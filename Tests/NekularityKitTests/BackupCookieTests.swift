import Foundation
import Testing

@testable import NekularityKit

/// Restoring the official app's single jar into per-source partitions.
///
/// The point of these tests is that nothing quietly becomes a shared jar, and that
/// a cookie is only written where Core said it belongs.
@Suite struct BackupCookieTests {
    private func plan(cookies: [BackupCookie]?, targets: [String]?) -> BackupPlan {
        var plan = BackupPlan()
        plan.cookies = cookies
        plan.cookieTargets = targets
        return plan
    }

    @Test func everyCookieReachesEveryTarget() {
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [
            BackupCookie(name: "sid", value: "a", domain: ".wnacg.com"),
            BackupCookie(name: "cf", value: "b", domain: "mangadex.org", path: "/",
                         expires: 1_900_000_000_000, secure: true, httpOnly: true),
        ], targets: ["copy_manga", "mangadex"])

        let written = BackupImporter.restoreCookies(plan, jars: jars)

        #expect(written == 4)
        for partition in ["copy_manga", "mangadex"] {
            let sid = jars.header(partition: partition, url: URL(string: "https://wnacg.com/")!)
            #expect(sid?.contains("sid=a") == true)
            let cf = jars.header(partition: partition, url: URL(string: "https://mangadex.org/")!)
            #expect(cf?.contains("cf=b") == true)
        }
    }

    @Test func aPartitionOnlySendsCookiesForItsOwnDomain() {
        // The reason no per-source filtering is needed: a jar matches on host, so a
        // copy in a partition that never visits that host is inert rather than shared.
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [BackupCookie(name: "sid", value: "a", domain: ".wnacg.com")],
                        targets: ["copy_manga"])
        _ = BackupImporter.restoreCookies(plan, jars: jars)

        #expect(jars.header(partition: CookiePartition.comic("copy_manga"), url: URL(string: "https://mangadex.org/")!) == nil)
        #expect(jars.header(partition: "unrelated", url: URL(string: "https://wnacg.com/")!) == nil)
    }

    @Test func withoutTargetsNothingIsWritten() {
        // A plan with cookies but no partitions must not fall back to a global jar.
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [BackupCookie(name: "sid", value: "a", domain: ".wnacg.com")], targets: nil)

        #expect(BackupImporter.restoreCookies(plan, jars: jars) == 0)
        #expect(jars.header(partition: CookiePartition.comic("copy_manga"), url: URL(string: "https://wnacg.com/")!) == nil)
    }

    @Test func anEmptyValueIsSkipped() {
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [
            BackupCookie(name: "empty", value: "", domain: "wnacg.com"),
            BackupCookie(name: "kept", value: "v", domain: "wnacg.com"),
        ], targets: ["copy_manga"])

        #expect(BackupImporter.restoreCookies(plan, jars: jars) == 1)
        let header = jars.header(partition: CookiePartition.comic("copy_manga"), url: URL(string: "https://wnacg.com/")!)
        #expect(header == "kept=v")
    }

    @Test func aDomainThatIsNotAHostIsSkipped() {
        // Real backups carry junk rows. Writing them would store a cookie that can
        // never match, which looks like a restore that half worked.
        for domain in ["https://wnacg.com", "wnacg", "", "a b.com"] {
            let jars = CookieJars(file: nil)
            let plan = plan(cookies: [BackupCookie(name: "sid", value: "v", domain: domain)],
                            targets: ["copy_manga"])
            #expect(BackupImporter.restoreCookies(plan, jars: jars) == 0, "domain \(domain)")
        }
    }

    @Test func anExpiredCookieIsNotRestored() {
        // A dead cookie is not a sign-in. Writing it would make the summary claim
        // something that no longer works, and leave a row the jar can never send.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let jars = CookieJars(file: nil, now: { now })
        let stale = Int64((now.timeIntervalSince1970 - 3600) * 1000)
        let live = Int64((now.timeIntervalSince1970 + 3600) * 1000)
        let plan = plan(cookies: [
            BackupCookie(name: "old", value: "v", domain: "wnacg.com", expires: stale),
            BackupCookie(name: "new", value: "v", domain: "wnacg.com", expires: live),
        ], targets: ["copy_manga"])

        #expect(BackupImporter.restoreCookies(plan, jars: jars) == 1)
        #expect(jars.header(partition: CookiePartition.comic("copy_manga"), url: URL(string: "https://wnacg.com/")!) == "new=v")
    }

    @Test func restoringTwiceKeepsOneRow() {
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [BackupCookie(name: "sid", value: "a", domain: ".wnacg.com")],
                        targets: ["copy_manga"])
        _ = BackupImporter.restoreCookies(plan, jars: jars)
        _ = BackupImporter.restoreCookies(plan, jars: jars)

        #expect(jars.header(partition: CookiePartition.comic("copy_manga"), url: URL(string: "https://wnacg.com/")!) == "sid=a")
    }

    @Test func cookiesLandInThePartitionRequestsUse() {
        // The plan names sources; every request names "comic:<key>". A restore that
        // wrote to the bare key would store cookies nothing ever sends, and its own
        // test would still pass if the test made the same assumption.
        let jars = CookieJars(file: nil)
        let plan = plan(cookies: [BackupCookie(name: "sid", value: "a", domain: ".wnacg.com")],
                        targets: ["copy_manga"])
        _ = BackupImporter.restoreCookies(plan, jars: jars)

        let page = URL(string: "https://wnacg.com/")!
        #expect(jars.header(partition: CookiePartition.comic("copy_manga"), url: page) == "sid=a")
        #expect(jars.header(partition: "copy_manga", url: page) == nil)
    }

    @Test func aClassicBackupWithNoCookieKeysStillDecodes() {
        // Old plans have neither key; the model must not fail to decode them.
        let json = #"{"history":[],"sources":[{"key":"a","script":"x"}]}"#
        let plan = try? JSONDecoder().decode(BackupPlan.self, from: Data(json.utf8))
        #expect(plan != nil)
        #expect(plan?.cookies == nil)
        #expect(plan?.cookieTargets == nil)
    }
}
