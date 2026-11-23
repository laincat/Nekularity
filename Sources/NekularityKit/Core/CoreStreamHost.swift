import Foundation
import VeneraCatCore

/// The client's chunked transport, as Core's `HostStream` sees it.
///
/// Core cannot call back into the client, so the protocol is a poll: open the
/// stream, then ask for one piece at a time. A head-only piece precedes body
/// pieces; the last piece repeats the metadata for older Core versions.
///
/// This type only moves data; the request itself goes through the same
/// `URLSessionTransport` as every other request, so the cookie partitions and
/// the cancellation rules stay the ones the client already has.
public final class CoreStreamHost: NSObject, MobileHostStreamProtocol, @unchecked Sendable {
    /// One open stream: the pieces that arrived and the head of the reply.
    ///
    /// `@unchecked Sendable`: all mutable state, including response metadata
    /// and failures, is protected by the same condition as the body queue.
    private final class Stream: @unchecked Sendable {
        private let lock = NSCondition()
        private var pending: [Data] = []
        private var headIndex = 0
        private var pendingBytes = 0
        private var ended = false
        private var head: URLSessionTransport.Response?
        private var headPending = false
        private var failure: Error?
        let requestID: Int64
        let maxBufferedBytes: Int

        init(requestID: Int64, maxBufferedBytes: Int) {
            self.requestID = requestID
            self.maxBufferedBytes = maxBufferedBytes
        }

        private var hasPendingChunks: Bool { headIndex < pending.count }

        private func clearPendingLocked() {
            pending.removeAll(keepingCapacity: false)
            headIndex = 0
            pendingBytes = 0
        }

        func next() -> StreamChunk {
            lock.lock(); defer { lock.unlock() }
            while !hasPendingChunks && !headPending && !ended {
                lock.wait()
            }
            if headPending {
                headPending = false
                return StreamChunk(done: false, chunkBase64: nil, status: head?.status,
                                   headers: head?.headers, finalUrl: head?.finalURL.absoluteString, error: nil)
            }
            if hasPendingChunks {
                let piece = pending[headIndex]
                headIndex += 1
                pendingBytes = max(0, pendingBytes - piece.count)
                if headIndex == pending.count {
                    pending.removeAll(keepingCapacity: false)
                    headIndex = 0
                } else if headIndex >= 64 && headIndex * 2 >= pending.count {
                    pending.removeFirst(headIndex)
                    headIndex = 0
                }
                return StreamChunk(done: false, chunkBase64: piece.base64EncodedString(),
                                   status: nil, headers: nil, finalUrl: nil, error: nil)
            }
            return StreamChunk(done: true, chunkBase64: nil, status: head?.status ?? 0,
                               headers: head?.headers ?? [:], finalUrl: head?.finalURL.absoluteString ?? "",
                               error: failure?.localizedDescription)
        }

        func received(_ response: URLSessionTransport.Response) {
            lock.lock(); defer { lock.unlock() }
            guard !ended, head == nil else { return }
            head = response
            headPending = true
            lock.broadcast()
        }

        func append(_ data: Data) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !ended, !data.isEmpty else { return !ended }
            if pendingBytes + data.count > maxBufferedBytes {
                clearPendingLocked()
                headPending = false
                failure = CoreError("stream buffer exceeded \(maxBufferedBytes) bytes")
                ended = true
                lock.broadcast()
                return false
            }
            pending.append(data)
            pendingBytes += data.count
            lock.signal()
            return true
        }

        func finish(_ error: Error? = nil, discardingBody: Bool = false) {
            lock.lock(); defer { lock.unlock() }
            if discardingBody {
                clearPendingLocked()
                headPending = false
            }
            guard !ended else { return }
            failure = error
            ended = true
            lock.broadcast()
        }
    }

    private let transport: URLSessionTransport
    public let maxBufferedBytes: Int
    private let lock = NSLock()
    private var streams: [Int64: Stream] = [:]
    private var nextID: Int64 = 0

    public init(transport: URLSessionTransport, maxBufferedBytes: Int? = nil) {
        self.transport = transport
        self.maxBufferedBytes = max(1, maxBufferedBytes ?? transport.maxBodyBytes)
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
            let stream = Stream(requestID: w.id, maxBufferedBytes: maxBufferedBytes)
            lock.lock()
            nextID += 1
            let id = nextID
            streams[id] = stream
            lock.unlock()

            // The transfer runs beside Core's poll: the transport hands every
            // piece over as it arrives and the stream keeps them until Core
            // asks for the next one, bounded by `maxBufferedBytes`.
            Task {
                do {
                    _ = try await transport.sendStreaming(request, onResponse: { response in
                        stream.received(response)
                    }) { [transport] data in
                        if !stream.append(data) {
                            transport.cancel(id: stream.requestID)
                        }
                    }
                    stream.finish()
                } catch {
                    stream.finish(error)
                }
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
        let chunk = stream.next()
        if chunk.done {
            lock.lock()
            streams[id_] = nil
            lock.unlock()
        }
        return Self.json(chunk)
    }

    public func streamClose(_ id_: Int64) {
        lock.lock()
        let stream = streams.removeValue(forKey: id_)
        lock.unlock()
        if let stream {
            transport.cancel(id: stream.requestID)
            stream.finish(CancellationError(), discardingBody: true)
        }
    }

    private static func json(_ v: StreamChunk) -> String {
        (try? String(decoding: JSONEncoder().encode(v), as: UTF8.self)) ?? "{}"
    }
}
