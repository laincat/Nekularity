import Foundation
import Network
import UIKit

/// A tiny HTTP server the app can fetch from, inside the simulator.
///
/// The reader takes its images from URLs, so checking that it draws pages used to
/// need a real site. The test runner and the app are two processes on the same
/// simulator, so they share loopback: a server here is reachable from the app at
/// 127.0.0.1 with no network, no site and no account.
///
/// It answers `/page.png` with a small PNG and `/clip.mp4` with the video fixture,
/// in ranges. Nothing about it is meant to be general — one port, one route per
/// case is what the reader and player cases need. The video route refuses a
/// request without the source's `Referer`, so a passing playback case also proves
/// the headers travelled from `video.loadPlay` to the engine.
///
/// `@unchecked Sendable` because every stored property is a `let` and the only
/// mutable state lives in `Signal`, which carries its own lock. The project builds
/// with complete concurrency checking, and `NWListener`'s handlers are `@Sendable`,
/// so the alternative would be to hand the framework a fresh object per call.
final class LocalImageServer: @unchecked Sendable {
    static let port: UInt16 = 18731

    /// Where the fixture's chapter points: `http://127.0.0.1:18731/page.png`.
    static var pageURL: String { "http://127.0.0.1:\(port)/page.png" }
    /// Where the video fixture's play answer points.
    static var clipURL: String { "http://127.0.0.1:\(port)/clip.mp4" }
    /// The value the video route demands; the fixture sends it as `Referer`.
    static let clipReferer = "http://127.0.0.1:18731/"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "local-image-server")
    private let png: Data
    /// nil when the fixture is missing from the bundle; the route then answers 404
    /// rather than pretending the file is there.
    private let video: Data?

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
        // The runner's own bundle: `UITests/Fixtures/media/clip.mp4` is copied as a
        // resource of the test target.
        if let url = Bundle(for: LocalImageServer.self).url(forResource: "clip", withExtension: "mp4"),
           let clip = try? Data(contentsOf: url) {
            video = clip
        } else {
            video = nil
        }

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
        receiveHead(connection, buffer: Data())
    }

    /// Reads until the request head is complete. One `receive` is not enough: a
    /// request with a `Range` header arrives in more than one chunk often enough
    /// that answering the first chunk truncates the header and the route misfires.
    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] chunk, _, isComplete, error in
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                send(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
                return
            }
            if isComplete || error != nil || buffer.count > 32_768 {
                connection.cancel()
                return
            }
            receiveHead(connection, buffer: buffer)
        }
    }

    private func send(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let route = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        switch route {
        case "/clip.mp4":
            // The header the source declared. Without it the request fails, which is
            // the whole point of the case.
            guard headers["referer"] == Self.clipReferer else {
                reply(connection, status: "403 Forbidden", body: Data())
                return
            }
            guard let video else {
                reply(connection, status: "404 Not Found", body: Data())
                return
            }
            reply(connection, status: "200 OK", body: video, type: "video/mp4",
                  range: headers["range"], extra: ["Accept-Ranges": "bytes"])
        default:
            reply(connection, status: "200 OK", body: png, type: "image/png")
        }
    }

    /// Answers with the whole body, or with the requested range of it. AVFoundation
    /// and FFmpeg both ask for ranges, and a server that ignores the header can make
    /// a perfectly good file look unplayable.
    private func reply(_ connection: NWConnection, status: String, body: Data,
                       type: String = "application/octet-stream", range: String? = nil,
                       extra: [String: String] = [:]) {
        var payload = body
        var status = status
        var resume = ""
        if status == "200 OK", let range, range.hasPrefix("bytes=") {
            let spec = range.dropFirst("bytes=".count).split(separator: "-")
            let start = Int(spec.first ?? "") ?? 0
            let end = spec.count > 1 ? (Int(spec[1]) ?? body.count - 1) : body.count - 1
            if start < body.count {
                let last = min(end, body.count - 1)
                payload = body.subdata(in: start...(last))
                status = "206 Partial Content"
                resume = "Content-Range: bytes \(start)-\(last)/\(body.count)\r\n"
            }
        }
        var response = Data("HTTP/1.1 \(status)\r\n".utf8)
        response.append(Data("Content-Type: \(type)\r\n".utf8))
        response.append(Data("Content-Length: \(payload.count)\r\n".utf8))
        for (name, value) in extra {
            response.append(Data("\(name): \(value)\r\n".utf8))
        }
        response.append(Data(resume.utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
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
