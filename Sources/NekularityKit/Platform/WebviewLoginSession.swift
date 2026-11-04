import Foundation
#if canImport(WebKit)
import WebKit

/// Runs a source's own login page in a WKWebView.
///
/// Five official sources log in on their site rather than with a form, and the
/// client cannot know which page means "logged in": the source does, through
/// `checkStatus(url, title)`. So the session polls the page and asks Core, then
/// moves the cookies it earned into the source's partition and runs
/// `onLoginSuccess`.
///
/// The data store is non-persistent, so this page starts clean and its cookies
/// cannot leak into another source's verification. Whatever the user typed stays
/// in the WebView until the session reports back.
@MainActor
public final class WebviewLoginSession: NSObject, WKNavigationDelegate {
    public let login: WebviewLogin
    /// The page, so a view can show it.
    public let webView: WKWebView
    private let key: String
    private let partition: String
    private let core: CoreClient
    private let jars: CookieJars
    private var continuation: CheckedContinuation<Int, Error>?
    private var finished = false
    /// Bumped on every navigation so an older poll cannot report a newer page.
    private var generation = 0

    public init(login: WebviewLogin, key: String, partition: String,
                core: CoreClient, jars: CookieJars) {
        self.login = login
        self.key = key
        self.partition = partition
        self.core = core
        self.jars = jars
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads the page and waits until the source says it is logged in. Returns
    /// the number of cookies kept, so the caller can say what happened.
    public func run() async throws -> Int {
        guard let url = URL(string: login.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw CoreError("this source's login page is not a web address")
        }
        // The view can disappear without the user pressing 取消 — a caller that
        // drops the task would otherwise leave this continuation waiting for a
        // page nobody is looking at.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { k in
                if Task.isCancelled {
                    k.resume(throwing: CancellationError())
                    return
                }
                continuation = k
                webView.load(URLRequest(url: url))
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    /// The user gave up: nothing is stored, and the window can close.
    public func cancel() {
        finish(.failure(CoreError("login cancelled")))
    }

    private func finish(_ result: Result<Int, Error>) {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        switch result {
        case .success(let count): continuation?.resume(returning: count)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        generation += 1
        let mine = generation
        Task { await poll(mine) }
    }

    /// Some login pages swap the title without navigating, so the check repeats
    /// for a while after each load instead of running once.
    private func poll(_ mine: Int) async {
        for _ in 0..<90 {
            if finished || mine != generation { return }
            if await check(mine) { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func check(_ mine: Int) async -> Bool {
        guard let url = webView.url?.absoluteString else { return false }
        let title = (try? await webView.evaluateJavaScript("document.title") as? String) ?? ""
        guard !finished, mine == generation else { return true }
        let status: Bool
        do {
            status = try await core.webviewStatus(key: key, handle: login.handle,
                                                   pageURL: url, title: title)
        } catch let error as CoreError where error.isWebviewHandleGone {
            // The source was updated or removed while this page was open: the
            // handle belongs to a runtime that is gone, and polling it can never
            // succeed. Ordinary source errors keep the wait going.
            finish(.failure(error))
            return true
        } catch {
            return false
        }
        guard status else { return false }
        guard !finished, mine == generation else { return true }
        let count: Int
        do {
            count = try await store(generation: mine)
        } catch {
            // The cookies can arrive after checkStatus first succeeds.
            return finished || mine != generation
        }
        guard !finished, mine == generation else { return true }
        do {
            try await core.webviewLoginDone(key: key, handle: login.handle)
            guard !finished else { return true }
            finish(.success(count))
        } catch {
            // Cookies have already been stored; report the callback failure.
            finish(.failure(error))
        }
        return true
    }

    /// The cookies that belong to the login site, out of everything the page set.
    ///
    /// The rule is the browser's: a leading dot means the host and its subdomains,
    /// no dot means that exact host, and a cookie with no domain belongs to the
    /// page that set it. Anything else was set by a third party the page loaded and
    /// is not part of a login the source asked for.
    nonisolated static func cookiesForHosts(_ cookies: [HTTPCookie], hosts: [String]) -> [HTTPCookie] {
        let wanted = hosts.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: .whitespaces)
            if domain.isEmpty { return true }
            for host in wanted {
                if domain.hasPrefix(".") {
                    if host == String(domain.dropFirst()) || host.hasSuffix(domain) { return true }
                } else if host == domain {
                    return true
                }
            }
            return false
        }
    }

    /// Moves the login site's cookies into the source's partition, which is what
    /// every later request reads.
    ///
    /// Only that site's cookies: the page also loads third parties, and their
    /// cookies are not part of a login the source asked for. The rule is the
    /// browser's — a leading dot means the host and its subdomains, no dot means
    /// that exact host, and no domain at all means the page that set it.
    private func store(generation mine: Int) async throws -> Int {
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard !finished, mine == generation else { throw CancellationError() }
        guard let start = URL(string: login.url)?.host()?.lowercased() else {
            throw CoreError("this source's login page is not a web address")
        }
        // A login can finish on another host than it started on (manga_dex goes
        // from forums.mangadex.org back to mangadex.org), so both count.
        var hosts = [start]
        if let done = webView.url?.host()?.lowercased(), !hosts.contains(done) {
            hosts.append(done)
        }
        let mine = Self.cookiesForHosts(all, hosts: hosts)
        guard !mine.isEmpty else {
            throw CoreError("the login page set no cookies to keep")
        }
        jars.importCookies(partition: partition, mine)
        return mine.count
    }
}
#endif
