import Foundation

/// Sends Core's HTTP requests with URLSession.
///
/// Cookies never go through `HTTPCookieStorage`: the shared store would mix
/// partitions. The session is ephemeral with cookie handling off; the
/// transport adds the partition's Cookie header itself and stores every
/// Set-Cookie, including those on redirect hops.
public final class URLSessionTransport: NSObject, @unchecked Sendable, URLSessionTaskDelegate {
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
        return Response(status: http.statusCode, headers: headers, body: data, finalURL: finalURL)
    }

    /// Aborts request id (Core no longer waits for it).
    public func cancel(id: Int64) {
        lock.lock()
        let t = tasks[id]
        lock.unlock()
        t?.cancel()
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

    static func httpDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: d)
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
