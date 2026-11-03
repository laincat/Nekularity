import Foundation
import Testing
@testable import NekularityKit

/// Holds the body until the test has observed the response head. Cancellation
/// wakes the producer as well, so a failing timing assertion cannot leak it.
private final class HeldBody: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var cancelled = false
    let status: Int
    let body = Data("body released by the test".utf8)

    init(status: Int) { self.status = status }

    var wasReleased: Bool {
        condition.lock(); defer { condition.unlock() }
        return released
    }

    func release() {
        condition.lock(); defer { condition.unlock() }
        released = true
        condition.broadcast()
    }

    func cancel() {
        condition.lock(); defer { condition.unlock() }
        cancelled = true
        condition.broadcast()
    }

    func waitForBody() -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(5)
        while !released && !cancelled {
            if !condition.wait(until: deadline) { return false }
        }
        return released && !cancelled
    }

    func waitForCancellation() -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(2)
        while !cancelled {
            if !condition.wait(until: deadline) { return false }
        }
        return true
    }
}

private final class HeadGateProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [URL: HeldBody] = [:]

    static func install(_ reply: HeldBody, at url: URL) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }
    static func remove(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = nil
    }
    static func reply(at url: URL) -> HeldBody? {
        lock.lock(); defer { lock.unlock() }
        return replies[url]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = Self.reply(at: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["X-Fixture": "ready", "Content-Length": String(reply.body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async { [self] in
            guard reply.waitForBody() else { return }
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        guard let url = request.url else { return }
        Self.reply(at: url)?.cancel()
    }
}

@Suite("Core stream response heads")
struct CoreStreamHeadTests {
    private struct Opened: Decodable { var id: Int64 }
    private struct Chunk: Decodable, Sendable {
        var done: Bool
        var chunkBase64: String?
        var status: Int?
        var headers: [String: [String]]?
        var finalUrl: String?
        var error: String?
    }

    private func open(status: Int) throws -> (CoreStreamHost, Int64, URL, HeldBody) {
        let url = URL(string: "https://head-\(UUID().uuidString.lowercased()).test/reply")!
        let reply = HeldBody(status: status)
        HeadGateProtocol.install(reply, at: url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeadGateProtocol.self]
        let transport = URLSessionTransport(cookies: CookieJars(file: nil), defaultUserAgent: "nk-test/1",
                                            timeout: 5, configuration: configuration)
        let host = CoreStreamHost(transport: transport)
        let wire = try JSONSerialization.data(withJSONObject: ["id": 1, "method": "GET",
                                                               "url": url.absoluteString, "partition": "magpie"])
        var failure: NSError?
        let raw = host.streamOpen(String(decoding: wire, as: UTF8.self), error: &failure)
        if let failure { throw failure }
        let id = try JSONDecoder().decode(Opened.self, from: Data(raw.utf8)).id
        return (host, id, url, reply)
    }

    private func next(_ host: CoreStreamHost, _ id: Int64) async throws -> Chunk {
        // streamNext blocks by contract. The watchdog closes that exact stream
        // if the response head is accidentally held until the body completes.
        let watchdog = Task.detached {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            host.streamClose(id)
        }
        defer { watchdog.cancel() }
        return try await Task.detached {
            var failure: NSError?
            let raw = host.streamNext(id, error: &failure)
            if let failure { throw failure }
            return try JSONDecoder().decode(Chunk.self, from: Data(raw.utf8))
        }.value
    }

    @Test func responseHeadPrecedesHeldBody() async throws {
        try await verifyHead(status: 201)
    }

    @Test func errorResponseHeadPrecedesHeldBody() async throws {
        try await verifyHead(status: 503)
    }

    private func verifyHead(status: Int) async throws {
        let (host, id, url, reply) = try open(status: status)
        defer { host.streamClose(id); reply.cancel(); HeadGateProtocol.remove(url) }
        let head = try await next(host, id)
        try #require(!head.done)
        #expect(head.chunkBase64 == nil)
        #expect(head.status == status)
        #expect(head.finalUrl == url.absoluteString)
        #expect(head.headers?.first { $0.key.lowercased() == "x-fixture" }?.value == ["ready"])
        #expect(!reply.wasReleased)

        reply.release()
        var body = Data()
        for _ in 0..<8 {
            let chunk = try await next(host, id)
            if let encoded = chunk.chunkBase64 { body.append(try #require(Data(base64Encoded: encoded))) }
            if chunk.done {
                #expect(chunk.status == status)
                #expect(chunk.finalUrl == head.finalUrl)
                #expect(chunk.headers == head.headers)
                #expect(chunk.error == nil)
                #expect(body == reply.body)
                return
            }
        }
        Issue.record("stream did not end after the held body was released")
    }

    @Test func cancellationAfterHeadStopsHeldBody() async throws {
        let (host, id, url, reply) = try open(status: 200)
        defer { host.streamClose(id); reply.cancel(); HeadGateProtocol.remove(url) }
        let head = try await next(host, id)
        try #require(!head.done && head.status == 200)
        host.streamClose(id)
        #expect(reply.waitForCancellation())
        #expect(!reply.wasReleased)
    }
}
