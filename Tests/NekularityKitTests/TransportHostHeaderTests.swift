import Foundation
import Network
import Testing
@testable import NekularityKit

/// A one-request HTTP server that keeps the request head, so a test can see
/// exactly what went on the wire.
private final class HeadRecorder: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "head-recorder")
    private let condition = NSCondition()
    private var head = Data()
    private var ready = false
    private var problem: String?
    private var stopped = false

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
        while !ready && problem == nil && Date() < deadline {
            condition.wait(until: deadline)
        }
        let started = ready
        let message = problem ?? "listener did not become ready"
        condition.unlock()
        guard started, let port = listener.port else {
            throw NSError(domain: "HeadRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return Int(port.rawValue)
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, !stopped else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                condition.lock()
                head = buffer
                condition.broadcast()
                condition.unlock()
                let response = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), contentContext: .finalMessage,
                                isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if complete || error != nil {
                condition.lock()
                problem = "request ended before its head"
                condition.broadcast()
                condition.unlock()
            } else {
                receive(connection, buffer: buffer)
            }
        }
    }

    /// Waits for the head and returns it as text, or an empty string.
    func waitForHead() -> String {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(3)
        while head.isEmpty && problem == nil && Date() < deadline {
            condition.wait(until: deadline)
        }
        return String(decoding: head, as: UTF8.self)
    }

    func stop() {
        stopped = true
        listener.cancel()
    }
}

/// A source can name the virtual host it wants to talk to (`Host:
/// mobileapp.comic-walker.com`) while the address it dials is another one. Core
/// passes that header through and the Windows client had to be taught to send
/// it; this pins what the iOS client does, so a future change is a decision
/// rather than an accident.
@Test func aHostTheSourceNamesReachesTheServer() async throws {
    let server = try HeadRecorder()
    let port = try server.start()
    defer { server.stop() }

    let transport = URLSessionTransport(cookies: CookieJars(file: nil), defaultUserAgent: "test-agent")
    let request = URLSessionTransport.Request(id: 1, method: "GET",
                                              url: URL(string: "http://127.0.0.1:\(port)/probe")!,
                                              headers: ["Host": ["mobileapp.example.com"]],
                                              body: nil, useCookies: false, partition: "host")
    _ = try await transport.send(request)

    let head = server.waitForHead()
    #expect(!head.isEmpty, "the server never received a request head")
    let host = head.split(separator: "\r\n")
        .first { $0.lowercased().hasPrefix("host:") }
        .map { $0.dropFirst("host:".count).trimmingCharacters(in: .whitespaces) }
    #expect(host == "mobileapp.example.com",
            "the request named \(host ?? "no host"), not the one the source asked for")
}
