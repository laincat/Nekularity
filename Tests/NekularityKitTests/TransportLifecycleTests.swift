import Foundation
import Testing
@testable import NekularityKit

private final class LifecycleToken: @unchecked Sendable {}

private final class TokenBox: @unchecked Sendable {
    var token: LifecycleToken?
}

private final class LifecycleFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    func set(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        stored = value
    }

    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { k in
            lock.lock()
            continuation = k
            lock.unlock()
        }
    }

    func open() {
        let k: CheckedContinuation<Void, Never>? = lock.withLock {
            let k = continuation
            continuation = nil
            return k
        }
        k?.resume()
    }
}

@Suite("transport lifecycle")
struct TransportLifecycleTests {
    private func transport() -> (URLSessionTransport, CookieJars) {
        let jars = CookieJars(file: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportStub.self]
        let t = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-lifecycle/1",
                                   timeout: 3, configuration: config)
        return (t, jars)
    }

    private func request(_ host: String, id: Int64) -> URLSessionTransport.Request {
        URLSessionTransport.Request(id: id, method: "GET",
                                    url: URL(string: "https://\(host)/request")!,
                                    headers: [:], body: nil, useCookies: false,
                                    partition: "lifecycle")
    }

    private func state(onChunk: (@Sendable (Data) -> Void)? = nil) -> TaskState {
        TaskState(limit: 1 << 20, partition: "lifecycle", useCookies: false,
                  manualHeaders: [:], manualCookie: nil,
                  cookies: CookieJars(file: nil),
                  origin: URL(string: "https://lifecycle.invalid/")!,
                  onChunk: onChunk)
    }

    /// A failure before a body arrives must not leave the chunk closure (or the
    /// body buffer it belongs to) in the delegate's states table.
    @Test func failedRequestReleasesItsChunkClosure() async throws {
        let host = "lifecycle-fail.test"
        let (t, _) = transport()
        var token: LifecycleToken? = LifecycleToken()
        weak var weakToken = token
        await #expect(throws: (any Error).self) {
            _ = try await t.sendStreaming(request(host, id: 101)) { [token] _ in _ = token }
        }
        token = nil
        try await Task.sleep(for: .milliseconds(150))
        #expect(weakToken == nil, "failed request retained its chunk closure")
    }

    @Test func oversizedRequestReleasesItsChunkClosure() async throws {
        let host = "lifecycle-big.test"
        TransportStub.reply("https://\(host)/request", with: .init(body: Data(repeating: 0x41, count: 4096)))
        let (t, _) = transport()
        t.maxBodyBytes = 1024
        var token: LifecycleToken? = LifecycleToken()
        weak var tokenWeak = token
        await #expect(throws: (any Error).self) {
            _ = try await t.sendStreaming(request(host, id: 102)) { [token] _ in _ = token }
        }
        token = nil
        try await Task.sleep(for: .milliseconds(150))
        #expect(tokenWeak == nil, "oversized request retained its chunk closure")
    }

    @Test func cancelledRequestReleasesItsChunkClosure() async throws {
        let host = "lifecycle-cancel.test"
        TransportStub.reply("https://\(host)/request", with: .init(body: Data("late".utf8), delay: 0.5))
        let (t, _) = transport()
        let box = TokenBox()
        box.token = LifecycleToken()
        weak var tokenWeak = box.token
        let req = request(host, id: 103)
        var task: Task<Void, Never>? = Task {
            _ = try? await t.sendStreaming(req) { [box] _ in _ = box.token }
        }
        try await Task.sleep(for: .milliseconds(80))
        t.cancel(id: 103)
        _ = await task?.value
        task = nil
        box.token = nil
        try await Task.sleep(for: .milliseconds(150))
        #expect(tokenWeak == nil, "cancelled request retained its chunk closure")
    }

    /// Finish followed by a late data callback must not emit a chunk.
    @Test func aChunkAfterFinishIsIgnored() throws {
        let chunks = ChunkRecorder()
        let s = state { chunks.append($0) }
        let url = URL(string: "https://lifecycle.invalid/done")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "0"])!
        s.received(response)
        s.finish(.success(url))

        #expect(s.append(Data("late".utf8)) == false)
        #expect(chunks.pieces.isEmpty, "a chunk was emitted after finish")
    }

    /// cancel() can arrive before attach(). The continuation must still resume,
    /// otherwise the caller's TaskNever returns.
    @Test func attachAfterCancelResumes() async throws {
        let s = state()
        s.cancel()
        let flag = LifecycleFlag()
        let task = Task {
            do {
                try await withCheckedThrowingContinuation {
                    (k: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                    s.attach(k)
                }
                flag.set("resumed")
            } catch {
                flag.set("error")
            }
        }
        for _ in 0..<50 {
            if flag.value != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(flag.value != nil, "attach after cancel left the continuation suspended")
        task.cancel()
    }

    /// A finished old request must not clear the map entry of a newer request
    /// that reused the same Core id while the old one was still in flight.
    @Test func staleCompletionDoesNotClearAReusedID() async throws {
        let host = "lifecycle-reuse.test"
        TransportStub.reply("https://\(host)/old", with: .init(body: Data("old".utf8), delay: 0.5))
        TransportStub.reply("https://\(host)/new", with: .init(body: Data("new".utf8), delay: 1.0))
        let (t, _) = transport()
        let old = URLSessionTransport.Request(id: 105, method: "GET",
                                              url: URL(string: "https://\(host)/old")!,
                                              headers: [:], body: nil, useCookies: false,
                                              partition: "lifecycle")
        let new = URLSessionTransport.Request(id: 105, method: "GET",
                                              url: URL(string: "https://\(host)/new")!,
                                              headers: [:], body: nil, useCookies: false,
                                              partition: "lifecycle")
        let oldTask = Task { _ = try? await t.send(old) }
        try await Task.sleep(for: .milliseconds(100))
        let newTask = Task { try? await t.send(new) }
        try await Task.sleep(for: .milliseconds(600))
        t.cancel(id: 105)
        let newResult = await newTask.value
        _ = await oldTask.value
        #expect(newResult == nil, "old cleanup cleared the reused id and left the new request running")
    }

    /// A Swift Task cancelled before it reaches send() must not issue a request.
    @Test func cancelledSwiftTaskDoesNotStartNetwork() async throws {
        let host = "lifecycle-precancel.test"
        TransportStub.reply("https://\(host)/request", with: .init(body: Data("must not run".utf8)))
        let (t, _) = transport()
        let gate = AsyncGate()
        let req = request(host, id: 104)
        let task = Task {
            await gate.wait()
            _ = try? await t.send(req)
        }
        task.cancel()
        gate.open()
        try await Task.sleep(for: .milliseconds(300))
        #expect(TransportStub.requests(host: host).isEmpty, "a cancelled Task started a request")
        task.cancel()
    }
}
