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

    @Test func unchangedAndEmptyWritesDoNotRewriteDisk() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cookies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let t = t0
        let j = CookieJars(file: file, now: { t })

        // Empty save, invalid-domain cookie, and session-only cookie do not touch disk.
        j.save(partition: "p", url: page, cookies: [])
        j.store(partition: "p", url: page, setCookieHeaders: [])
        j.save(partition: "p", url: page, cookies: [WireCookie(name: "evil", value: "1", domain: ".other.test", maxAge: 60)])
        j.save(partition: "p", url: page, cookies: [WireCookie(name: "session", value: "1", path: "/")])
        #expect(j.diskWriteCount == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // First persistent cookie writes once; identical re-save skips disk write.
        let persistent = WireCookie(name: "keep", value: "v1", path: "/", maxAge: 3600)
        j.save(partition: "p", url: page, cookies: [persistent])
        #expect(j.diskWriteCount == 1)
        j.save(partition: "p", url: page, cookies: [persistent])
        #expect(j.diskWriteCount == 1)

        // Updating value persists; expiring deletes and persists across reopen.
        j.save(partition: "p", url: page, cookies: [WireCookie(name: "keep", value: "v2", path: "/", maxAge: 3600)])
        #expect(j.diskWriteCount == 2)
        #expect(CookieJars(file: file, now: { t }).cookies(partition: "p", url: page).first?.value == "v2")

        j.save(partition: "p", url: page, cookies: [WireCookie(name: "keep", value: "", path: "/", expires: 1)])
        #expect(j.diskWriteCount == 3)
        #expect(CookieJars(file: file, now: { t }).cookies(partition: "p", url: page).isEmpty)
    }

    @Test func responseWithoutSetCookieSkipsDiskAndMultiCookieWithExpiryPersists() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cookies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let t = t0
        let j = CookieJars(file: file, now: { t })
        j.save(partition: "comic:other", url: page, cookies: [WireCookie(name: "untouched", value: "ok", path: "/", maxAge: 3600)])
        let writesAfterSeed = j.diskWriteCount

        let plain = try #require(HTTPURLResponse(url: page, statusCode: 200, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": "text/plain"]))
        #expect(URLSessionTransport.responseCookies(plain).isEmpty)
        j.save(partition: "comic:target", url: page, cookies: URLSessionTransport.responseCookies(plain))
        #expect(j.diskWriteCount == writesAfterSeed)

        let setResp = try #require(HTTPURLResponse(
            url: page, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "a=1; Path=/; Expires=Wed, 01 Jan 2031 00:00:00 GMT, b=2; Domain=.u.test; Path=/; Expires=Wed, 01 Jan 2031 00:00:00 GMT"]))
        j.save(partition: "comic:target", url: page, cookies: URLSessionTransport.responseCookies(setResp))
        #expect(j.diskWriteCount == writesAfterSeed + 1)

        let reopened = CookieJars(file: file, now: { t })
        #expect(Set(reopened.cookies(partition: "comic:target", url: page).map(\.name)) == ["a", "b"])
        #expect(reopened.cookies(partition: "comic:other", url: page).map(\.value) == ["ok"])

        // Expiring one cookie via Set-Cookie removes only that cookie and keeps other partitions intact.
        let expireResp = try #require(HTTPURLResponse(
            url: page, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "a=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"]))
        j.save(partition: "comic:target", url: page, cookies: URLSessionTransport.responseCookies(expireResp))
        let afterExpire = CookieJars(file: file, now: { t })
        #expect(afterExpire.cookies(partition: "comic:target", url: page).map(\.name) == ["b"])
        #expect(afterExpire.cookies(partition: "comic:other", url: page).map(\.value) == ["ok"])
    }

    @Test func webviewImportPersistsAndSkipsIdenticalReimport() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cookies-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let t = t0
        let j = CookieJars(file: file, now: { t })
        let future = t0.addingTimeInterval(3600)
        let cookie = try #require(HTTPCookie(properties: [
            .name: "cf_clearance", .value: "xyz", .domain: ".u.test", .path: "/",
            .expires: future, .secure: true,
        ]))
        j.importCookies(partition: "comic:a", [cookie])
        #expect(j.diskWriteCount == 1)
        j.importCookies(partition: "comic:a", [cookie])
        #expect(j.diskWriteCount == 1)
        #expect(CookieJars(file: file, now: { t }).cookies(partition: "comic:a", url: page).map(\.value) == ["xyz"])
        #expect(CookieJars(file: file, now: { t }).cookies(partition: "comic:b", url: page).isEmpty)
    }
}
