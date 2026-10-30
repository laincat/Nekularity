import Foundation
import Testing
@testable import NekularityKit

@Suite struct CookieJarsTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func jar() -> CookieJars { let t = t0; return CookieJars(file: nil, now: { t }) }
    let page = URL(string: "https://www.u.test/a/b")!

    @Test func partitionsAreSeparate() {
        let j = jar()
        j.save(partition: "comic:a", url: page, cookies: [WireCookie(name: "sid", value: "1")])
        #expect(j.header(partition: "comic:a", url: page) == "sid=1")
        #expect(j.header(partition: "comic:b", url: page) == nil)
    }

    @Test func hostOnlyAndDomainCookies() {
        let j = jar()
        j.save(partition: "p", url: page, cookies: [
            WireCookie(name: "host", value: "1"),
            WireCookie(name: "dom", value: "2", domain: ".u.test", path: "/"),
        ])
        #expect(j.header(partition: "p", url: URL(string: "https://img.u.test/x")!) == "dom=2")
        #expect(Set(j.cookies(partition: "p", url: page).map(\.name)) == ["host", "dom"])
        // A page may not set cookies for an unrelated or public domain.
        j.save(partition: "p", url: page, cookies: [WireCookie(name: "evil", value: "1", domain: ".other.test")])
        #expect(!j.cookies(partition: "p", url: URL(string: "https://other.test/")!).contains { $0.name == "evil" })
    }

    @Test func pathAndSecure() {
        let j = jar()
        j.save(partition: "p", url: page, cookies: [
            WireCookie(name: "deep", value: "1", path: "/a"),
            WireCookie(name: "sec", value: "1", path: "/", secure: true),
        ])
        #expect(j.header(partition: "p", url: URL(string: "https://www.u.test/a/c")!)?.contains("deep=1") == true)
        #expect(j.header(partition: "p", url: URL(string: "https://www.u.test/ab")!)?.contains("deep") == false)
        #expect(j.header(partition: "p", url: URL(string: "http://www.u.test/")!) == nil)
    }

    @Test func defaultPathIsTheDirectory() {
        let j = jar()
        j.save(partition: "p", url: page, cookies: [WireCookie(name: "d", value: "1")])
        #expect(j.cookies(partition: "p", url: page).first?.path == "/a")
    }

    @Test func expiryAndDelete() {
        let j = jar()
        let ms = Int64(t0.timeIntervalSince1970 * 1000)
        j.save(partition: "p", url: page, cookies: [
            WireCookie(name: "old", value: "1", path: "/", expires: ms - 1),
            WireCookie(name: "new", value: "1", path: "/", expires: ms + 60_000),
            WireCookie(name: "age", value: "1", path: "/", maxAge: 10),
        ])
        #expect(Set(j.cookies(partition: "p", url: page).map(\.name)) == ["new", "age"])
        j.delete(partition: "p", url: page)
        #expect(j.cookies(partition: "p", url: page).isEmpty)
    }

    @Test func parsesSetCookie() throws {
        let c = try #require(CookieJars.parseSetCookie("a=b=c; Domain=u.test; Path=/x; Max-Age=60; Secure; HttpOnly", now: t0))
        #expect(c.name == "a" && c.value == "b=c")
        #expect(c.domain == ".u.test" && c.path == "/x" && c.maxAge == 60)
        #expect(c.secure == true && c.httpOnly == true)
        let gone = try #require(CookieJars.parseSetCookie("a=; Max-Age=0", now: t0))
        #expect(gone.expires == 1)
        #expect(CookieJars.parseSetCookie("novalue", now: t0) == nil)
    }

    @Test func persistsOnlyPersistentCookies() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cookies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let t = t0
        let j = CookieJars(file: file, now: { t })
        j.save(partition: "p", url: page, cookies: [
            WireCookie(name: "session", value: "1", path: "/"),
            WireCookie(name: "keep", value: "1", path: "/", maxAge: 3600),
        ])
        let reloaded = CookieJars(file: file, now: { t })
        #expect(reloaded.cookies(partition: "p", url: page).map(\.name) == ["keep"])
    }
}
