import Foundation
import Testing

@testable import NekularityKit

@Suite("Theme")
@MainActor
struct ThemeTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "theme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a theme file installs, is remembered, and can be removed")
    func installSelectRemove() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!
        let store = ThemeStore(directory: dir, defaults: defaults)

        let json = Data(##"{"id":"mine","name":"我的主题","accent":"#FF6B6B","radius":16}"##.utf8)
        try store.install(data: json)
        #expect(store.all.contains { $0.id == "mine" })
        #expect(store.active.id == "system", "installing must not change the choice")

        let mine = store.all.first { $0.id == "mine" }!
        store.select(mine)
        #expect(store.active.id == "mine")
        #expect(defaults.string(forKey: "theme") == "mine")

        // A new store over the same directory and defaults remembers both.
        let again = ThemeStore(directory: dir, defaults: defaults)
        #expect(again.active.id == "mine")
        #expect(again.all.contains { $0.id == "mine" })

        again.remove(mine)
        #expect(!again.all.contains { $0.id == "mine" })
        #expect(again.active.id == "system")
    }

    @Test("the id in a file cannot write outside the theme directory")
    func idsAreSanitised() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThemeStore(directory: dir, defaults: UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!)
        let json = Data(##"{"id":"../escape","name":"trap","accent":"#000000","radius":8}"##.utf8)
        try store.install(data: json)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 1)
        #expect(!files[0].contains("/"))
        #expect(store.all.contains { $0.name == "trap" })
    }

    @Test("a file without an id or a name is refused")
    func incompleteThemeIsRefused() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThemeStore(directory: dir, defaults: UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!)
        #expect(throws: CoreError.self) {
            try store.install(data: Data(##"{"id":"","name":"x","accent":"#000000","radius":8}"##.utf8))
        }
    }

    // A theme's accent is a hex string from a file, so white text is only right
    // when the accent is dark enough for white. The shipped accents are; flipping
    // them to black because black scores higher would restyle the whole app to fix
    // a case that is not broken. A pale one cannot carry white and needs dark text.
    @Test("text on an accent follows its lightness")
    func accentTextFollowsTheAccent() {
        #expect(!Theme(id: "a", name: "a", accent: "#0A84FF").accentTextIsDark)
        #expect(!Theme(id: "b", name: "b", accent: "#3482FF").accentTextIsDark)
        // 2.51:1 with white — the dark theme's pastel accent needs dark text.
        #expect(Theme(id: "b2", name: "b2", accent: "#6BA4FF").accentTextIsDark)
        #expect(Theme(id: "c", name: "c", accent: "#FFF59D").accentTextIsDark)
        #expect(Theme(id: "d", name: "d", accent: "#FFFFFF").accentTextIsDark)
        #expect(Theme(id: "e", name: "e", accent: "FFFF00").accentTextIsDark)
        #expect(!Theme(id: "f", name: "f", accent: "#000000").accentTextIsDark)
    }

    /// The decision above is "dark text when white is unreadable", which is a rule
    /// about a number. This checks the number for the accents that ship, so the
    /// claim stops resting on one hand-written comment about 3.44:1.
    @Test func everyShippedAccentKeepsItsTextAboveTheFloor() throws {
        for accent in ["#3482FF", "#6BA4FF", "#0A84FF"] {
            let rgb = try #require(Theme.components(of: accent))
            let theme = Theme(id: accent, name: accent, accent: accent)
            let text = theme.accentTextIsDark ? 0.0 : 1.0
            let ratio = Theme.contrast(Theme.luminance(rgb), text)
            #expect(ratio >= 3, "\(accent) scores \(ratio):1, below the 3:1 floor")
        }
    }

    @Test("an unreadable accent falls back to white text")
    func anUnreadableAccentFallsBack() {
        #expect(!Theme(id: "g", name: "g", accent: "not a colour").accentTextIsDark)
        #expect(!Theme(id: "h", name: "h", accent: "#12345").accentTextIsDark)
    }

    /// A stored choice that no longer exists falls back rather than leaving the app
    /// with no theme: the built-in Miuix pair was removed, and anyone who had picked
    /// it kept its id in defaults.
    @Test("a choice that is gone falls back to the system look")
    func removedChoiceFallsBack() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!
        defaults.set("miuix", forKey: "theme")
        let store = ThemeStore(directory: dir, defaults: defaults)
        #expect(store.active.id == BuiltinThemes.system.id)
        #expect(store.all.map(\.id) == [BuiltinThemes.system.id])
    }

    /// A theme from a link is the same file as one from a picker, so it goes through
    /// the same door: the id is sanitised, and a bad body is refused before anything
    /// is written. The link itself must be HTTPS — the check lives in the store so a
    /// caller other than the settings screen cannot skip it.
    @Test("a theme installs over HTTPS and a bad body is refused")
    func themeFromLink() async throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThemeStore(directory: dir, defaults: UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!)
        let url = URL(string: "https://themes.test/night.json")!

        let body = Data(##"{"id":"night","name":"夜","accent":"#8E7BFF","radius":14,"dark":true}"##.utf8)
        try await store.install(from: url) { asked in
            #expect(asked == url)
            return body
        }
        #expect(store.all.contains { $0.id == "night" })
        #expect(store.active.id == BuiltinThemes.system.id)

        var refused = false
        do {
            try await store.install(from: url) { _ in Data("not json".utf8) }
        } catch {
            refused = true
        }
        #expect(refused, "a body that is not a theme was accepted")
        #expect(store.all.contains { $0.id == "night" }, "the failing install removed the good theme")
    }

    @Test("plaintext and malformed theme links are refused before fetching")
    func plaintextThemeLinksAreRefused() async throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThemeStore(directory: dir, defaults: UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!)
        for text in ["http://themes.test/night.json", "HTTP://themes.test/night.json",
                     "file:///tmp/night.json", "https:///no-host.json", "themes.test/night.json"] {
            let url = try #require(URL(string: text))
            do {
                try await store.install(from: url) { requested in
                    Issue.record("\(requested) reached the network before the scheme check")
                    return Data(##"{"id":"plain","name":"plain","accent":"#000000","radius":8}"##.utf8)
                }
                Issue.record("\(text) was accepted")
            } catch {
                #expect(error is CoreError)
            }
        }
        #expect(store.all.allSatisfy { $0.id == BuiltinThemes.system.id }, "a refused link installed a theme")
    }

    @Test("a redirect away from HTTPS is refused without waiting for the timeout")
    func redirectToPlaintextIsRefused() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThemeLinkStub.self]
        let started = Date()
        do {
            _ = try await ThemeSource.fetch(URL(string: "https://redirect.test/hop.json")!,
                                            configuration: config)
            Issue.record("the plaintext redirect was followed")
        } catch {
            #expect((error as? CoreError)?.message.contains("非 https") == true,
                    "the refusal did not name the scheme: \(error)")
        }
        // The first version refused the hop but left the task waiting for the
        // 20-second request timeout, which reads as a slow server.
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 5, "the refusal took \(elapsed)s, so the user waits for the timeout")
        let plaintext = ThemeLinkStub.requests().filter { $0.host == "plain.test" }
        #expect(plaintext.isEmpty, "the request went to \(plaintext) after the https hop")
    }

    @Test("a redirect that stays on HTTPS is followed")
    func redirectWithinHTTPSIsFollowed() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThemeLinkStub.self]
        let data = try await ThemeSource.fetch(URL(string: "https://keep.test/hop.json")!,
                                              configuration: config)
        #expect(String(decoding: data, as: UTF8.self).contains("\"id\":\"kept\""),
                "the https hop did not deliver the theme")
    }

    @Test("a non-2xx response and an oversized body are refused")
    func badResponsesAreRefused() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThemeLinkStub.self]
        do {
            _ = try await ThemeSource.fetch(URL(string: "https://missing.test/theme.json")!,
                                            configuration: config)
            Issue.record("a 404 body was accepted as a theme")
        } catch {
            #expect(error is CoreError)
        }
        do {
            _ = try await ThemeSource.fetch(URL(string: "https://huge.test/theme.json")!,
                                            configuration: config)
            Issue.record("an oversized body was accepted as a theme")
        } catch {
            #expect(error is CoreError)
        }
    }

    @Test("only an HTTPS host may be a redirect target")
    func redirectTargets() throws {
        #expect(ThemeSource.allowsRedirect(to: URL(string: "https://themes.test/a.json")))
        #expect(!ThemeSource.allowsRedirect(to: URL(string: "http://themes.test/a.json")))
        #expect(!ThemeSource.allowsRedirect(to: URL(string: "HTTP://themes.test/a.json")))
        #expect(!ThemeSource.allowsRedirect(to: URL(string: "file:///tmp/a.json")))
        #expect(!ThemeSource.allowsRedirect(to: URL(string: "https:///a.json")))
        #expect(!ThemeSource.allowsRedirect(to: nil))
    }
}

/// Answers theme fetches from a table: a plaintext hop, an HTTPS hop, a 404 and
/// a body larger than `ThemeSource.maximumBytes`. Requests are recorded so the
/// refusal can be shown to stop before the plaintext host is reached.
final class ThemeLinkStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [URL] = []

    static func requests() -> [URL] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { Self.seen.append(url) }
        if url.path.contains("plain") {
            // Only reached if the plaintext hop was actually followed.
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch url.host {
        case "redirect.test":
            let target = URL(string: "http://plain.test/plain.json")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        case "keep.test":
            let target = URL(string: "https://keep.test/final.json")!
            if url.path == "/hop.json" {
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                              headerFields: ["Location": target.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
                return
            }
            deliver(url, status: 200, body: Data("{\"id\":\"kept\"}".utf8))
        case "missing.test":
            deliver(url, status: 404, body: Data("not a theme".utf8))
        default:
            let big = Data(repeating: 0x20, count: ThemeSource.maximumBytes + 1)
            deliver(url, status: 200, body: big)
        }
    }

    private func deliver(_ url: URL, status: Int, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
