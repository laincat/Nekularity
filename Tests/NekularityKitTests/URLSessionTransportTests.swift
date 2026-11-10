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
        /// Streamed pieces, used to prove the transport stops reading rather than
        /// buffering a body it will refuse. `chunks > 0` also omits Content-Length,
        /// which is how a server without a declared size behaves.
        var chunks = 0
        var chunkSize = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [(url: URL, headers: [String: String])] = []
    nonisolated(unsafe) private static var delivered: [String: Int] = [:]

    static func reply(_ url: String, with reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    static func lookup(_ url: URL) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        return replies[url.absoluteString]
    }

    /// Bytes handed to the client for a host, which is what "stopped early" means.
    static func bytesDelivered(host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return delivered[host] ?? 0
    }

    static func addDelivered(host: String, _ n: Int) {
        lock.lock(); defer { lock.unlock() }
        delivered[host, default: 0] += n
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
        if reply.chunks > 0 {
            let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            stream(reply, host: url.host ?? "", piece: Data(repeating: 0x41, count: reply.chunkSize))
            return
        }
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

    override func stopLoading() { stopped = true }

    private var stopped = false

    /// Delivers one piece at a time on a background task and stops as soon as the
    /// client cancels, so an early refusal is visible as a byte count.
    private func stream(_ reply: Reply, host: String, piece: Data) {
        let chunks = reply.chunks
        let size = piece.count
        Task { @Sendable [weak self] in
            guard let self else { return }
            for _ in 0..<chunks {
                guard !self.stopped else { return }
                self.client?.urlProtocol(self, didLoad: piece)
                Self.addDelivered(host: host, size)
                // The client cancels from its own queue: without a hop it would
                // only see the whole body after it had already been handed over.
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
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
    /// A cancel that lands before the request is registered must still be honoured:
    /// the call is never sent at all.
    @Test func aCancelBeforeRegistrationStopsTheRequest() async throws {
        let host = "earlycancel.test"
        TransportStub.reply("https://\(host)/x", with: .init(body: Data("should not run".utf8)))
        let (t, _) = transport()

        t.cancel(id: 99)
        await #expect(throws: (any Error).self) {
            _ = try await t.send(request("https://\(host)/x", id: 99))
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(TransportStub.requests(host: host).isEmpty)
    }

    private func state(_ origin: String, headers: [String: [String]] = [:], cookies: Bool = true,
                       manualCookie: String? = nil, partition: String = "test") -> TaskState {
        TaskState(limit: 1 << 20, partition: partition, useCookies: cookies,
                  manualHeaders: headers, manualCookie: manualCookie,
                  cookies: CookieJars(file: nil), origin: URL(string: origin)!)
    }

    /// The caller's own credential headers belong to its origin. Cookie is
    /// rebuilt from the jar either way, but `X-Api-Key` and friends must not
    /// follow a redirect to another host — Foundation only strips Authorization.
    @Test func anotherOriginDoesNotReceiveCallerCredentials() throws {
        let s = state("https://leak-from.test/start",
                      headers: ["X-Api-Key": ["secret-key"], "Authorization": ["Bearer secret"]],
                      manualCookie: "mine=1")
        var request = URLRequest(url: URL(string: "https://leak-to.test/next")!)
        request.setValue("secret-key", forHTTPHeaderField: "X-Api-Key")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("mine=1", forHTTPHeaderField: "Cookie")

        let out = s.redirected(request)

        #expect(out.value(forHTTPHeaderField: "X-Api-Key") == nil)
        #expect(out.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(out.value(forHTTPHeaderField: "Cookie") == nil)
    }

    /// A redirect inside one origin keeps them: that is the same server.
    @Test func theSameOriginKeepsCallerCredentials() throws {
        let s = state("https://same-origin.test/start", headers: ["X-Api-Key": ["secret-key"]],
                      manualCookie: "mine=1")

        let out = s.redirected(URLRequest(url: URL(string: "https://same-origin.test/next")!))

        #expect(out.value(forHTTPHeaderField: "X-Api-Key") == "secret-key")
        #expect(out.value(forHTTPHeaderField: "Cookie") == "mine=1")
    }

    /// A different port is a different origin even when the host matches.
    @Test func aPortChangeIsAnotherOrigin() throws {
        let s = state("http://localhost:8080/start", headers: ["X-Api-Key": ["secret-key"]])

        let out = s.redirected(URLRequest(url: URL(string: "http://localhost:8081/next")!))

        #expect(out.value(forHTTPHeaderField: "X-Api-Key") == nil)
    }

    /// The jar's cookies for the new host still travel, because those are the
    /// new host's cookies and not a leaked credential.
    @Test func theJarStillAnswersForTheNewHost() throws {
        let s = state("https://jar-a.test/start", manualCookie: "old=1")
        s.cookies.store(partition: "test", url: URL(string: "https://jar-b.test/")!,
                        setCookieHeaders: ["fresh=2; Path=/"])

        let out = s.redirected(URLRequest(url: URL(string: "https://jar-b.test/next")!))

        let cookie = out.value(forHTTPHeaderField: "Cookie") ?? ""
        #expect(cookie.contains("fresh=2"))
        #expect(!cookie.contains("old=1"))
    }

    /// A body with no declared length is refused while it arrives, not after the
    /// whole 256 KiB has been buffered.
    @Test func anOversizedStreamIsRefusedWhileItArrives() async throws {
        let host = "stream.test"
        let total = 256 * 1024
        let chunk = 1024
        TransportStub.reply("https://\(host)/stream", with: .init(chunks: total / chunk, chunkSize: chunk))
        let (t, _) = transport()
        t.maxBodyBytes = 1024

        await #expect(throws: (any Error).self) {
            _ = try await t.send(request("https://\(host)/stream"))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(TransportStub.bytesDelivered(host: host) < total)
    }

    /// URLSession keeps its delegate alive, so a session built with `delegate: self`
    /// would keep the transport alive for the life of the process.
    @Test func theTransportIsReleasedWithItsSession() async throws {
        weak var weakTransport: URLSessionTransport?
        do {
            let (t, _) = transport()
            weakTransport = t
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(weakTransport == nil)
    }

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

/// The app's own cleartext gate, checked at the transport rather than only on
/// the policy value: a bug that skipped the call site would still pass the
/// unit tests above.
extension URLSessionTransportTests {
    @Test func aPublicCleartextRequestIsRefusedBeforeItStarts() async throws {
        let host = "cleartext.test"
        TransportStub.reply("http://\(host)/x", with: .init(body: Data("must not run".utf8)))
        let (t, _) = transport()

        do {
            _ = try await t.send(request("http://\(host)/x", partition: "ai"))
            Issue.record("a public http request reached the session")
        } catch let error as CoreError {
            #expect(error.message.contains("cleartext http is not allowed"))
        }
        #expect(TransportStub.requests(host: host).isEmpty)
    }

    @Test func aLocalCleartextRequestStillRuns() async throws {
        let host = "127.0.0.1"
        TransportStub.reply("http://\(host):9/ok", with: .init(body: Data("local".utf8)))
        let (t, _) = transport()

        let response = try await t.send(request("http://\(host):9/ok", partition: "ai"))

        #expect(String(decoding: response.body, as: UTF8.self) == "local")
    }

    @Test func aDeclaredSourceHostRunsForAComicPartitionOnly() async throws {
        let host = "lrr.tvc-16.science"
        TransportStub.reply("http://\(host)/api/search", with: .init(body: Data("lan".utf8)))
        let (t, _) = transport()

        let response = try await t.send(request("http://\(host)/api/search", partition: "comic:lanraragi"))
        #expect(String(decoding: response.body, as: UTF8.self) == "lan")

        do {
            _ = try await t.send(request("http://\(host)/api/search", id: 2, partition: "ai"))
            Issue.record("the declared source host was allowed for an AI request")
        } catch let error as CoreError {
            #expect(error.message.contains("cleartext http is not allowed"))
        }
    }
}
