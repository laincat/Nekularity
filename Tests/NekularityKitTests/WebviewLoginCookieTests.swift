import Foundation
import Testing
@testable import NekularityKit

#if canImport(WebKit)
/// Which cookies a finished login hands to the source.
///
/// The login page also loads third parties, and their cookies are not part of a
/// login the source asked for. The desktop client applies the same rule, and both
/// are written here because getting it wrong is silent: the source simply carries
/// another site's cookie into every later request.
@Suite("Webview login cookies")
struct WebviewLoginCookieTests {
    /// A cookie for this domain.
    ///
    /// `HTTPCookie(properties:)` returns nil unless the properties describe a
    /// complete cookie, and an Apple platform wants an origin URL; a force unwrap
    /// here crashed the whole test bundle instead of failing a case.
    private func cookie(_ name: String, domain: String) throws -> HTTPCookie {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: "v",
            .path: "/",
            .domain: domain,
        ]
        if let origin = URL(string: "https://\(host)/") { props[.originURL] = origin }
        return try #require(HTTPCookie(properties: props), "cannot build a cookie for \(domain)")
    }

    @Test func keepsTheLoginSiteAndDropsThirdParties() throws {
        let all = [try cookie("session", domain: "forums.e-hentai.org"),
                   try cookie("shared", domain: ".e-hentai.org"),
                   try cookie("other", domain: "analytics.test")]
        let kept = WebviewLoginSession.cookiesForHosts(all, hosts: ["forums.e-hentai.org"])
        #expect(Set(kept.map(\.name)) == ["session", "shared"])
    }

    /// A leading dot covers the host and its subdomains and nothing that merely
    /// looks similar.
    @Test func theDotRuleIsExact() throws {
        let all = [try cookie("sub", domain: ".nhentai.net"),
                   try cookie("lookalike", domain: ".notnhentai.net"),
                   try cookie("sibling", domain: "evilnhentai.net")]
        let kept = WebviewLoginSession.cookiesForHosts(all, hosts: ["nhentai.net"])
        #expect(kept.map(\.name) == ["sub"])
    }

    /// A login can finish on another host than it started on, so both count.
    @Test func coversTheStartingAndFinishingHost() throws {
        let all = [try cookie("forum", domain: "forums.mangadex.org"),
                   try cookie("site", domain: "mangadex.org"),
                   try cookie("shared", domain: ".mangadex.org"),
                   try cookie("other", domain: "analytics.test")]
        let kept = WebviewLoginSession.cookiesForHosts(all, hosts: ["forums.mangadex.org", "mangadex.org"])
        #expect(Set(kept.map(\.name)) == ["forum", "site", "shared"])
    }

    /// No host means no cookies, rather than all of them. A cookie with no domain
    /// at all is a host-only cookie and is kept; that case is covered by the
    /// desktop test, because a cookie built here always names a domain.
    @Test func noHostKeepsNothing() throws {
        let all = [try cookie("a", domain: "x.test")]
        #expect(WebviewLoginSession.cookiesForHosts(all, hosts: []).isEmpty)
    }
}
#endif
