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

    /// Decrements the waiter count and cancels the download when nobody is left.
    private func release(_ ck: CacheKey) {
        guard let shared = inFlight[ck] else { return }
        shared.waiters -= 1
        guard shared.waiters <= 0 else { return }
        inFlight[ck] = nil
        shared.task.cancel()
    }

    public init(core: CoreClient, memoryLimitBytes: Int = 128 << 20) {
        self.core = core
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
            let req: ImageRequest
            if key.isThumbnail {
                req = try await core.thumbnailRequest(key: key.source, url: key.url)
            } else {
                req = try await core.imageRequest(key: key.source, url: key.url, comicID: key.comicID ?? "", chapterID: key.chapterID)
            }
            // A source may hand back an image address without its scheme, such
            // as "//images.example.com/1.jpg". RFC 3986 says such an address
            // inherits the scheme of the page, so the scheme this source last
            // used is the one to use. The address still has to be http(s):
            // Core's rule leaves file://, javascript: and ftp:// alone.
            let partition = CookiePartition.comic(key.source)
            let base = core.host.transport.scheme(partition: partition)
            let normalized = base.isEmpty ? req.url : core.normalizeURL(req.url, base: base + "://")
            guard let url = URL(string: normalized) else { throw CoreError("invalid image URL \(normalized)") }
            var headers = req.headers.mapValues { [$0] }
            if headers.keys.first(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) == nil {
                headers["Accept"] = ["image/avif,image/webp,image/*,*/*;q=0.8"]
            }
            let resp = try await core.host.transport.send(.init(
                id: id, method: req.method, url: url, headers: headers, body: req.body.map { Data($0.utf8) },
                useCookies: true, partition: partition))
            guard (200..<300).contains(resp.status) else { throw CoreError("image HTTP \(resp.status)") }
            guard let image = Self.decode(resp.body, limit: limit) else { throw CoreError("not an image") }
            return CGImageBox(image)
        }
        let shared = SharedLoad(task: task)
        shared.waiters = 1
        inFlight[ck] = shared
        return try await withTaskCancellationHandler {
            let box = try await task.value
            inFlight[ck] = nil
            cache.setObject(box, forKey: name, cost: box.image.bytesPerRow * box.image.height)
            return box
        } onCancel: {
            Task { await self.giveUp(ck) }
        }
    }

    /// Called when a waiter's task is cancelled. The loader is an actor, so the
    /// count is adjusted in one place whatever thread cancelled.
    private func giveUp(_ ck: CacheKey) {
        release(ck)
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
