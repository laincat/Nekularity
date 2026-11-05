import Foundation
import Testing

@testable import NekularityKit

@Suite("ChallengeRule")
struct ChallengeRuleTests {
    private func conditions(html: String = "<html></html>",
                            query: String = "",
                            cookies: Set<String> = ["cf_clearance"],
                            host: String = "example.test",
                            guardedHost: String? = nil)
        -> ChallengeRule.Conditions {
        let url = URL(string: "https://" + host + "/page" + query)!
        return ChallengeRule.Conditions(html: html, url: url, cookieNames: cookies,
                                        guardedHost: guardedHost)
    }

    @Test("a rule with nothing to check never passes")
    func emptyRuleNeverPasses() {
        #expect(conditions().satisfied(absentMarkers: [], requiredCookies: [],
                                       requiredQueryParams: []) == false)
    }

    @Test("a cookie rule needs the markers gone and the cookie present")
    func cookieRule() {
        #expect(conditions().satisfied(absentMarkers: ["challenge-form"],
                                       requiredCookies: ["cf_clearance"],
                                       requiredQueryParams: []) == true)
        #expect(conditions(html: "<div id=\"challenge-form\"></div>")
            .satisfied(absentMarkers: ["challenge-form"], requiredCookies: ["cf_clearance"],
                       requiredQueryParams: []) == false)
        #expect(conditions(cookies: []).satisfied(absentMarkers: ["challenge-form"],
                                                  requiredCookies: ["cf_clearance"],
                                                  requiredQueryParams: []) == false)
    }

    @Test("a MangaDex-shaped rule needs its parameters in the URL")
    func edgeRule() {
        let rule: ([String]) -> Bool = { parameters in
            self.conditions().satisfied(absentMarkers: [], requiredCookies: [],
                                        requiredQueryParams: parameters)
        }
        #expect(rule(["powblock", "pbchal"]) == false)
        #expect(conditions(query: "?powblock=abc&pbchal=def").satisfied(
            absentMarkers: [], requiredCookies: [], requiredQueryParams: ["powblock", "pbchal"]) == true)
        #expect(conditions(query: "?powblock=abc&pbchal=").satisfied(
            absentMarkers: [], requiredCookies: [], requiredQueryParams: ["powblock", "pbchal"]) == false)
    }

    // The edge shape ends on the guarded host. Without this, a window that has
    // not loaded anything yet has no challenge markers in it either, so a
    // markers-only rule would report a pass immediately.
    @Test("a rule that names the guarded host is only satisfied back on it")
    func sameHostRule() {
        let rule = conditions(html: "", cookies: [], host: "mangadex.org",
                              guardedHost: "api.mangadex.org")
        #expect(rule.satisfied(absentMarkers: ["challenge-assets"], requiredCookies: [],
                               requiredQueryParams: [], sameHost: true) == false)
        let guarded = conditions(html: "<html></html>", cookies: [], host: "api.mangadex.org",
                                 guardedHost: "api.mangadex.org")
        #expect(guarded.satisfied(absentMarkers: ["challenge-assets"], requiredCookies: [],
                                  requiredQueryParams: [], sameHost: true) == true)
        // Same host, but the challenge page is still on screen.
        let still = conditions(html: "challenge-assets/challenge.js", cookies: [],
                               host: "api.mangadex.org", guardedHost: "api.mangadex.org")
        #expect(still.satisfied(absentMarkers: ["challenge-assets"], requiredCookies: [],
                                requiredQueryParams: [], sameHost: true) == false)
        // A rule with no host condition keeps working without one.
        #expect(conditions().satisfied(absentMarkers: ["challenge-form"],
                                       requiredCookies: ["cf_clearance"],
                                       requiredQueryParams: []) == true)
    }

    @Test("groups are a conjunction, and an unlisted group asks for nothing")
    func groupsCombine() {
        let both = conditions(query: "?powblock=abc&pbchal=def")
        #expect(both.satisfied(absentMarkers: ["challenge-form"], requiredCookies: ["cf_clearance"],
                               requiredQueryParams: ["powblock", "pbchal"]) == true)
        #expect(both.satisfied(absentMarkers: ["challenge-form"], requiredCookies: ["missing"],
                               requiredQueryParams: ["powblock", "pbchal"]) == false)
    }
}
