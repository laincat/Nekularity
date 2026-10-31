import Foundation
import Testing
@testable import NekularityKit

/// Answers requests from a table instead of the network, so the transport's own
/// cookie and cancellation rules can be checked without a server.
///
/// The table and the record of what was sent are shared by every test in this
/// file, and Swift Testing runs tests in a suite in parallel. So each test uses
/// its own host names and never clears the tables: a `reset()` here would delete
/// another test's entries halfway through its request, which looks exactly like
/// a network failure (`-1004 cannot connect to host`).
final class TransportStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [(url: URL, headers: [String: String])] = []

    static func reply(_ url: String, with reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    static func lookup(_ url: URL) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        return replies[url.absoluteString]
    }

    static func record(_ url: URL, _ headers: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        seen.append((url, headers))
    }

    /// Requests this test made, ignoring every other test's.
    static func requests(host: String) -> [(url: URL, headers: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return seen.filter { $0.url.host == host }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.record(url, request.allHTTPHeaderFields ?? [:])
        guard let reply = Self.lookup(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        // `@Sendable` because the delayed path hops to another executor; the stub is
        // `@unchecked Sendable` and the reply is a value type, so nothing shared is
        // smuggled across.
        let deliver: @Sendable () -> Void = { [weak self] in
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
            let delay = reply.delay
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                deliver()
            }
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

@Suite("URLSessionTransport")
struct URLSessionTransportTests {
    private func transport(timeout: TimeInterval = 5) -> (URLSessionTransport, CookieJars) {
        let jars = CookieJars(file: nil)
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
        let host = "ua.test"
        TransportStub.reply("https://\(host)/a", with: .init(body: Data("hi".utf8)))
        let (t, _) = transport()

        let response = try await t.send(request("https://\(host)/a"))

        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == "hi")
        #expect(TransportStub.requests(host: host).first?.headers["User-Agent"] == "nk-test/1")
    }

    /// The jar's cookies are added, and an explicit Cookie header is not thrown
    /// away — sources set both, and dropping either breaks a login.
    @Test func storedCookiesJoinTheCallersOwn() async throws {
        let host = "cookies.test"
        TransportStub.reply("https://\(host)/b", with: .init())
        let (t, jars) = transport()
        jars.store(partition: "test", url: URL(string: "https://\(host)/")!,
                   setCookieHeaders: ["sid=from-jar; Path=/"])

        _ = try await t.send(request("https://\(host)/b", headers: ["Cookie": ["mine=1"]]))

        let sent = TransportStub.requests(host: host).first?.headers["Cookie"] ?? ""
        #expect(sent.contains("mine=1"))
        #expect(sent.contains("sid=from-jar"))
    }

    /// A Set-Cookie lands in the partition it came from, and nowhere else.
    @Test func setCookieIsStoredInItsPartition() async throws {
        let host = "setcookie.test"
        TransportStub.reply("https://\(host)/c", with: .init(headers: ["Set-Cookie": "token=abc; Path=/"]))
        let (t, jars) = transport()

        _ = try await t.send(request("https://\(host)/c", partition: "alpha"))

        #expect(jars.header(partition: "alpha", url: URL(string: "https://\(host)/x")!)?.contains("token=abc") == true)
        #expect(jars.header(partition: "beta", url: URL(string: "https://\(host)/x")!) == nil)
    }

    /// With cookies off, the jar is neither read nor written: a source that opted
    /// out must not silently keep state.
    @Test func cookiesOffMeansNoJarAtAll() async throws {
        let host = "nocookies.test"
        TransportStub.reply("https://\(host)/d", with: .init(headers: ["Set-Cookie": "token=xyz; Path=/"]))
        let (t, jars) = transport()
        jars.store(partition: "test", url: URL(string: "https://\(host)/")!,
                   setCookieHeaders: ["sid=kept; Path=/"])

        _ = try await t.send(request("https://\(host)/d", cookies: false))

        let sent = TransportStub.requests(host: host).first?.headers["Cookie"]
        #expect(sent == nil)
        #expect(jars.header(partition: "test", url: URL(string: "https://\(host)/x")!)?.contains("token=xyz") == false)
    }

    /// A body over the limit is refused rather than held in memory.
    @Test func anOversizedBodyIsRefused() async throws {
        let host = "big.test"
        TransportStub.reply("https://\(host)/big", with: .init(body: Data(repeating: 0x41, count: 4096)))
        let (t, _) = transport()
        t.maxBodyBytes = 1024

        await #expect(throws: (any Error).self) {
            _ = try await t.send(request("https://\(host)/big"))
        }
    }

    /// Cancelling by request id stops that request and leaves the next one alone.
    @Test func cancelStopsTheNamedRequestOnly() async throws {
        let host = "cancel.test"
        TransportStub.reply("https://\(host)/slow", with: .init(body: Data("late".utf8), delay: 0.5))
        TransportStub.reply("https://\(host)/fast", with: .init(body: Data("now".utf8)))
        let (t, _) = transport()

        async let slow: URLSessionTransport.Response? = try? await t.send(request("https://\(host)/slow", id: 7))
        // Give the task a moment to register before cancelling it.
        try await Task.sleep(nanoseconds: 50_000_000)
        t.cancel(id: 7)
        let cancelled = await slow
        #expect(cancelled == nil)

        let fast = try await t.send(request("https://\(host)/fast", id: 8))
        #expect(String(decoding: fast.body, as: UTF8.self) == "now")
    }
}
