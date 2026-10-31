import Foundation
import Testing
@testable import NekularityKit

/// Serves one image slowly, in pieces, and records how much of it was handed over.
/// A cancelled download is visible as a byte count rather than as a timing guess.
final class SlowImageStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var delivered: [String: Int] = [:]
    nonisolated(unsafe) private static var started: [String] = []

    static func serve(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        body = data
    }

    static func bytesDelivered(host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return delivered[host] ?? 0
    }

    static func starts(host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return started.filter { $0 == host }.count
    }

    private static func piece() -> Data {
        lock.lock(); defer { lock.unlock() }
        return body
    }

    private static func addDelivered(host: String, _ n: Int) {
        lock.lock(); defer { lock.unlock() }
        delivered[host, default: 0] += n
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let host = url.host ?? ""
        Self.lock.lock(); Self.started.append(host); Self.lock.unlock()
        let image = Self.piece()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Ten pieces with a pause between them: long enough that a cancel lands
        // while the download is still running.
        let piece = max(1, image.count / 10)
        let pieces = stride(from: 0, to: image.count, by: piece).map { image[$0..<min($0 + piece, image.count)] }
        Task { @Sendable [weak self] in
            guard let self else { return }
            for part in pieces {
                guard !self.stopped else { return }
                self.client?.urlProtocol(self, didLoad: part)
                Self.addDelivered(host: host, part.count)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var stopped = false
    override func stopLoading() { stopped = true }
}

@Suite("ImageLoaderSharing")
struct ImageLoaderSharingTests {
    /// A 1×1 PNG: enough for the decoder to succeed, small enough to inline.
    private static let png = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """.trimmingCharacters(in: .whitespacesAndNewlines))!

    private func loader() throws -> ImageLoader {
        let jars = CookieJars(file: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowImageStub.self]
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1",
                                           timeout: 5, configuration: config)
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "nk-test/1"), host: host)
        return ImageLoader(core: core)
    }

    /// Every image request in this test file uses its own host, because the stub's
    /// tables are shared between tests running in parallel.
    private func key(_ host: String) -> ImageLoader.Key {
        ImageLoader.Key(source: "not-installed-\(host)", url: "https://\(host)/one.png", isThumbnail: true)
    }

    /// A download shared with nobody must stop when its only waiter leaves. Left
    /// running it holds a connection and a buffer for an image no screen shows.
    @Test func theLastWaiterLeavingStopsTheDownload() async throws {
        let host = "last-waiter.test"
        SlowImageStub.serve(Self.png)
        let images = try loader()

        let task = Task { try await images.image(key(host), maxWidth: 64) }
        // Let the request reach the stub before it is cancelled.
        try await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()
        _ = try? await task.value
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(SlowImageStub.bytesDelivered(host: host) < Self.png.count)
    }

    /// Two cells can show the same image; one going away must not abort the other.
    @Test func oneWaiterLeavingDoesNotStopTheOther() async throws {
        let host = "two-waiters.test"
        SlowImageStub.serve(Self.png)
        let images = try loader()

        let first = Task { try await images.image(key(host), maxWidth: 64) }
        try await Task.sleep(nanoseconds: 60_000_000)
        let second = Task { try await images.image(key(host), maxWidth: 64) }
        try await Task.sleep(nanoseconds: 30_000_000)
        first.cancel()
        _ = try? await first.value

        let image = try await second.value
        #expect(image.image.width == 1)
        // One download, not two: the second waiter joined the first.
        #expect(SlowImageStub.starts(host: host) == 1)
    }
}
