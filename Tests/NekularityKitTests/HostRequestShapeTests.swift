import Foundation
import Network
import Testing
@testable import NekularityKit

/// A one-request HTTP server that answers with a fixed body, so a test can see
/// whether a request was made at all.
private final class AnswerServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "answer-server")
    private let condition = NSCondition()
    private var hits = 0
    private var ready = false
    private var problem: String?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> Int {
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
            guard let self else { return }
            connection.start(queue: queue)
            receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
        condition.lock()
        let deadline = Date().addingTimeInterval(2)
        while !ready && problem == nil && Date() < deadline { condition.wait(until: deadline) }
        let started = ready
        let message = problem ?? "listener did not become ready"
        condition.unlock()
        guard started, let port = listener.port else {
            throw NSError(domain: "AnswerServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return Int(port.rawValue)
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                condition.lock()
                hits += 1
                condition.broadcast()
                condition.unlock()
                let body = "proof"
                let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), contentContext: .finalMessage,
                                isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil {
                connection.cancel()
            } else {
                receive(connection, buffer: buffer)
            }
        }
    }

    var requests: Int {
        condition.lock(); defer { condition.unlock() }
        return hits
    }

    func stop() { listener.cancel() }
}

private func hostFor(_ root: URL) throws -> CoreHost {
    let transport = URLSessionTransport(cookies: CookieJars(file: nil), defaultUserAgent: "nk-service-test/1")
    return CoreHost(store: try SourceStore(root: root), cookies: CookieJars(file: nil), transport: transport)
}

/// The host contract lists `cookies`, but a request that leaves it out must
/// still be sent.
///
/// Core's service fetch once omitted the field, and this client decoded it as a
/// required `Bool`, so every service call failed with "the data couldn't be
/// read because it is missing" before anything was dialled - a fixture saw zero
/// requests. Both sides changed; this pins the client half.
@Test func aRequestWithoutCookiesIsStillSent() async throws {
    let server = try AnswerServer()
    let port = try server.start()
    defer { server.stop() }

    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nk-host-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let host = try hostFor(root)

    // Exactly the shape Core sent before the fix: no `cookies`, no `bodyBase64`.
    let request = """
    {"id":7,"method":"GET","url":"http://127.0.0.1:\(port)/proof","headers":{},"partition":"service:fixture"}
    """
    var failure: NSError?
    let answer = host.http(request, error: &failure)
    #expect(failure == nil, "the host refused a request the contract allows: \(failure?.localizedDescription ?? "")")
    #expect(server.requests == 1, "the request never reached the server")
    let decoded = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any]
    #expect(decoded?["status"] as? Int == 200)
    #expect(decoded?["bodyBase64"] as? String == Data("proof".utf8).base64EncodedString())
}
