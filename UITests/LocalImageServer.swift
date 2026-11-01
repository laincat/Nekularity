import Foundation
import Network
import UIKit

/// A tiny HTTP server the app can fetch images from, inside the simulator.
///
/// The reader takes its images from URLs, so checking that it draws pages used to
/// need a real site. The test runner and the app are two processes on the same
/// simulator, so they share loopback: a server here is reachable from the app at
/// 127.0.0.1 with no network, no site and no account.
///
/// It answers every GET with the same small PNG. Nothing about it is meant to be
/// general — one image, one port, one connection at a time is what the reader case
/// needs.
///
/// `@unchecked Sendable` because every stored property is a `let` and the only
/// mutable state lives in `Signal`, which carries its own lock. The project builds
/// with complete concurrency checking, and `NWListener`'s handlers are `@Sendable`,
/// so the alternative would be to hand the framework a fresh object per call.
final class LocalImageServer: @unchecked Sendable {
    static let port: UInt16 = 18731

    /// Where the fixture's chapter points: `http://127.0.0.1:18731/page.png`.
    static var pageURL: String { "http://127.0.0.1:\(port)/page.png" }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "local-image-server")
    private let png: Data

    init() throws {
        // Drawn rather than pasted as base64: a hand-typed blob is exactly the kind
        // of thing that decodes to nothing and looks like a client bug.
        let side: CGFloat = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "LocalImageServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "a drawn image produced no PNG"])
        }
        png = data

        let options = NWParameters.tcp
        options.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Self.port) else {
            throw NSError(domain: "LocalImageServer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "port \(Self.port) is not usable"])
        }
        listener = try NWListener(using: options, on: port)
    }

    /// Starts listening and returns once the port is bound, so the app never
    /// launches against a server that is not there yet.
    func start(timeout: TimeInterval = 10) throws {
        let signal = Signal()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                signal.finish()
            case .failed(let error):
                signal.finish(error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [self] connection in
            serve(connection)
        }
        listener.start(queue: queue)
        if signal.semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw NSError(domain: "LocalImageServer", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "the listener was not ready in time"])
        }
        if let failure = signal.failure {
            throw failure
        }
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // The request is read only to know the client has finished sending; the
        // answer is the same whatever was asked for.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] _, _, _, _ in
            var response = Data()
            response.append(Data("HTTP/1.1 200 OK\r\n".utf8))
            response.append(Data("Content-Type: image/png\r\n".utf8))
            response.append(Data("Content-Length: \(png.count)\r\n".utf8))
            response.append(Data("Connection: close\r\n\r\n".utf8))
            response.append(png)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

/// One start-or-fail outcome from an `NWListener`, carried across the handler.
private final class Signal: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: Error?

    var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func finish(_ error: Error? = nil) {
        lock.lock()
        stored = error
        lock.unlock()
        semaphore.signal()
    }
}
