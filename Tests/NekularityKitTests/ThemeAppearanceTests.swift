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
}
