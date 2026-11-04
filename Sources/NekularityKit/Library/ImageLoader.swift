import Foundation
import ImageIO
import CoreGraphics

/// Loads comic images with each source's request rules.
///
/// Sources often need a Referer or cookies for images, which `AsyncImage`
/// cannot send, so images go through the source's own transport partition.
/// Decoded images are cached in memory and downsampled to the size the
/// screen needs.
public actor ImageLoader {
    public struct Key: Hashable, Sendable {
        public var source: String
        public var url: String
        public var comicID: String?
        public var chapterID: String?
        /// Covers use onThumbnailLoad, pages onImageLoad.
        public var isThumbnail: Bool

        public init(source: String, url: String, comicID: String? = nil, chapterID: String? = nil, isThumbnail: Bool) {
            self.source = source; self.url = url; self.comicID = comicID; self.chapterID = chapterID; self.isThumbnail = isThumbnail
        }
    }

    private let core: CoreClient
    /// Where a downloaded copy may come from. Asked before the network, so a
    /// chapter that was downloaded opens with no connection at all.
    private let offline: (@Sendable (Key) async -> Data?)?
    private let cache = NSCache<NSString, CGImageBox>()
    private var inFlight: [CacheKey: SharedLoad] = [:]
    private var nextID: Int64 = 1 << 40 // distinct from Core's request ids

    struct CacheKey: Hashable { var key: Key; var limit: Limit }

    /// One download shared by every caller that asked for the same image.
    ///
    /// The download outlives the caller that started it, but not every caller:
    /// the last one to give up cancels it. Cancelling it for one waiter would
    /// abort an image another visible cell is still waiting for.
    private final class SharedLoad {
        let task: Task<CGImageBox, Error>
        var waiters = 0
        init(task: Task<CGImageBox, Error>) { self.task = task }
    }

    /// Drops the entry only when it is still the download this call started: a
    /// cancelled call may already have been replaced by a newer one, and
    /// clearing that would hand every later caller a fresh download.
    private func clear(_ ck: CacheKey, _ load: SharedLoad) {
        if inFlight[ck] === load { inFlight[ck] = nil }
    }

    /// Decrements the waiter count and cancels the download when nobody is left.
    private func release(_ ck: CacheKey) {
        guard let shared = inFlight[ck] else { return }
        shared.waiters -= 1
        guard shared.waiters <= 0 else { return }
        inFlight[ck] = nil
        shared.task.cancel()
    }

    /// Connects archive lookup and retries without retaining the environment in
    /// a cycle. The archive keeps the loader alive for retrying a saved failure;
    /// the loader must therefore borrow the archive for offline reads.
    @MainActor
    public static func forDownloads(core: CoreClient, downloads: DownloadStore) -> ImageLoader {
        let images = ImageLoader(core: core, offline: { [weak downloads] key in
            await downloads?.bytes(for: key)
        })
        downloads.fallbackFetch = { try await images.raw($0) }
        return images
    }

    public init(core: CoreClient, memoryLimitBytes: Int = 128 << 20,
                offline: (@Sendable (Key) async -> Data?)? = nil) {
        self.core = core
        self.offline = offline
        cache.totalCostLimit = memoryLimitBytes
    }

    /// The image for key at most maxWidth pixels wide. Tall strips keep
    /// their full height up to 16384 pixels.
    public func image(_ key: Key, maxWidth: Int) async throws -> CGImageBox {
        try await image(key, limit: .width(maxWidth))
    }

    /// The image for key, scaled so its longer side is at most maxPixel.
    public func image(_ key: Key, maxPixel: Int) async throws -> CGImageBox {
        try await image(key, limit: .longerSide(maxPixel))
    }

    enum Limit: Hashable, Sendable {
        case width(Int)
        case longerSide(Int)
    }

    private func image(_ key: Key, limit: Limit) async throws -> CGImageBox {
        let ck = CacheKey(key: key, limit: limit)
        let name = "\(key.source)|\(key.isThumbnail)|\(key.comicID ?? "")|\(key.chapterID ?? "")|\(key.url)|\(limit)" as NSString
        if let hit = cache.object(forKey: name) { return hit }
        if let running = inFlight[ck] {
            running.waiters += 1
            return try await withTaskCancellationHandler {
                try await running.task.value
            } onCancel: {
                Task { await self.giveUp(ck) }
            }
        }

        nextID += 1
        let id = nextID
        let core = self.core
        let task = Task<CGImageBox, Error> {
            var req: ImageRequest
            if key.isThumbnail {
                req = try await core.thumbnailRequest(key: key.source, url: key.url)
            } else {
                req = try await core.imageRequest(key: key.source, url: key.url, comicID: key.comicID ?? "", chapterID: key.chapterID)
            }
            let partition = CookiePartition.comic(key.source)
            let base = core.host.transport.scheme(partition: partition)
            // A source may name several mirrors and a body transform, and both
            // live in its runtime behind `req.handle`. A mirror that answers
            // with an error page, or a body that will not decode, is what the
            // official client calls a failed load, so it asks for the next one.
            var lastError: Error = CoreError("not an image")
            for _ in 0..<4 {
                do {
                    var body: Data
                    if let offline, let saved = await offline(key) {
                        // The archive stores bytes after onResponse. They are
                        // already final: running the source's transform again
                        // would decrypt/rewrite a readable PNG a second time.
                        body = saved
                    } else {
                        body = try await Self.fetch(req, id: id, partition: partition, base: base, core: core)
                        if req.has("onLoadFailed"), Self.looksLikeHTML(body) {
                            throw CoreError("image response is an HTML page")
                        }
                        if !req.handle.isEmpty, req.has("onResponse"),
                           let rewritten = try await core.applyImageResponse(key: key.source, handle: req.handle, body: body) {
                            // The bytes are the source's now, so nothing may assume
                            // they are what the server described.
                            body = rewritten
                        }
                    }
                    guard let decoded = Self.decode(body, limit: limit) else { throw CoreError("not an image") }
                    // A source may ask for a pixel pass — jm reorders the blocks
                    // of a long strip, others rotate a page. iOS has no JS, so
                    // Core runs the script over the pixels.
                    var image = decoded
                    if !req.modifyImage.isEmpty,
                       let fixed = try await Self.pixelPass(req.modifyImage, decoded, source: key.source, core: core) {
                        image = fixed
                    }
                    return CGImageBox(image)
                } catch {
                    lastError = error
                    guard req.has("onLoadFailed"),
                          let next = try? await core.imageFallback(key: key.source, handle: req.handle) else { throw error }
                    req = next
                }
            }
            throw lastError
        }
        let shared = SharedLoad(task: task)
        shared.waiters = 1
        inFlight[ck] = shared
        return try await withTaskCancellationHandler {
            do {
                let box = try await task.value
                cache.setObject(box, forKey: name, cost: box.image.bytesPerRow * box.image.height)
                clear(ck, shared)
                return box
            } catch {
                // A failure must not stay in the table: the entry would hand
                // every later caller the same finished task, so one bad
                // response would make that image unloadable until the app
                // restarts.
                clear(ck, shared)
                throw error
            }
        } onCancel: {
            Task { await self.giveUp(ck) }
        }
    }

    /// Called when a waiter's task is cancelled. The loader is an actor, so the
    /// count is adjusted in one place whatever thread cancelled.
    private func giveUp(_ ck: CacheKey) {
        release(ck)
    }

    /// The bytes the source would hand the reader, without decoding them.
    ///
    /// The downloader needs exactly what the reader gets — the same request
    /// rules and the same response callback — but saves the file instead of
    /// drawing it. The returned bytes are **after** `onResponse`; the archive
    /// contract is that offline reads decode them directly and never run that
    /// callback again. A mirror that fails, or a body that cannot decode, is
    /// still followed to the next one.
    public func raw(_ key: Key) async throws -> Data {
        var req: ImageRequest
        if key.isThumbnail {
            req = try await core.thumbnailRequest(key: key.source, url: key.url)
        } else {
            req = try await core.imageRequest(key: key.source, url: key.url,
                                              comicID: key.comicID ?? "", chapterID: key.chapterID)
        }
        let partition = CookiePartition.comic(key.source)
        let base = core.host.transport.scheme(partition: partition)
        var lastError: Error = CoreError("not an image")
        for _ in 0..<4 {
            do {
                var body = try await Self.fetch(req, id: 0, partition: partition, base: base, core: core)
                if req.has("onLoadFailed"), Self.looksLikeHTML(body) {
                    throw CoreError("image response is an HTML page")
                }
                if !req.handle.isEmpty, req.has("onResponse"),
                   let rewritten = try await core.applyImageResponse(key: key.source, handle: req.handle, body: body) {
                    body = rewritten
                }
                // Saving an undecodable body would mark a chapter complete that
                // the reader cannot open. Validate with a tiny thumbnail, not a
                // full-resolution bitmap; the bytes themselves stay untouched.
                guard Self.isImage(body) else { throw CoreError("not an image") }
                return body
            } catch {
                lastError = error
                guard req.has("onLoadFailed"),
                      let next = try? await core.imageFallback(key: key.source, handle: req.handle) else { throw error }
                req = next
            }
        }
        throw lastError
    }

    /// One hop: the request as the source described it.
    private static func fetch(_ req: ImageRequest, id: Int64, partition: String, base: String, core: CoreClient) async throws -> Data {
        // A source may hand back an image address without its scheme, such as
        // "//images.example.com/1.jpg". RFC 3986 says such an address inherits
        // the scheme of the page, so the scheme this source last used is the one
        // to use. The address still has to be http(s): Core's rule leaves
        // file://, javascript: and ftp:// alone.
        let normalized = base.isEmpty ? req.url : core.normalizeURL(req.url, base: base + "://")
        guard let url = URL(string: normalized) else { throw CoreError("invalid image URL \(normalized)") }
        // The comment above is only true if it is enforced here: nothing below
        // this line rejects a scheme, and URLSession would happily read a
        // `file:` address off this device.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw CoreError("image URL must be http or https: \(normalized)")
        }
        var headers = req.headers.mapValues { [$0] }
        if headers.keys.first(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) == nil {
            headers["Accept"] = ["image/avif,image/webp,image/*,*/*;q=0.8"]
        }
        let resp = try await core.host.transport.send(.init(
            id: id, method: req.method, url: url, headers: headers, body: req.body.map { Data($0.utf8) },
            useCookies: true, partition: partition))
        guard (200..<300).contains(resp.status) else { throw CoreError("image HTTP \(resp.status)") }
        return resp.body
    }

    /// Whether the body can produce a picture. A thumbnail decode is enough to
    /// reject HTML, empty bodies and corrupt bytes without allocating the full
    /// page; valid bytes are returned unchanged by `raw`.
    static func isImage(_ data: Data) -> Bool {
        decode(data, limit: .longerSide(64)) != nil
    }

    /// Whether a body is a web page rather than an image. A mirror that is out
    /// of quota answers 200 with an error page, and only the source knows
    /// another mirror.
    static func looksLikeHTML(_ data: Data) -> Bool {
        let head = data.prefix(512)
        let text = String(decoding: head, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for prefix in ["<!doctype html", "<html", "<?xml", "<head", "<body"] where text.hasPrefix(prefix) {
            return true
        }
        return false
    }

    /// Runs the source's modifyImage script over a decoded picture.
    ///
    /// The pixels go to Core as straight RGBA and come back the same way, so
    /// nothing here assumes a colour space beyond sRGB. A picture too large to
    /// hand over is left as it is rather than failing the page.
    static func pixelPass(_ script: String, _ image: CGImage, source: String, core: CoreClient) async throws -> CGImage? {
        let w = image.width, h = image.height
        guard Self.pixelPassFits(w, h) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let out = try await core.modifyImage(key: source, script: script, width: w, height: h,
                                             rgba: Data(pixels))
        guard out.width > 0, out.height > 0, out.rgba.count == out.width * out.height * 4 else { return nil }
        var result = [UInt8](out.rgba)
        guard let back = CGContext(data: &result, width: out.width, height: out.height, bitsPerComponent: 8,
                                   bytesPerRow: out.width * 4, space: space, bitmapInfo: info) else { return nil }
        return back.makeImage()
    }

    /// Whether a picture is small enough to hand to Core.
    ///
    /// The pixels cross as RGBA and again as base64, so one pass peaks at
    /// roughly w·h·4 × 2.7. A long strip at 1080×16384 is 17.7M pixels, about
    /// 190 MB; the cap sits just above that and well under what a phone grants
    /// an app. A bigger picture is passed through unmodified rather than
    /// risking the process.
    static func pixelPassFits(_ width: Int, _ height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        // 24,000,000 pixels, not 24 Mi: the boundary the tests and the docs talk
        // about is 3000×8000, which is exactly this number.
        // Compared in division form so a huge width cannot overflow the product.
        return width <= 24_000_000 / height
    }

    /// Decodes and downsamples without decoding the full-size bitmap first.
    static func decode(_ data: Data, limit: Limit) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let maxPixel: Int
        switch limit {
        case .longerSide(let n):
            maxPixel = n
        case .width(let w):
            // The thumbnail API limits the longer side; derive it from the
            // aspect ratio so the width comes out at w.
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? w
            let ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? w
            guard pw > 0, ph > 0 else { return nil }
            let target = min(pw, w)
            maxPixel = min(16384, max(target, Int((Double(target) * Double(ph) / Double(pw)).rounded(.up))))
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// A decoded image that can cross actor boundaries. CGImage is immutable,
/// so sharing it is safe.
public final class CGImageBox: @unchecked Sendable {
    public let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
