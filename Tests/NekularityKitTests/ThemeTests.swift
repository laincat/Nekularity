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
}
