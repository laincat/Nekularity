import Foundation

/// Sends Core's HTTP requests with URLSession.
///
/// Cookies never go through `HTTPCookieStorage`: the shared store would mix
/// partitions. The session is ephemeral with cookie handling off; the
/// transport adds the partition's Cookie header itself and stores every
/// Set-Cookie, including those on redirect hops.
public final class URLSessionTransport: NSObject, @unchecked Sendable {
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

    private let delegate = TransportDelegate()
    private var session: URLSession!

    private let lock = NSLock()
    private var tasks: [Int64: URLSessionTask] = [:]
    /// Ids cancelled before their task existed. A cancel that arrives while the
    /// call is still being queued must not be forgotten: the request would then
    /// run for a user who already gave up.
    private var cancelledEarly: Set<Int64> = []
    /// The scheme each partition last used, so a source that serves its pages
    /// over http keeps its images over http too. A scheme-relative image
    /// address inherits this, as RFC 3986 says it inherits the page's.
    private var partitionSchemes: [String: String] = [:]

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
        // The delegate is a separate object that points back here weakly:
        // URLSession keeps its delegate alive, so a session built with
        // `delegate: self` would keep this transport (and its cookies and
        // buffers) alive for the life of the process.
        delegate.owner = self
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        // Ends the delegate's retain and closes every open connection instead of
        // letting them run on with nobody reading.
        session.invalidateAndCancel()
    }

    /// Sends a request and waits for the whole body.
    public func send(_ r: Request) async throws -> Response {
        try await perform(r, onChunk: nil)
    }

    /// Sends a request and hands each piece of the body over as it arrives.
    ///
    /// Same request path, same cookies, same cancellation and the same size
    /// limit as `send`; the difference is that `onChunk` is called on the
    /// delegate queue for every piece, before the reply is done. The returned
    /// `Response` still carries the whole body, because a caller may want both.
    /// `onResponse` receives accepted final headers with an empty body before
    /// any body callback, including HTTP error statuses.
    public func sendStreaming(_ r: Request,
                              onResponse: (@Sendable (Response) -> Void)? = nil,
                              onChunk: @escaping @Sendable (Data) -> Void) async throws -> Response {
        try await perform(r, onResponse: onResponse, onChunk: onChunk)
    }

    private func perform(_ r: Request, onResponse: (@Sendable (Response) -> Void)? = nil,
                         onChunk: (@Sendable (Data) -> Void)?) async throws -> Response {
        if takeEarlyCancellation(r.id) {
            throw CoreError("request cancelled before it started")
        }
        var req = URLRequest(url: r.url)
        req.httpMethod = r.method
        req.httpBody = r.body
        var manual: [String: [String]] = [:]
        for (k, values) in r.headers where k.caseInsensitiveCompare("Cookie") != .orderedSame {
            // URLRequest joins repeated headers with commas.
            req.setValue(values.joined(separator: ", "), forHTTPHeaderField: k)
            manual[k] = values
        }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        let manualCookie = r.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value.joined(separator: "; ")
        var cookieHeader = manualCookie
        if r.useCookies, let stored = cookies.header(partition: r.partition, url: r.url) {
            cookieHeader = [cookieHeader, stored].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "; ")
        }
        if let cookieHeader, !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }

        let state = TaskState(limit: maxBodyBytes, partition: r.partition, useCookies: r.useCookies,
                              manualHeaders: manual, manualCookie: manualCookie,
                              cookies: cookies, origin: r.url, onResponse: onResponse, onChunk: onChunk)
        let (data, http): (Data, HTTPURLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { k in
                state.attach(k)
                let task = session.dataTask(with: req)
                state.task = task
                delegate.register(task: task, state: state)
                lock.lock()
                if cancelledEarly.remove(r.id) != nil {
                    lock.unlock()
                    state.finish(.failure(CoreError("request cancelled before it started")))
                    task.cancel()
                    return
                }
                tasks[r.id] = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            state.cancel()
        }
        lock.withLock { tasks[r.id] = nil }
        delegate.forget(state)

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
    ///
    /// A cancel that arrives before the task is registered is remembered until
    /// the send starts, so that request is never sent at all.
    public func cancel(id: Int64) {
        let task: URLSessionTask? = lock.withLock {
            if let t = tasks[id] { return t }
            cancelledEarly.insert(id)
            return nil
        }
        task?.cancel()
    }

    private func takeEarlyCancellation(_ id: Int64) -> Bool {
        lock.withLock { cancelledEarly.remove(id) != nil }
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

    static func httpDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: d)
    }
}

/// Header names that carry a credential. They are the caller's, not the jar's, so
/// they must not follow a redirect to another origin.
let credentialHeaderNames: Set<String> = [
    "authorization", "proxy-authorization", "cookie", "x-api-key", "api-key",
    "x-auth-token", "x-access-token", "x-goog-api-key",
]

/// The session delegate.
///
/// It owns the per-request state, so a transport that goes away cannot strand a
/// continuation: the delegate keeps only a weak reference back to the transport,
/// and finishes requests with an error when there is no owner left.
///
/// Being the data delegate is what makes the size limit real: Foundation hands
/// the body over in pieces, and a piece that would cross the limit stops the
/// transfer instead of being buffered first.
final class TransportDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    weak var owner: URLSessionTransport?

    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]

    func register(task: URLSessionTask, state: TaskState) {
        lock.withLock { states[task.taskIdentifier] = state }
    }

    func forget(_ state: TaskState) {
        let key: Int? = lock.withLock {
            states.first { $0.value === state }?.key
        }
        if let key { lock.withLock { states[key] = nil } }
    }

    private func state(for task: URLSessionTask) -> TaskState? {
        lock.withLock { states[task.taskIdentifier] }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let state = state(for: dataTask) else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse else {
            state.finish(.failure(CoreError("not an HTTP response")))
            completionHandler(.cancel)
            return
        }
        // A declared length over the limit is refused before a byte is read.
        if response.expectedContentLength > Int64(state.limit) {
            state.finish(.failure(CoreError("response larger than \(state.limit) bytes")))
            completionHandler(.cancel)
            return
        }
        state.received(http)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let state = state(for: dataTask) else { return }
        if !state.append(data) {
            // Crossing the limit cancels the transfer here; the completion
            // handler then reports it, so the server cannot push the rest.
            state.finish(.failure(CoreError("response larger than \(state.limit) bytes")))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let state = state(for: task), let final = task.currentRequest?.url ?? task.response?.url else { return }
        if let error {
            state.finish(.failure(error))
        } else if state.isFinished {
            // Already reported, for example when the size limit stopped it.
        } else {
            state.finish(.success(final))
        }
    }

    /// Keeps cookies set on redirect hops, and decides which caller headers may
    /// travel on.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let state = state(for: task) else { return request }
        let from = response.url ?? task.currentRequest?.url ?? state.origin
        state.storeHopCookies(from: from, response: response)
        return state.redirected(request)
    }
}

extension TaskState {
    /// The headers a redirect may carry.
    ///
    /// Same origin is the same server, so the caller's headers still apply there.
    /// Another origin is a different server: the caller's credential headers stay
    /// behind, and `Cookie` is rebuilt from the jar so it names the new host's
    /// cookies rather than the old host's.
    ///
    /// This is separate from the delegate so the rule can be checked without a
    /// server: custom `URLProtocol` clients never see a redirect, and the real
    /// network is not available to a unit test.
    func redirected(_ request: URLRequest) -> URLRequest {
        let to = request.url ?? origin
        var out = request
        out.setValue(nil, forHTTPHeaderField: "Cookie")
        let sameOrigin = origin.isSameOrigin(as: to)
        if sameOrigin {
            for (name, values) in manualHeaders {
                out.setValue(values.joined(separator: ", "), forHTTPHeaderField: name)
            }
        } else {
            for name in credentialHeaderNames {
                out.setValue(nil, forHTTPHeaderField: name)
            }
        }
        guard useCookies else {
            if sameOrigin, let cookie = manualCookie, !cookie.isEmpty {
                out.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            return out
        }
        var cookie = sameOrigin ? manualCookie : nil
        if let stored = cookies.header(partition: partition, url: to) {
            cookie = [cookie, stored].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "; ")
        }
        if let cookie, !cookie.isEmpty { out.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return out
    }
}

extension URL {
    /// Scheme, host and effective port: the comparison a redirect needs before it
    /// lets a caller's credential header travel.
    func isSameOrigin(as other: URL) -> Bool {
        guard let a = scheme?.lowercased(), let b = other.scheme?.lowercased(), a == b else { return false }
        guard let ha = host()?.lowercased(), let hb = other.host()?.lowercased(), ha == hb else { return false }
        return effectivePort == other.effectivePort
    }

    var effectivePort: Int? {
        if let p = port { return p }
        switch scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

/// One request in flight: the received body, the limit, and the continuation.
///
/// Every finish goes through one lock, so a cancellation, a size refusal and a
/// normal completion cannot resume the same continuation twice.
final class TaskState: @unchecked Sendable {
    let limit: Int
    let partition: String
    let useCookies: Bool
    let manualHeaders: [String: [String]]
    let manualCookie: String?
    let cookies: CookieJars
    let origin: URL
    /// Called when the final response head is accepted, before body pieces.
    private let onResponse: (@Sendable (URLSessionTransport.Response) -> Void)?
    /// Called with every accepted piece, for the streaming path.
    private let onChunk: (@Sendable (Data) -> Void)?

    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var body = Data()
    private var http: HTTPURLResponse?
    private var done = false
    private var cancelled = false

    init(limit: Int, partition: String, useCookies: Bool, manualHeaders: [String: [String]],
         manualCookie: String?, cookies: CookieJars, origin: URL,
         onResponse: (@Sendable (URLSessionTransport.Response) -> Void)? = nil,
         onChunk: (@Sendable (Data) -> Void)? = nil) {
        self.limit = limit
        self.partition = partition
        self.useCookies = useCookies
        self.manualHeaders = manualHeaders
        self.manualCookie = manualCookie
        self.cookies = cookies
        self.origin = origin
        self.onResponse = onResponse
        self.onChunk = onChunk
    }

    /// The URLSession task, once it exists, so a cancelled waiter stops the
    /// transfer instead of leaving it running with nobody to read it.
    weak var task: URLSessionTask?
    var isFinished: Bool { lock.withLock { done } }

    func attach(_ k: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        let finishNow: Error? = lock.withLock {
            if done { return CoreError("request finished twice") }
            continuation = k
            return cancelled ? CoreError("request cancelled") : nil
        }
        if let finishNow { finish(.failure(finishNow)) }
    }

    func received(_ response: HTTPURLResponse) {
        let notify = lock.withLock {
            guard !done, http == nil else { return false }
            http = response
            return true
        }
        guard notify, let onResponse else { return }
        var headers: [String: [String]] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            headers[key, default: []].append(value)
        }
        // Notify outside the state lock: a consumer may cancel from this call.
        onResponse(URLSessionTransport.Response(status: response.statusCode, headers: headers,
                                                 body: Data(), finalURL: response.url ?? origin))
    }

    /// Appends one piece, refusing the piece that would cross the limit.
    ///
    /// The chunk callback runs outside the lock: it re-enters the caller's code,
    /// and holding this lock across it would let a slow consumer stall the
    /// transfer.
    func append(_ data: Data) -> Bool {
        let accepted: Bool = lock.withLock {
            guard !done else { return true }
            if body.count + data.count > limit { return false }
            body.append(data)
            return true
        }
        if accepted, let onChunk { onChunk(data) }
        return accepted
    }

    func storeHopCookies(from url: URL, response: HTTPURLResponse) {
        guard useCookies else { return }
        cookies.store(partition: partition, url: url, setCookieHeaders: URLSessionTransport.setCookieHeaders(response))
    }

    func finish(_ result: Result<URL, Error>) {
        let toResume: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        let outcome: Result<(Data, HTTPURLResponse), Error>
        (toResume, outcome) = lock.withLock {
            guard !done else { return (nil, .failure(CoreError("request finished twice"))) }
            done = true
            let k = continuation
            continuation = nil
            switch result {
            case .failure(let error):
                return (k, .failure(error))
            case .success:
                guard let http = http else { return (k, .failure(CoreError("not an HTTP response"))) }
                return (k, .success((body, http)))
            }
        }
        toResume?.resume(with: outcome)
    }

    /// Called when the Swift task that awaited this request is cancelled.
    func cancel() {
        let k: CheckedContinuation<(Data, HTTPURLResponse), Error>? = lock.withLock {
            cancelled = true
            guard !done else { return nil }
            done = true
            let k = continuation
            continuation = nil
            return k
        }
        k?.resume(throwing: CancellationError())
        task?.cancel()
    }
}
