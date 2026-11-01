import Foundation
import Testing

@testable import NekularityKit

@Suite("ChallengeRule")
struct ChallengeRuleTests {
    private func conditions(html: String = "<html></html>",
                            query: String = "",
                            cookies: Set<String> = ["cf_clearance"])
        -> ChallengeRule.Conditions {
        let url = URL(string: "https://example.test/page" + query)!
        return ChallengeRule.Conditions(html: html, url: url, cookieNames: cookies)
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

    @Test("groups are a conjunction, and an unlisted group asks for nothing")
    func groupsCombine() {
        let both = conditions(query: "?powblock=abc&pbchal=def")
        #expect(both.satisfied(absentMarkers: ["challenge-form"], requiredCookies: ["cf_clearance"],
                               requiredQueryParams: ["powblock", "pbchal"]) == true)
        #expect(both.satisfied(absentMarkers: ["challenge-form"], requiredCookies: ["missing"],
                               requiredQueryParams: ["powblock", "pbchal"]) == false)
    }
}
