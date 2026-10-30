import Foundation
#if canImport(WebKit)
import WebKit

/// Drives a WKWebView through a human-verification page.
///
/// The view shows `challenge.url`; after each navigation it checks Core's
/// done rule: none of `absentMarkers` in the page HTML and every
/// `requiredCookies` present. Then it copies the WebView's cookies for the
/// challenge host into the partition's jar and reports the WebView's
/// User-Agent, which Cloudflare binds clearance to.
///
/// Each verification uses a non-persistent data store, so pages never see
/// another source's cookies.
@MainActor
public final class VerificationSession: NSObject, WKNavigationDelegate {
    public let challenge: Challenge
    public let webView: WKWebView
    private let cookies: CookieJars
    private var continuation: CheckedContinuation<String?, Never>?
    private var finished = false

    public init(challenge: Challenge, cookies: CookieJars, userAgent: String?) {
        self.challenge = challenge
        self.cookies = cookies
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        if let userAgent { webView.customUserAgent = userAgent }
    }

    /// Loads the page and waits until it is passed (User-Agent) or
    /// `cancel()` is called (nil).
    public func run() async -> String? {
        guard let url = URL(string: challenge.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        // Send the cookies the partition already has, so a session the
        // source started is continued rather than replaced.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for c in cookies.cookies(partition: challenge.partition, url: url) {
            var props: [HTTPCookiePropertyKey: Any] = [.name: c.name, .value: c.value, .path: c.path ?? "/",
                                                       .domain: c.domain ?? url.host() ?? ""]
            if let e = c.expires, e > 0 { props[.expires] = Date(timeIntervalSince1970: TimeInterval(e) / 1000) }
            if c.secure == true { props[.secure] = "TRUE" }
            if let hc = HTTPCookie(properties: props) { await store.setCookie(hc) }
        }
        return await withCheckedContinuation { k in
            continuation = k
            webView.load(URLRequest(url: url))
        }
    }

    public func cancel() { finish(nil) }

    private func finish(_ ua: String?) {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        continuation?.resume(returning: ua)
        continuation = nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await check() }
    }

    /// Some challenges finish with script instead of a navigation, so the
    /// check also repeats briefly after each load.
    private func check() async {
        for _ in 0..<10 where !finished {
            if await passed() { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func passed() async -> Bool {
        guard let url = webView.url, let host = url.host()?.lowercased() else { return false }
        let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? ""
        for marker in challenge.absentMarkers ?? [] where html.contains(marker) { return false }
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let relevant = all.filter { c in
            let d = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == d || host.hasSuffix("." + d)
        }
        let names = Set(relevant.map(\.name))
        for required in challenge.requiredCookies ?? [] where !names.contains(required) { return false }
        cookies.importCookies(partition: challenge.partition, relevant)
        let ua = webView.customUserAgent?.isEmpty == false ? webView.customUserAgent
            : (try? await webView.evaluateJavaScript("navigator.userAgent") as? String)
        finish(ua ?? "")
        return true
    }
}
#endif
