import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NekularityKit

/// A private transport for these tests: the fixture body is keyed by the full
/// URL, so parallel suites cannot overwrite one another's bytes the way a single
/// shared static body can.
final class ImageIntegrityStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String: Data] = [:]
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func serve(_ url: String, _ body: Data) {
        lock.lock(); defer { lock.unlock() }
        bodies[url] = body
    }

    static func requests(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url] ?? 0
    }

    private static func body(_ url: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        counts[url, default: 0] += 1
        return bodies[url]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let data = Self.body(url.absoluteString) ?? Data("missing fixture".utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Real Core runs the source's JavaScript callbacks; the transport only replaces
/// HTTP. No shared Core, source store or simulator state is used.
@MainActor
@Suite("Image integrity", .serialized)
struct ImageIntegrityTests {
    private func png(width: Int = 8, height: Int = 8) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func inverted(_ data: Data) -> Data {
        Data(data.map { 255 - $0 })
    }

    private func environment(script: String) async throws -> (ImageLoader, CoreClient, String, URL) {
        try await environment { _ in script }
    }

    private func environment(scriptForHost: (String) -> String) async throws -> (ImageLoader, CoreClient, String, URL) {
        let suffix = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let host = "image-integrity-\(suffix).test"
        let root = FileManager.default.temporaryDirectory
            .appending(path: "image-integrity-\(UUID().uuidString)")
        let jars = CookieJars(file: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageIntegrityStub.self]
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-image-test/1",
                                            timeout: 5, configuration: configuration)
        let coreHost = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "nk-image-test/1"), host: coreHost)
        _ = try await core.installComicSource(scriptForHost(host), origin: "test")
        return (ImageLoader(core: core), core, host, root)
    }

    private func key(_ host: String, _ path: String, source: String) -> ImageLoader.Key {
        ImageLoader.Key(source: source, url: "https://\(host)/\(path)",
                        comicID: "comic", chapterID: "chapter", isThumbnail: false)
    }

    private func source(key: String, transform: Bool = false, fallback: String? = nil,
                        modify: Bool = false) -> String {
        let callback = transform ? """
        ,
            onResponse: (data) => {
                const a = new Uint8Array(data)
                for (let i = 0; i < a.length; i++) a[i] = 255 - a[i]
                return a.buffer
            }
        """ : ""
        let failure = fallback.map { """
        ,
            onLoadFailed: () => ({url: "\($0)"})
        """ } ?? ""
        let modifyField = modify ? #", modifyImage: "let modifyImage = (image) => image.copyAndRotate90()""# : ""
        return """
        class Integrity\(key) extends ComicSource {
            name = "Integrity \(key)"
            key = "\(key)"
            version = "1.0.0"
            search = { load: async () => ({comics: [], maxPage: 1}) }
            comic = {
                loadInfo: async (id) => ({id: id, title: "Integrity", chapters: {}}),
                onImageLoad: (url) => ({url: url\(callback)\(failure)\(modifyField)})
            }
        }
        """
    }

    private func waitForDownload(_ store: DownloadStore, _ id: String, failure: Bool) async -> Bool {
        for _ in 0..<300 {
            if failure ? store.failures[id] != nil : store.chapters[id] != nil { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return failure ? store.failures[id] != nil : store.chapters[id] != nil
    }

    /// The regression: raw saves the bytes after onResponse, but the offline
    /// reader used to feed those already-final bytes back into onResponse. The
    /// inverse transform turned a valid PNG into garbage on the second pass.
    @Test func offlineBytesAreNotPassedThroughOnResponseAgain() async throws {
        let original = png()
        let served = inverted(original)
        let (loader, core, host, root) = try await environment(script: source(key: "integrity_offline", transform: true))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://\(host)/scrambled.png"
        ImageIntegrityStub.serve(url, served)
        let page = ImageLoader.Key(source: "integrity_offline", url: url,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)

        // Online: the transform runs once and the reader decodes the result.
        let online = try await loader.image(page, maxWidth: 64)
        #expect(online.image.width == 8)
        // The same online path's saved bytes are the readable PNG.
        let saved = try await loader.raw(page)
        #expect(saved == original)

        let downloads = DownloadStore(root: root.appending(path: "downloads"))
        let request = DownloadStore.Request(sourceKey: "integrity_offline", comicID: "comic",
                                            comicTitle: "Integrity", chapterID: "chapter",
                                            chapterTitle: "Chapter", pages: [url])
        downloads.download(request) { key in try await loader.raw(key) }
        #expect(await waitForDownload(downloads, request.id, failure: false))
        #expect(downloads.bytes(for: page) == original)

        // Offline: the archive is asked first. If onResponse runs again, the
        // valid PNG becomes non-decodable and this call throws.
        ImageIntegrityStub.serve(url, Data("the network must not be used".utf8))
        let before = ImageIntegrityStub.requests(url)
        let offline = ImageLoader.forDownloads(core: core, downloads: downloads)
        let image = try await offline.image(page, maxWidth: 64)
        #expect(image.image.width > 0)
        #expect(ImageIntegrityStub.requests(url) == before, "offline read touched the network")
    }

    /// Offline reading skips onResponse, not the decoded pixel pass: a source
    /// that rotates pages still gets its modifyImage callback after the archive
    /// is decoded.
    @Test func offlineStillRunsModifyImageAfterDecode() async throws {
        let original = png(width: 8, height: 4)
        let (loader, core, host, root) = try await environment(
            script: source(key: "integrity_modify", modify: true))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://\(host)/rotate.png"
        ImageIntegrityStub.serve(url, original)
        let page = ImageLoader.Key(source: "integrity_modify", url: url,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)
        #expect(try await loader.raw(page) == original)

        let downloads = DownloadStore(root: root.appending(path: "downloads"))
        let request = DownloadStore.Request(sourceKey: "integrity_modify", comicID: "comic",
                                            comicTitle: "Integrity", chapterID: "chapter",
                                            chapterTitle: "Chapter", pages: [url])
        downloads.download(request) { key in try await loader.raw(key) }
        #expect(await waitForDownload(downloads, request.id, failure: false))

        let offline = ImageLoader.forDownloads(core: core, downloads: downloads)
        let image = try await offline.image(page, maxWidth: 64)
        #expect(image.image.width == 4)
        #expect(image.image.height == 8)
    }

    /// A valid response is not altered by the new check.
    @Test func rawKeepsValidImageBytesUnchanged() async throws {
        let original = png(width: 16, height: 12)
        let (loader, _, host, root) = try await environment(script: source(key: "integrity_valid"))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://\(host)/plain.png"
        ImageIntegrityStub.serve(url, original)
        let page = ImageLoader.Key(source: "integrity_valid", url: url,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)
        #expect(try await loader.raw(page) == original)
    }

    /// The validation pass must accept the other common page format too: a
    /// thumbnail decode is not PNG-only.
    @Test func rawAcceptsJPEGBytes() async throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 12, height: 9, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 9))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        let jpeg = data as Data
        #expect(ImageLoader.isImage(jpeg))

        let (loader, _, host, root) = try await environment(script: source(key: "integrity_jpeg"))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://\(host)/page.jpg"
        ImageIntegrityStub.serve(url, jpeg)
        let page = ImageLoader.Key(source: "integrity_jpeg", url: url,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)
        #expect(try await loader.raw(page) == jpeg)
    }

    /// HTTP 200 garbage is a failed page, not a completed download. With no
    /// onLoadFailed the store keeps a retryable failure; after the server recovers
    /// the same request succeeds.
    @Test func garbageIsRejectedAndRetrySucceedsAfterRecovery() async throws {
        let good = png()
        let (loader, _, host, root) = try await environment(script: source(key: "integrity_retry"))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "https://\(host)/page.png"
        ImageIntegrityStub.serve(url, Data("not a decodable image".utf8))
        let page = ImageLoader.Key(source: "integrity_retry", url: url,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)

        await #expect(throws: Error.self) { try await loader.raw(page) }

        let downloads = DownloadStore(root: root.appending(path: "downloads"))
        let request = DownloadStore.Request(sourceKey: "integrity_retry", comicID: "comic",
                                            comicTitle: "Integrity", chapterID: "chapter",
                                            chapterTitle: "Chapter", pages: [url])
        downloads.download(request) { key in try await loader.raw(key) }
        #expect(await waitForDownload(downloads, request.id, failure: true))
        #expect(downloads.chapters[request.id] == nil)

        ImageIntegrityStub.serve(url, good)
        downloads.retry(request.id)
        #expect(await waitForDownload(downloads, request.id, failure: false))
        #expect(downloads.bytes(for: page) == good)
    }

    /// A bad first address is followed through Core's onLoadFailed to a good
    /// mirror, and the mirror's valid bytes are saved unchanged.
    @Test func rawFollowsOnLoadFailedToAValidMirror() async throws {
        let good = png(width: 12, height: 9)
        let (loader, _, host, root) = try await environment { host in
            let mirror = "https://\(host)/mirror.png"
            return source(key: "integrity_mirror", fallback: mirror)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = "https://\(host)/bad.png"
        let mirror = "https://\(host)/mirror.png"
        ImageIntegrityStub.serve(bad, Data("bad".utf8))
        ImageIntegrityStub.serve(mirror, good)
        let page = ImageLoader.Key(source: "integrity_mirror", url: bad,
                                   comicID: "comic", chapterID: "chapter", isThumbnail: false)
        #expect(try await loader.raw(page) == good)
        #expect(ImageIntegrityStub.requests(bad) == 1)
        #expect(ImageIntegrityStub.requests(mirror) == 1)
    }
}
