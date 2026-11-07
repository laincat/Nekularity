import Foundation
import Testing
@testable import NekularityKit

/// A response head that arrives and a body that never does.
///
/// A provider that answers `401` and then holds the connection open is the
/// case this file is about: the status is known at once, so the client must
/// report it at once. Waiting for a body that will never come turns a wrong
/// key into a hang.
final class HeldHeadStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 401
        var headers: [String: String] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var stoppedHosts: Set<String> = []
    nonisolated(unsafe) private static var bodyBytes: [String: Int] = [:]

    static func reply(_ url: String, with reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    static func lookup(_ url: URL) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        return replies[url.absoluteString]
    }

    /// Whether the client stopped reading the body of a host.
    static func stopped(host: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stoppedHosts.contains(host)
    }

    /// How many body bytes the client took. A head-only answer takes none.
    static func bytesRead(host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return bodyBytes[host] ?? 0
    }

    static func noteStop(host: String) {
        lock.lock(); defer { lock.unlock() }
        stoppedHosts.insert(host)
    }

    static func noteBytes(host: String, _ n: Int) {
        lock.lock(); defer { lock.unlock() }
        bodyBytes[host, default: 0] += n
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        guard let reply = Self.lookup(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // The body never arrives and the request never finishes: only the
        // client stopping it can end this.
    }

    override func stopLoading() {
        Self.noteStop(host: request.url?.host ?? "")
    }
}

@Suite("A rejected standard AI stream ends at the head")
struct StandardAIStreamRejectionTests {
    private func client(_ status: Int) throws -> (StandardAI, StandardAIConfig, URL, URL) {
        let hostName = "rejected-\(UUID().uuidString.lowercased()).test"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rejected-\(UUID().uuidString)")
        let config = StandardAIConfig(protocol: .chat, baseURL: "https://\(hostName)/v1", model: "fixture-model")
        let url = URL(string: config.baseURL + "/chat/completions")!
        HeldHeadStub.reply(url.absoluteString, with: .init(status: status,
                                                           headers: ["Content-Type": "application/json"]))
        let jars = CookieJars(file: nil)
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [HeldHeadStub.self]
        // A short timeout: the accepted-head case waits for a body the stub
        // never sends, and it must end quickly.
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "ai-tests/1",
                                            timeout: 3, configuration: session)
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "ai-tests/1"), host: host)
        return (StandardAI(core: core), config, url, root)
    }

    /// A `401` that the server never finishes must be reported at once.
    ///
    /// Before the fix the status was only known when the whole body had
    /// arrived, so this case hung until the socket timed out.
    @Test func aRejectedStreamIsReportedWithoutWaitingForTheBody() async throws {
        let (api, config, url, root) = try client(401)
        defer { try? FileManager.default.removeItem(at: root) }

        let started = ContinuousClock.now
        var failure: StandardAIError?
        do {
            _ = try await api.replyStreaming(config: config, apiKey: "wrong-key",
                                             messages: [StandardMessage(role: "user", content: "hi")]) { _ in }
            Issue.record("a rejected stream became an answer")
        } catch let error as StandardAIError {
            failure = error
        }
        let elapsed = ContinuousClock.now - started

        let message = try #require(failure?.message)
        #expect(message.contains("HTTP 401"))
        // The body was never read: the head alone ended the request.
        #expect(HeldHeadStub.bytesRead(host: url.host ?? "") == 0)
        #expect(HeldHeadStub.stopped(host: url.host ?? ""))
        // It must not have waited for the socket to time out.
        #expect(elapsed < .seconds(5))
    }

    /// A status that is not a rejection is still read as a whole.
    ///
    /// The body is never sent by the stub, so the request can only end by
    /// timing out. That is the point: an accepted head must not end the
    /// request, and the case asserts that the transport was not stopped and
    /// that the failure is not the rejection message.
    @Test func anAcceptedStreamKeepsReadingTheBody() async throws {
        let (api, config, url, root) = try client(200)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await api.replyStreaming(config: config, apiKey: "fixture-key",
                                             messages: [StandardMessage(role: "user", content: "hi")]) { _ in }
            Issue.record("a held-open body became an answer")
        } catch let error as StandardAIError {
            #expect(!error.message.contains("HTTP 200"))
        } catch {
            // A transport error is fine here: the point is that the head did
            // not end the request.
        }
        #expect(!HeldHeadStub.stopped(host: url.host ?? ""))
    }
}
