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
            // The cursor outlives one call because the pieces are delivered
            // across several turns of the run loop; the box keeps it off the
            // captured variable list, which a @Sendable closure may not mutate.
            let cursor = PieceCursor()
            func sendNext() {
                guard let piece = cursor.take(from: reply.pieces) else {
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
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

    /// One piece of `size` bytes whose first five bytes are `tag`.
    ///
    /// The size matters: Foundation merges adjacent `URLProtocol` pieces that
    /// are smaller than about 256 bytes before the delegate sees them, so a
    /// tiny stub piece would never arrive as its own chunk. 1024 bytes is
    /// comfortably above that, and the tag keeps each piece identifiable.
    private func piece(_ tag: String, size: Int = 1024) -> Data {
        var data = Data(tag.utf8)
        data.append(Data(repeating: 0x20, count: max(0, size - data.count)))
        return data
    }

    /// The first five bytes of a piece, as text.
    private func tag(_ data: Data) -> String {
        String(decoding: data.prefix(5), as: UTF8.self)
    }

    private func request(_ url: String, id: Int64 = 1) -> URLSessionTransport.Request {
        URLSessionTransport.Request(id: id, method: "GET", url: URL(string: url)!,
                                    headers: [:], body: nil, useCookies: false, partition: "magpie")
    }

    /// The pieces are handed over before the body is finished.
    @Test func piecesArriveBeforeTheBodyEnds() async throws {
        let host = "stream.test"
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: [
            piece("one  "), piece("two  "), piece("three"),
        ]))
        let t = transport()
        let collector = ChunkRecorder()

        let response = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.map(tag) == ["one  ", "two  ", "three"])
        #expect(response.status == 200)
        #expect(response.body.count == 3 * 1024)
    }

    /// The first piece must arrive while the server is still writing, not after
    /// the last one. This is the difference between a stream and a whole reply.
    @Test func theFirstPieceArrivesWhileTheServerIsStillWriting() async throws {
        let host = "early.test"
        StreamStub.reply("https://\(host)/chat", with: .init(
            pieces: [piece("first"), piece("secnd")], gap: 0.3))
        let t = transport()

        let stamps = ArrivalStamps()
        let collector = ChunkRecorder(onPiece: { _ in stamps.mark() })
        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.count == 2)
        // The whole reply takes at least two gaps; the first piece must come
        // before the second one, so it cannot have waited for the end.
        let arrived = stamps.marks
        let total = arrived.last ?? .zero
        #expect(arrived.count == 2)
        #expect(total < .milliseconds(550))
        #expect(arrived.count == 2 && arrived[0] < arrived[1])
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
        // 20 pieces of 1024 bytes each: big enough that Foundation does not
        // merge them, and enough of them that an order bug would show.
        let expected = (0..<20).map { piece("p\(String(format: "%03d", $0))") }
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: expected, gap: 0.001))
        let t = transport()
        let collector = ChunkRecorder()

        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.map(tag) == expected.map(tag))
        #expect(collector.pieces.count == 20)
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

/// Hands out the pieces of a reply one at a time.
///
/// The cursor lives in an object because the pieces are delivered across
/// several turns of the run loop, and a `@Sendable` closure may not mutate a
/// captured variable.
final class PieceCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func take(from pieces: [Data]) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard index < pieces.count else { return nil }
        let piece = pieces[index]
        index += 1
        return piece
    }
}

/// Records when each piece arrived, relative to the first.
final class ArrivalStamps: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var stored: [Duration] = []

    func mark() {
        let now = ContinuousClock.now
        lock.lock(); defer { lock.unlock() }
        stored.append(now - start)
    }

    var marks: [Duration] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
