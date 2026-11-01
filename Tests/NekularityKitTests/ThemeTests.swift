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
    // when the accent is dark. Every shipped accent is; a pale one is not, and
    // white on it is invisible.
    @Test("text on an accent follows its lightness")
    func accentTextFollowsTheAccent() {
        #expect(!Theme(id: "a", name: "a", accent: "#0A84FF").accentTextIsDark)
        #expect(!Theme(id: "b", name: "b", accent: "#3482FF").accentTextIsDark)
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
}
