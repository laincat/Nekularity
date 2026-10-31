import Foundation

/// Sends Core's HTTP requests with URLSession.
///
/// Cookies never go through `HTTPCookieStorage`: the shared store would mix
/// partitions. The session is ephemeral with cookie handling off; the
/// transport adds the partition's Cookie header itself and stores every
/// Set-Cookie, including those on redirect hops.
public final class URLSessionTransport: NSObject, @unchecked Sendable, URLSessionDataDelegate {
    public struct Request: Sendable {
        public var id: Int64
        public var method: String
        public var url: URL
        public var headers: [String: [String]]
        public var body: Data?
        public var useCookies: Bool
        public var partition: String
    }

    public struct Response: Sendable {
        public var status: Int
        public var headers: [String: [String]]
        public var body: Data
        public var finalURL: URL
    }

    private let cookies: CookieJars
    private let defaultUserAgent: String
    /// Responses larger than this fail instead of exhausting memory.
    public var maxBodyBytes = 64 << 20

    private var session: URLSession!
    private let lock = NSLock()
    private var tasks: [Int64: URLSessionTask] = [:]
    /// Partition and cookie flag per task, for redirect handling.
    private var taskInfo: [Int: (partition: String, useCookies: Bool)] = [:]
    /// The scheme each partition last used, so a source that serves its pages
    /// over http keeps its images over http too. A scheme-relative image
    /// address inherits this, as RFC 3986 says it inherits the page's.
    private var partitionSchemes: [String: String] = [:]
    /// The collector of a streaming request, keyed by the task that owns it.
    private var streams: [Int: StreamCollector] = [:]

    /// `configuration` exists for tests: a stub protocol cannot be installed into a
    /// session this type builds itself, and the cookie and cancellation rules are
    /// exactly what is worth testing.
    public init(cookies: CookieJars, defaultUserAgent: String, timeout: TimeInterval = 30,
                configuration: URLSessionConfiguration? = nil) {
        self.cookies = cookies
        self.defaultUserAgent = defaultUserAgent
        super.init()
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        // A caller-supplied configuration keeps its protocol classes but not its
        // cookie policy: mixing partitions is the thing this type exists to prevent.
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 4
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Sends a request and waits for the whole body.
    public func send(_ r: Request) async throws -> Response {
        var req = URLRequest(url: r.url)
        req.httpMethod = r.method
        req.httpBody = r.body
        for (k, values) in r.headers where k.caseInsensitiveCompare("Cookie") != .orderedSame {
            // URLRequest joins repeated headers with commas.
            req.setValue(values.joined(separator: ", "), forHTTPHeaderField: k)
        }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        var cookieHeader = r.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value.joined(separator: "; ")
        if r.useCookies, let stored = cookies.header(partition: r.partition, url: r.url) {
            cookieHeader = [cookieHeader, stored].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "; ")
        }
        if let cookieHeader, !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }

        // One task carries the request, so cancellation and the redirect
        // delegate see the task that is actually running.
        let box = TaskBox()
        defer {
            if let task = box.task {
                lock.withLock {
                    tasks[r.id] = nil
                    taskInfo[task.taskIdentifier] = nil
                }
            }
        }
        let (data, response): (Data, URLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { k in
                let task = session.dataTask(with: req) { data, response, error in
                    if let error { k.resume(throwing: error) } else if let data, let response { k.resume(returning: (data, response)) }
                    else { k.resume(throwing: CoreError("empty response")) }
                }
                lock.withLock {
                    tasks[r.id] = task
                    taskInfo[task.taskIdentifier] = (r.partition, r.useCookies)
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
        guard let http = response as? HTTPURLResponse else { throw CoreError("not an HTTP response") }
        guard data.count <= maxBodyBytes else { throw CoreError("response larger than \(maxBodyBytes) bytes") }

        var headers: [String: [String]] = [:]
        for (k, v) in http.allHeaderFields {
            guard let k = k as? String, let v = v as? String else { continue }
            headers[k, default: []].append(v)
        }
        let finalURL = http.url ?? r.url
        if r.useCookies {
            cookies.store(partition: r.partition, url: finalURL, setCookieHeaders: Self.setCookieHeaders(http))
        }
        rememberScheme(partition: r.partition, url: finalURL)
        return Response(status: http.statusCode, headers: headers, body: data, finalURL: finalURL)
    }

    /// Remembers the scheme a partition used, so a scheme-relative address
    /// can inherit it.
    private func rememberScheme(partition: String, url: URL) {
        guard !partition.isEmpty, let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        lock.withLock { partitionSchemes[partition] = scheme }
    }

    /// The scheme a partition last used, or "" when it has not asked for
    /// anything yet.
    public func scheme(partition: String) -> String {
        lock.withLock { partitionSchemes[partition] ?? "" }
    }

    /// Aborts request id (Core no longer waits for it).
    public func cancel(id: Int64) {
        lock.lock()
        let t = tasks[id]
        lock.unlock()
        t?.cancel()
    }

    /// Sends a request and hands the body over while it is still arriving.
    ///
    /// The whole-reply path waits for the body; this one does not, so a chat
    /// can be drawn as it is written. `onChunk` is called on an arbitrary
    /// queue with each piece of the body, in the order the server sent them.
    /// Cancelling by request id aborts the transfer.
    public func sendStreaming(_ r: Request, onChunk: @escaping @Sendable (Data) -> Void) async throws -> Response {
        var req = URLRequest(url: r.url)
        req.httpMethod = r.method
        req.httpBody = r.body
        for (k, values) in r.headers where k.caseInsensitiveCompare("Cookie") != .orderedSame {
            req.setValue(values.joined(separator: ", "), forHTTPHeaderField: k)
        }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        var cookieHeader = r.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value.joined(separator: "; ")
        if r.useCookies, let stored = cookies.header(partition: r.partition, url: r.url) {
            cookieHeader = [cookieHeader, stored].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "; ")
        }
        if let cookieHeader, !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }

        let collector = StreamCollector(onChunk: onChunk, limit: maxBodyBytes)
        let box = TaskBox()
        defer {
            if let task = box.task {
                lock.withLock {
                    tasks[r.id] = nil
                    taskInfo[task.taskIdentifier] = nil
                    streams[task.taskIdentifier] = nil
                }
            }
        }
        let response: HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { k in
                let task = session.dataTask(with: req)
                lock.withLock {
                    tasks[r.id] = task
                    taskInfo[task.taskIdentifier] = (r.partition, r.useCookies)
                    streams[task.taskIdentifier] = collector
                }
                box.set(task)
                task.resume()
                collector.setTask(task)
                collector.onFinish = { result in k.resume(with: result) }
            }
        } onCancel: {
            box.cancel()
        }

        var headers: [String: [String]] = [:]
        for (k, v) in response.allHeaderFields {
            guard let k = k as? String, let v = v as? String else { continue }
            headers[k, default: []].append(v)
        }
        let finalURL = response.url ?? r.url
        if r.useCookies {
            cookies.store(partition: r.partition, url: finalURL, setCookieHeaders: Self.setCookieHeaders(response))
        }
        rememberScheme(partition: r.partition, url: finalURL)
        return Response(status: response.statusCode, headers: headers, body: collector.body, finalURL: finalURL)
    }

    /// Set-Cookie values. Foundation folds repeated headers into one string,
    /// which `HTTPCookie` can split; values are then re-serialised so the jar
    /// parses them uniformly.
    static func setCookieHeaders(_ http: HTTPURLResponse) -> [String] {
        guard let url = http.url else { return [] }
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { out, kv in
            if let k = kv.key as? String, let v = kv.value as? String { out[k] = v }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map { c in
            var s = "\(c.name)=\(c.value); Path=\(c.path)"
            if c.domain.hasPrefix(".") { s += "; Domain=\(c.domain)" }
            if let d = c.expiresDate { s += "; Expires=\(httpDate(d))" }
            if c.isSecure { s += "; Secure" }
            if c.isHTTPOnly { s += "; HttpOnly" }
            return s
        }
    }

    /// Holds the running task for the cancellation handler, which may run
    /// before the task exists.
    final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private(set) var task: URLSessionTask?

        func set(_ t: URLSessionTask) {
            lock.lock(); defer { lock.unlock() }
            task = t
            if cancelled { t.cancel() }
        }

        func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
            task?.cancel()
        }
    }

    /// Collects the pieces of a streaming reply and hands each one over as it
    /// arrives.
    ///
    /// It exists because a continuation may only be resumed once, while the
    /// body arrives in many pieces: the collector decides when the reply is
    /// over and resumes then. The pieces are also kept, because the caller
    /// still wants the whole body at the end.
    final class StreamCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var pieces: [Data] = []
        /// The body as it arrived, so the caller can have the whole reply too.
        private var whole = Data()
        private var total = 0
        private let limit: Int
        private let onChunk: @Sendable (Data) -> Void
        private var finished = false
        private var head: HTTPURLResponse?
        private var task: URLSessionTask?
        /// Called once, when the reply is over.
        var onFinish: ((Result<HTTPURLResponse, Error>) -> Void)?

        init(onChunk: @escaping @Sendable (Data) -> Void, limit: Int) {
            self.onChunk = onChunk
            self.limit = limit
        }

        /// The reply's head, which arrives before the body.
        func setHead(_ h: HTTPURLResponse) {
            lock.lock(); defer { lock.unlock() }
            head = h
        }

        /// The running task, so the collector can cancel it.
        func setTask(_ t: URLSessionTask) {
            lock.lock(); defer { lock.unlock() }
            task = t
        }

        /// The task, if there is one.
        var currentTask: URLSessionTask? {
            lock.lock(); defer { lock.unlock() }
            return task
        }

        /// The whole body, as it arrived. It is accumulated as the pieces come
        /// in, so asking for it at the end does not copy the body again.
        var body: Data {
            lock.lock(); defer { lock.unlock() }
            return whole
        }

        /// Takes one piece and hands it over.
        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            if total + data.count > limit {
                let running = task
                lock.unlock()
                running?.cancel()
                finish(CoreError("response larger than \(limit) bytes"))
                return
            }
            pieces.append(data)
            whole.append(data)
            total += data.count
            lock.unlock()
            onChunk(data)
        }

        /// Ends the reply: with the head when it worked, with the error when it
        /// did not.
        func finish(_ error: Error?) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            let answer = head
            let resume = onFinish
            onFinish = nil
            lock.unlock()
            guard let resume else { return }
            if let error {
                resume(.failure(error))
            } else if let answer {
                resume(.success(answer))
            } else {
                resume(.failure(CoreError("empty response")))
            }
        }
    }

    static func httpDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: d)
    }

    // MARK: URLSessionDataDelegate

    /// Hands each piece of the body over as it arrives.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let collector = lock.withLock { streams[dataTask.taskIdentifier] }
        collector?.append(data)
    }

    /// The reply's head arrives before its body.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let collector = lock.withLock { streams[dataTask.taskIdentifier] }
        if let head = response as? HTTPURLResponse { collector?.setHead(head) }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let collector = lock.withLock { streams[task.taskIdentifier] }
        collector?.finish(error)
    }

    // MARK: URLSessionTaskDelegate

    /// Keeps cookies set on redirect hops and sends the partition's cookies
    /// to the next URL, which may be another host.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        let info = lock.withLock { taskInfo[task.taskIdentifier] }
        guard let info, info.useCookies, let next = request.url else { return request }
        if let from = response.url {
            cookies.store(partition: info.partition, url: from, setCookieHeaders: Self.setCookieHeaders(response))
        }
        var out = request
        out.setValue(cookies.header(partition: info.partition, url: next), forHTTPHeaderField: "Cookie")
        return out
    }
}
