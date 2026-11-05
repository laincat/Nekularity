import Foundation

/// The client's half of `host.DoneRule`: a declarative test of whether a page has
/// passed a challenge.
///
/// A rule is satisfied when every group that has entries holds, and at least one
/// group has entries. An empty group means "no condition" rather than "vacuously
/// true", so one rule can describe a challenge whose clearance is a cookie and
/// another whose clearance comes back in the URL.
public enum ChallengeRule {
    /// The parts of a page a rule is tested against.
    public struct Conditions: Sendable {
        public var html: String
        public var url: URL
        public var cookieNames: Set<String>
        /// The host the challenge guards, from `Challenge.url`. A rule with
        /// `sameHost` needs it; a cookie or marker rule does not.
        public var guardedHost: String?

        public init(html: String, url: URL, cookieNames: Set<String>, guardedHost: String? = nil) {
            self.html = html
            self.url = url
            self.cookieNames = cookieNames
            self.guardedHost = guardedHost
        }

        public func satisfied(absentMarkers: [String], requiredCookies: [String],
                              requiredQueryParams: [String], sameHost: Bool = false) -> Bool {
            if absentMarkers.isEmpty && requiredCookies.isEmpty && requiredQueryParams.isEmpty && !sameHost {
                return false
            }
            if sameHost {
                // Being back on the guarded host is the whole condition for the
                // edge shape; a window that has not loaded anything has no host,
                // and the challenge page itself lives elsewhere.
                guard let want = guardedHost?.lowercased(), !want.isEmpty,
                      let have = url.host()?.lowercased(), have == want else { return false }
            }
            for marker in absentMarkers where !marker.isEmpty && html.contains(marker) {
                return false
            }
            for name in requiredCookies where !cookieNames.contains(name) {
                return false
            }
            if !requiredQueryParams.isEmpty {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let present = Set(items.compactMap { ($0.value?.isEmpty == false) ? $0.name : nil })
                for want in requiredQueryParams where !present.contains(want) {
                    return false
                }
            }
            return true
        }
    }
}
