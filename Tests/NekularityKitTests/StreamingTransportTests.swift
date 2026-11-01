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
        var headers = reply.headers
        headers["Content-Length"] = String(reply.pieces.reduce(0) { $0 + $1.count })
        let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // The pieces are delivered one at a time with a pause in between, so a
        // whole-reply transport cannot produce anything before the last one.
        // The cursor lives in a box: the loop crosses `Task.sleep`, and a
        // captured `var` cannot cross it under Swift 6.
        let cursor = PieceCursor(pieces: reply.pieces, gap: reply.gap)
        Task { @Sendable [weak self] in
            guard let self else { return }
            while let piece = cursor.next() {
                self.client?.urlProtocol(self, didLoad: piece)
                Self.record(url, piece)
                if reply.gap > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(reply.gap * 1_000_000_000))
                }
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Hands the pieces out one at a time, whatever queue asks.
final class PieceCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let pieces: [Data]
    private let gap: TimeInterval
    private var index = 0

    init(pieces: [Data], gap: TimeInterval) {
        self.pieces = pieces
        self.gap = gap
    }

    func next() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard index < pieces.count else { return nil }
        let piece = pieces[index]
        index += 1
        return piece
    }
}

/// A piece big enough that URLSession does not merge it with its neighbour.
///
/// Foundation coalesces small `URLProtocol` pieces before the data delegate sees
/// them: measured on this simulator SDK, 16/64 B arrive as one piece and 256 B as
/// two out of three. 1 KiB is above the threshold and keeps the tests about the
/// transport rather than about Foundation's batching.
private let pieceSize = 1024

/// A piece of `pieceSize` bytes, tagged so the order is checkable.
private func piece(_ tag: String) -> Data {
    var data = Data(tag.utf8)
    data.append(Data(repeating: 0x20, count: max(0, pieceSize - data.count)))
    return data
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
            piece("one"), piece("two"), piece("three"),
        ]))
        let t = transport()
        let collector = ChunkRecorder()

        let response = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.count == 3)
        // Each piece starts with its tag; the rest is padding that keeps it
        // above Foundation's batching threshold.
        #expect(collector.pieces.map { String(decoding: $0.prefix(5), as: UTF8.self).trimmingCharacters(in: .whitespaces) }
            == ["one", "two", "three"])
        #expect(response.body.count == 3 * pieceSize)
        #expect(response.status == 200)
    }

    /// The first piece must arrive while the server is still writing, not after
    /// the last one. This is the difference between a stream and a whole reply.
    @Test func theFirstPieceArrivesWhileTheServerIsStillWriting() async throws {
        let host = "early.test"
        StreamStub.reply("https://\(host)/chat", with: .init(
            pieces: [piece("first"), piece("second")], gap: 0.3))
        let t = transport()

        let firstAt = ContinuousClock.now
        // `arrived` is written from the transport's callback queue and read on
        // this one, so it lives behind the recorder's lock rather than in a
        // captured var — Swift 6 refuses a captured var that two queues touch.
        let stamps = ArrivalStamps()
        let collector = ChunkRecorder(onPiece: { _ in stamps.append(.now - firstAt) })
        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        #expect(collector.pieces.count == 2)
        // The whole reply takes at least two gaps; the first piece must come
        // before the second one, so it cannot have waited for the end.
        let arrived = stamps.values
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
        let expected = (0..<20).map { i -> Data in
            var d = Data("p\(i)".utf8)
            d.append(Data(repeating: 0x20, count: max(0, pieceSize - d.count)))
            return d
        }
        StreamStub.reply("https://\(host)/chat", with: .init(pieces: expected, gap: 0.001))
        let t = transport()
        let collector = ChunkRecorder()

        _ = try await t.sendStreaming(request("https://\(host)/chat")) { data in
            collector.append(data)
        }

        // The order is what the case is named for; the boundaries are the
        // transport's to choose. It arrived as [2048, 1024, …] once, which is two
        // pieces handed over together — not a reordering — and asserting the
        // framing made this fail for a reason that is not a bug.
        let joined = collector.pieces.reduce(into: Data()) { $0.append($1) }
        let wanted = expected.reduce(into: Data()) { $0.append($1) }
        #expect(joined == wanted)
        #expect(collector.pieces.allSatisfy { !$0.isEmpty })
    }
}

/// Records when each piece arrived, behind a lock because the transport calls
/// back on its own queue.
final class ArrivalStamps: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Duration] = []

    func append(_ d: Duration) {
        lock.lock(); defer { lock.unlock() }
        stored.append(d)
    }

    var values: [Duration] {
        lock.lock(); defer { lock.unlock() }
        return stored
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
