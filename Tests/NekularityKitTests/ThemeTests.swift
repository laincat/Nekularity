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
}
