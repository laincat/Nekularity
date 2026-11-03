import Foundation
import Network
import Testing
@testable import NekularityKit

/// Sends one real SSE event immediately and holds the remaining events. Network
/// state belongs to `queue`; observations are protected by `condition`.
private final class HeldBody: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "held-http-body")
    private var connection: NWConnection?
    private var stopped = false
    private let condition = NSCondition()
    private var ready = false
    private var released = false
    private var peerClosed = false
    private var problem: String?
    let status: Int
    let firstEvent = Data("data: {\"choices\":[{\"delta\":{\"content\":\"第一段 \"}}]}\n\n".utf8)
    let tail = Data("data: {\"choices\":[{\"delta\":{\"content\":\"第二段\"}}]}\n\ndata: [DONE]\n\n".utf8)
    var body: Data { firstEvent + tail }

    init(status: Int) throws {
        self.status = status
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    var wasReleased: Bool {
        condition.lock(); defer { condition.unlock() }
        return released
    }

    var summary: String {
        condition.lock(); defer { condition.unlock() }
        return "released=\(released), peerClosed=\(peerClosed), error=\(problem ?? "none")"
    }

    var wasPeerClosed: Bool {
        condition.lock(); defer { condition.unlock() }
        return peerClosed
    }

    private func fail(_ message: String) {
        condition.lock(); defer { condition.unlock() }
        problem = message
        condition.broadcast()
    }

    func start() throws -> URL {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            condition.lock(); defer { condition.unlock() }
            switch state {
            case .ready: ready = true
            case .failed(let error): problem = error.localizedDescription
            default: break
            }
            condition.broadcast()
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, !stopped, self.connection == nil else { connection.cancel(); return }
            self.connection = connection
            connection.start(queue: queue)
            receiveHead(connection, buffer: Data())
            // Bound an abandoned connection; this is local teardown, not evidence
            // that the client cancelled it.
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.stopOnQueue() }
        }
        listener.start(queue: queue)
        condition.lock()
        let deadline = Date().addingTimeInterval(2)
        while !ready && problem == nil {
            if !condition.wait(until: deadline) { break }
        }
        let started = ready
        let message = problem ?? "listener did not become ready"
        condition.unlock()
        guard started, let port = listener.port else {
            stop()
            throw NSError(domain: "HeldBody", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/reply")!
    }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, !stopped else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 32_768 else { fail("request head too large"); return }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                let reason = status == 503 ? "Service Unavailable" : (status == 201 ? "Created" : "OK")
                let head = "HTTP/1.1 \(status) \(reason)\r\nX-Fixture: ready\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
                    if let error { self?.fail("send head: \(error)") }
                })
                receiveClose(connection)
            } else if complete || error != nil {
                fail("request ended before its head: \(String(describing: error))")
            } else {
                receiveHead(connection, buffer: buffer)
            }
        }
    }

    private func receiveClose(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, complete, error in
            guard let self, !stopped else { return }
            let reset: Bool
            if case .posix(.ECONNRESET)? = error { reset = true } else { reset = false }
            if complete || reset {
                condition.lock()
                peerClosed = true
                condition.broadcast()
                condition.unlock()
            } else if error != nil || data?.isEmpty == false {
                fail("unexpected data/error after request head: \(String(describing: error))")
            } else {
                receiveClose(connection)
            }
        }
    }

    func release() {
        condition.lock()
        released = true
        condition.unlock()
        queue.async { [weak self] in
            guard let self, !stopped, let connection else { return }
            connection.send(content: tail, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { [weak self] error in
                if let error { self?.fail("send body: \(error)") }
            })
        }
    }

    func waitForPeerClose() -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(2)
        while !peerClosed && problem == nil {
            if !condition.wait(until: deadline) { return false }
        }
        return peerClosed
    }

    private func stopOnQueue() {
        stopped = true
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        connection?.cancel()
        connection = nil
    }

    func stop() { queue.sync { stopOnQueue() } }
}

@Suite("Core stream SSE response and first event")
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
        let reply = try HeldBody(status: status)
        let url = try reply.start()
        do {
            let transport = URLSessionTransport(cookies: CookieJars(file: nil), defaultUserAgent: "nk-test/1",
                                                timeout: 5, configuration: .ephemeral)
            let host = CoreStreamHost(transport: transport)
            let wire = try JSONSerialization.data(withJSONObject: ["id": 1, "method": "GET",
                                                                   "url": url.absoluteString, "partition": "magpie"])
            var failure: NSError?
            let raw = host.streamOpen(String(decoding: wire, as: UTF8.self), error: &failure)
            if let failure { throw failure }
            let id = try JSONDecoder().decode(Opened.self, from: Data(raw.utf8)).id
            return (host, id, url, reply)
        } catch {
            reply.stop()
            throw error
        }
    }

    private func next(_ host: CoreStreamHost, _ id: Int64) async throws -> Chunk {
        // streamNext blocks by contract. The watchdog closes that exact stream
        // if the response or first event is held until the stream completes.
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

    @Test func responseAndFirstEventPrecedeHeldTail() async throws {
        try await verifyHead(status: 201)
    }

    @Test func errorResponseAndFirstEventPrecedeHeldTail() async throws {
        try await verifyHead(status: 503)
    }

    private func verifyHead(status: Int) async throws {
        let (host, id, url, reply) = try open(status: status)
        defer { host.streamClose(id); reply.stop() }
        let head = try await next(host, id)
        try #require(!head.done, "first chunk: \(head); \(reply.summary)")
        #expect(head.chunkBase64 == nil)
        #expect(head.status == status)
        #expect(head.finalUrl == url.absoluteString)
        #expect(head.headers?.first { $0.key.lowercased() == "x-fixture" }?.value == ["ready"])
        #expect(!reply.wasReleased)

        let first = try await readFirstEvent(host, id, reply)
        #expect(first == reply.firstEvent)
        #expect(!reply.wasReleased)

        reply.release()
        var body = first
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
        Issue.record("stream did not end after the held tail was released")
    }

    private func readFirstEvent(_ host: CoreStreamHost, _ id: Int64, _ reply: HeldBody) async throws -> Data {
        var bytes = Data()
        for _ in 0..<8 {
            let chunk = try await next(host, id)
            try #require(!chunk.done, "stream ended before the first event: \(chunk); \(reply.summary)")
            if let encoded = chunk.chunkBase64 { bytes.append(try #require(Data(base64Encoded: encoded))) }
            if bytes.count >= reply.firstEvent.count { return bytes }
        }
        Issue.record("stream did not deliver the first event")
        return bytes
    }

    @Test func cancellationAfterFirstEventStopsHeldTail() async throws {
        let (host, id, _, reply) = try open(status: 200)
        defer { host.streamClose(id); reply.stop() }
        let first = try await readFirstEvent(host, id, reply)
        #expect(first == reply.firstEvent)
        #expect(!reply.wasReleased)
        try #require(!reply.wasPeerClosed, "peer closed before streamClose; \(reply.summary)")
        host.streamClose(id)
        #expect(reply.waitForPeerClose(), "\(reply.summary)")
        #expect(!reply.wasReleased)
    }
}
