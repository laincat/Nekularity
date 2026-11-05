import Foundation
import Testing
@testable import NekularityKit

/// A theme's three-way answer about light and dark. The model stores it as an
/// optional so an absent key means "follow the system", and that resolution now
/// lives in one tested place instead of a ternary in the view.
@Suite("Theme appearance")
struct ThemeAppearanceTests {
    /// Built as a dictionary rather than JSON text: the repository's syntax
    /// checker counts braces per line, so a fragment ending in a closing brace
    /// would unbalance it.
    private func theme(dark: Bool?) throws -> Theme {
        var raw: [String: Any] = ["id": "t", "name": "t", "accent": "#8E7BFF", "radius": 12]
        if let dark {
            raw["dark"] = dark
        }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(Theme.self, from: data)
    }

    @Test("an absent dark key follows the system")
    func absentFollowsSystem() throws {
        let decoded = try theme(dark: nil)
        #expect(decoded.appearance == .system)
        #expect(decoded.dark == nil)
    }

    @Test("the two explicit answers keep their meaning")
    func explicitAnswers() throws {
        #expect(try theme(dark: true).appearance == .dark)
        #expect(try theme(dark: false).appearance == .light)
    }

    @Test("the built-in theme does not force an appearance")
    func builtinFollowsSystem() {
        #expect(BuiltinThemes.system.appearance == .system)
    }

    /// A store over a throwaway defaults domain and theme directory, so one test
    /// cannot see another's choice.
    @MainActor
    private func store(_ name: String) -> (ThemeStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "themes-\(name)-\(UUID().uuidString)")
        return (ThemeStore(directory: directory, defaults: defaults), defaults)
    }

    @Test("with no choice the theme decides")
    @MainActor
    func themeDecides() {
        let (themes, _) = store("theme-appearance-1")
        #expect(themes.appearance == .system)
        #expect(themes.appearanceOverride == nil)
    }

    @Test("an explicit choice wins over the theme and survives a new store")
    @MainActor
    func explicitChoicePersists() {
        let name = "theme-appearance-2"
        let (themes, defaults) = store(name)
        themes.select(appearance: .dark)
        #expect(themes.appearance == .dark)
        // A second store over the same defaults is what a relaunch sees.
        let again = ThemeStore(directory: FileManager.default.temporaryDirectory
                                .appending(path: "themes-again-\(UUID().uuidString)"),
                               defaults: defaults)
        #expect(again.appearanceOverride == .dark)
        #expect(again.appearance == .dark)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("picking the system is a choice, not the absence of one")
    @MainActor
    func systemIsAChoice() {
        let name = "theme-appearance-3"
        let (themes, defaults) = store(name)
        themes.select(appearance: .dark)
        themes.select(appearance: .system)
        #expect(themes.appearanceOverride == .system)
        #expect(themes.appearance == .system)
        #expect(defaults.string(forKey: "appearance") == "system")
        defaults.removePersistentDomain(forName: name)
    }

    @Test("every case has a name for the picker")
    func labelsAreUnique() {
        let labels = ThemeAppearance.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(!labels.contains(""))
    }
}
