import Foundation
import VeneraCatCore

/// The client's chunked transport, as Core's `HostStream` sees it.
///
/// Core cannot call back into the client, so the protocol is a poll: open the
/// stream, then ask for one piece at a time. The pieces arrive in the order the
/// server sent them, and the last one carries the status and the final URL.
///
/// This type only moves data; the request itself goes through the same
/// `URLSessionTransport` as every other request, so the cookie partitions and
/// the cancellation rules stay the ones the client already has.
public final class CoreStreamHost: NSObject, MobileHostStreamProtocol, @unchecked Sendable {
    /// One open stream: the pieces that arrived and the head of the reply.
    private final class Stream {
        /// The pieces the server sent, in order.
        private let lock = NSCondition()
        private var pending: [Data] = []
        private var ended = false
        /// The status of the reply.
        var status = 0
        /// The reply's headers.
        var headers: [String: [String]] = [:]
        /// The URL the reply came from.
        var finalURL = ""
        /// Why the stream ended, when it ended badly.
        var failure: Error?
        /// The request id, so the stream can be aborted.
        let requestID: Int64

        init(requestID: Int64) {
            self.requestID = requestID
        }

        /// Takes the next piece, waiting for one to arrive.
        func next() -> Data? {
            lock.lock(); defer { lock.unlock() }
            while pending.isEmpty && !ended {
                lock.wait()
            }
            if pending.isEmpty { return nil }
            return pending.removeFirst()
        }

        /// Hands over a piece and wakes the reader.
        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            pending.append(data)
            lock.signal()
        }

        /// Ends the stream: the reader sees the end after the pieces it has.
        func finish() {
            lock.lock(); defer { lock.unlock() }
            ended = true
            lock.broadcast()
        }
    }

    private let transport: URLSessionTransport
    private let lock = NSLock()
    private var streams: [Int64: Stream] = [:]
    private var nextID: Int64 = 0

    public init(transport: URLSessionTransport) {
        self.transport = transport
        super.init()
    }

    // MARK: Wire shapes

    private struct WireRequest: Decodable {
        var id: Int64
        var method: String
        var url: String
        var headers: [String: [String]]?
        var bodyBase64: String?
        var partition: String?
    }

    private struct StreamChunk: Encodable {
        var done: Bool
        var chunkBase64: String?
        var status: Int?
        var headers: [String: [String]]?
        var finalUrl: String?
        var error: String?
    }

    // MARK: MobileHostStreamProtocol

    public func streamOpen(_ requestJSON: String?, error: NSErrorPointer) -> String {
        do {
            let w = try JSONDecoder().decode(WireRequest.self, from: Data((requestJSON ?? "").utf8))
            guard let url = URL(string: w.url) else { throw CoreError("invalid URL \(w.url)") }
            var body: Data?
            if let b = w.bodyBase64, !b.isEmpty {
                guard let d = Data(base64Encoded: b) else { throw CoreError("invalid request body") }
                body = d
            }
            let request = URLSessionTransport.Request(id: w.id, method: w.method, url: url,
                                                      headers: w.headers ?? [:], body: body,
                                                      useCookies: false, partition: w.partition ?? "magpie")
            let stream = Stream(requestID: w.id)
            lock.lock()
            nextID += 1
            let id = nextID
            streams[id] = stream
            lock.unlock()

            // The transfer runs beside Core's poll: the transport hands every
            // piece over as it arrives and the stream keeps them until Core
            // asks for the next one.
            Task {
                do {
                    let response = try await transport.sendStreaming(request) { data in
                        stream.append(data)
                    }
                    stream.status = response.status
                    stream.headers = response.headers
                    stream.finalURL = response.finalURL.absoluteString
                } catch {
                    stream.failure = error
                }
                stream.finish()
            }
            return "{\"id\":\(id)}"
        } catch let e {
            error?.pointee = NSError(domain: "Nekularity", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: e.localizedDescription])
            return ""
        }
    }

    public func streamNext(_ id_: Int64, error: NSErrorPointer) -> String {
        lock.lock()
        let stream = streams[id_]
        lock.unlock()
        guard let stream else {
            error?.pointee = NSError(domain: "Nekularity", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: "no stream under \(id_)"])
            return ""
        }
        guard let piece = stream.next() else {
            lock.lock()
            streams[id_] = nil
            lock.unlock()
            var chunk = StreamChunk(done: true, chunkBase64: nil, status: nil, headers: nil, finalUrl: nil, error: nil)
            chunk.status = stream.status
            chunk.headers = stream.headers
            chunk.finalUrl = stream.finalURL
            if let failure = stream.failure {
                chunk.error = failure.localizedDescription
            }
            return Self.json(chunk)
        }
        var chunk = StreamChunk(done: false, chunkBase64: piece.base64EncodedString(),
                                status: nil, headers: nil, finalUrl: nil, error: nil)
        return Self.json(chunk)
    }

    public func streamClose(_ id_: Int64) {
        lock.lock()
        let stream = streams.removeValue(forKey: id_)
        lock.unlock()
        if let stream {
            transport.cancel(id: stream.requestID)
            stream.finish()
        }
    }

    private static func json(_ v: StreamChunk) -> String {
        (try? String(decoding: JSONEncoder().encode(v), as: UTF8.self)) ?? "{}"
    }
}
