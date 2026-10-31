import Foundation
import Testing
@testable import NekularityKit

/// Answers requests from a table instead of the network, so the transport's own
/// cookie and cancellation rules can be checked without a server.
final class TransportStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var seen: [(url: URL, headers: [String: String])] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        replies = [:]
        seen = []
    }

    static func record(_ url: URL, _ headers: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        seen.append((url, headers))
    }

    static func requests() -> [(url: URL, headers: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    static func reply(for url: URL) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        return replies[url.absoluteString]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.record(url, request.allHTTPHeaderFields ?? [:])
        guard let reply = Self.reply(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let deliver = { [weak self] in
            guard let self else { return }
            var headers = reply.headers
            headers["Content-Length"] = String(reply.body.count)
            let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !reply.body.isEmpty { self.client?.urlProtocol(self, didLoad: reply.body) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

@Suite("URLSessionTransport")
struct URLSessionTransportTests {
    private func transport(timeout: TimeInterval = 5) -> (URLSessionTransport, CookieJars) {
        let jars = CookieJars()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportStub.self]
        let t = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1",
                                   timeout: timeout, configuration: config)
        return (t, jars)
    }

    private func request(_ url: String, id: Int64 = 1, cookies: Bool = true,
                         partition: String = "test", headers: [String: [String]] = [:]) -> URLSessionTransport.Request {
        URLSessionTransport.Request(id: id, method: "GET", url: URL(string: url)!,
                                    headers: headers, body: nil, useCookies: cookies,
                                    partition: partition)
    }

    @Test func theDefaultUserAgentIsSent() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/a"] = .init(body: Data("hi".utf8))
        let (t, _) = transport()

        let response = try await t.send(request("https://example.test/a"))

        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == "hi")
        #expect(TransportStub.requests().first?.headers["User-Agent"] == "nk-test/1")
    }

    /// The jar's cookies are added, and an explicit Cookie header is not thrown
    /// away — sources set both, and dropping either breaks a login.
    @Test func storedCookiesJoinTheCallersOwn() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/b"] = .init()
        let (t, jars) = transport()
        jars.store(partition: "test", url: URL(string: "https://example.test/")!,
                   setCookieHeaders: ["sid=from-jar; Path=/"])

        _ = try await t.send(request("https://example.test/b", headers: ["Cookie": ["mine=1"]]))

        let sent = TransportStub.requests().first?.headers["Cookie"] ?? ""
        #expect(sent.contains("mine=1"))
        #expect(sent.contains("sid=from-jar"))
    }

    /// A Set-Cookie lands in the partition it came from, and nowhere else.
    @Test func setCookieIsStoredInItsPartition() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/c"] = .init(headers: ["Set-Cookie": "token=abc; Path=/"])
        let (t, jars) = transport()

        _ = try await t.send(request("https://example.test/c", partition: "alpha"))

        #expect(jars.header(partition: "alpha", url: URL(string: "https://example.test/x")!)?.contains("token=abc") == true)
        #expect(jars.header(partition: "beta", url: URL(string: "https://example.test/x")!) == nil)
    }

    /// With cookies off, the jar is neither read nor written: a source that opted
    /// out must not silently keep state.
    @Test func cookiesOffMeansNoJarAtAll() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/d"] = .init(headers: ["Set-Cookie": "token=xyz; Path=/"])
        let (t, jars) = transport()
        jars.store(partition: "test", url: URL(string: "https://example.test/")!,
                   setCookieHeaders: ["sid=kept; Path=/"])

        _ = try await t.send(request("https://example.test/d", cookies: false))

        let sent = TransportStub.requests().first?.headers["Cookie"]
        #expect(sent == nil)
        #expect(jars.header(partition: "test", url: URL(string: "https://example.test/x")!)?.contains("token=xyz") == false)
    }

    /// A body over the limit is refused rather than held in memory.
    @Test func anOversizedBodyIsRefused() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/big"] = .init(body: Data(repeating: 0x41, count: 4096))
        let (t, _) = transport()
        t.maxBodyBytes = 1024

        await #expect(throws: (any Error).self) {
            _ = try await t.send(request("https://example.test/big"))
        }
    }

    /// Cancelling by request id stops that request and leaves the next one alone.
    @Test func cancelStopsTheNamedRequestOnly() async throws {
        TransportStub.reset()
        TransportStub.replies["https://example.test/slow"] = .init(body: Data("late".utf8), delay: 0.5)
        TransportStub.replies["https://example.test/fast"] = .init(body: Data("now".utf8))
        let (t, _) = transport()

        async let slow: URLSessionTransport.Response? = try? await t.send(request("https://example.test/slow", id: 7))
        // Give the task a moment to register before cancelling it.
        try await Task.sleep(nanoseconds: 50_000_000)
        t.cancel(id: 7)
        let cancelled = await slow
        #expect(cancelled == nil)

        let fast = try await t.send(request("https://example.test/fast", id: 8))
        #expect(String(decoding: fast.body, as: UTF8.self) == "now")
    }
}
