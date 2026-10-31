import Foundation
import Testing
@testable import NekularityKit

/// A stub that hands the body over in pieces, so the streaming path can be
/// checked without a server that keeps a connection open.
///
/// The pieces arrive with a pause between them, which is what makes the
/// difference between "the reply arrived whole" and "the reply arrived as it
/// was written" visible: a whole-reply transport cannot hand anything over
/// until the last piece is done.
final class StreamStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var pieces: [Data] = []
        /// The pause between two pieces.
        var gap: TimeInterval = 0.02
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var chunks: [String: [Data]] = [:]

    static func reply(_ url: String, with reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    static func lookup(_ url: URL) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        return replies[url.absoluteString]
    }

    static func record(_ url: URL, _ piece: Data) {
        lock.lock(); defer { lock.unlock() }
        chunks[url.absoluteString, default: []].append(piece)
    }

    /// The pieces this test's server sent, in order.
    static func sent(host: String) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return chunks.filter { URL(string: $0.key)?.host == host }.flatMap { $0.value }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let reply = Self.lookup(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let client = self.client
        let deliver: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            var headers = reply.headers
            headers["Content-Length"] = String(reply.pieces.reduce(0) { $0 + $1.count })
            let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            var index = 0
            func sendNext() {
                guard index < reply.pieces.count else {
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                let piece = reply.pieces[index]
                index += 1
                client?.urlProtocol(self, didLoad: piece)
                Self.record(url, piece)
                if reply.gap > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(reply.gap * 1_000_000_000))
                        sendNext()
                    }
                } else {
                    sendNext()
                }
            }
            sendNext()
        }
        deliver()
    }

    override func stopLoading() {}
}

@Suite("streaming transport")
struct StreamingTransportTests {
    private func transport() -> URLSessionTransport {
        let jars = CookieJars(file: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamStub.self]
        return URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1",
                                  timeout: 5, configuration: config)
    }

    private func request(_ url: String, id: Int64 = 1) -> URLSessionTransport.Request {
        URLSessionTransport.Request(id: id, method: "GET", url: URL(string: url)!,
                                    headers: [:], body: nil, useCookies: false, partition: "magpie")
    }

    /// The pieces are handed over before the body is finished.
    @Test func piecesArriveBeforeTheBodyEnds() async throws {
        let host = "stream.test"
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: [
            Data("one".utf8), Data("two".utf8), Data("three".utf8),
        ]))
        let t = transport()
        let collector = ChunkRecorder()

        let response = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.map { String(decoding: $0, as: UTF8.self) } == ["one", "two", "three"])
        #expect(String(decoding: response.body, as: UTF8.self) == "onetwothree")
        #expect(response.status == 200)
    }

    /// The first piece must arrive while the server is still writing, not after
    /// the last one. This is the difference between a stream and a whole reply.
    @Test func theFirstPieceArrivesWhileTheServerIsStillWriting() async throws {
        let host = "early.test"
        StreamStub.reply("https://\(host)/chat", with: .init(
            pieces: [Data("first".utf8), Data("second".utf8)], gap: 0.3))
        let t = transport()

        let firstAt = ContinuousClock.now
        var arrived: [Duration] = []
        let collector = ChunkRecorder(onPiece: { _ in arrived.append(.now - firstAt) })
        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.count == 2)
        // The whole reply takes at least two gaps; the first piece must come
        // before the second one, so it cannot have waited for the end.
        let total = arrived.last ?? .zero
        #expect(arrived.count == 2)
        #expect(total < .milliseconds(550))
        #expect(arrived[0] < arrived[1])
    }

    /// The head of the reply is known even when the body is empty.
    @Test func anEmptyBodyStillCarriesTheStatus() async throws {
        let host = "empty.test"
        StreamStub.reply("https://\(host)/chat", with: .init(status: 204, pieces: []))
        let t = transport()

        let response = try await t.sendStreaming(request("https://\(host)/chat")) { _ in }

        #expect(response.status == 204)
        #expect(response.body.isEmpty)
    }

    /// A body that does not fit is refused, the same as the whole-reply path.
    @Test func anOversizedBodyIsRefused() async throws {
        let host = "big.test"
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: [Data(repeating: 1, count: 4096)]))
        let t = transport()
        t.maxBodyBytes = 1024

        await #expect(throws: (any Error).self) {
            _ = try await t.sendStreaming(request("https://\(host)/chat")) { _ in }
        }
    }

    /// The pieces come in the order the server sent them.
    @Test func thePiecesKeepTheirOrder() async throws {
        let host = "order.test"
        let expected = (0..<20).map { Data("p\($0)".utf8) }
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: expected, gap: 0.001))
        let t = transport()
        let collector = ChunkRecorder()

        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces == expected)
    }
}

/// Collects the pieces a streaming call hands over.
final class ChunkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data] = []
    private let onPiece: (@Sendable (Data) -> Void)?

    init(onPiece: (@Sendable (Data) -> Void)? = nil) {
        self.onPiece = onPiece
    }

    var pieces: [Data] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func append(_ data: Data) {
        lock.lock()
        stored.append(data)
        lock.unlock()
        onPiece?(data)
    }
}
