import Foundation
import Testing

@testable import NekularityKit

@Suite("Tag glossary")
@MainActor
struct TagGlossaryTests {
    private func store() throws -> TagGlossaryStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "gloss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return TagGlossaryStore(directory: root)
    }

    @Test("a known tag is translated and an unknown one is left alone")
    func translates() throws {
        let store = try store()
        #expect(store.translation(of: "big breasts") == "巨乳")
        #expect(store.translation(of: "something nobody has named") == nil)
        // A tag with no entry keeps its own spelling; inventing one would be an
        // assertion about the content.
        #expect(store.label(for: "something nobody has named").text == "something nobody has named")
        let known = store.label(for: "big breasts")
        #expect(known.translated)
        #expect(known.text == "巨乳")
    }

    @Test("case, spacing and underscores do not need their own entries")
    func normalises() throws {
        let store = try store()
        #expect(store.translation(of: "  Big   Breasts ") == "巨乳")
        #expect(store.translation(of: "FULL_COLOR") == "全彩")
        #expect(TagGlossary.normalise("Sole  Female") == "sole female")
    }

    @Test("the user's correction wins and survives a relaunch")
    func overrides() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gloss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TagGlossaryStore(directory: root)
        store.setTranslation("大胸", for: "Big Breasts")
        #expect(store.translation(of: "big breasts") == "大胸")
        #expect(store.isOverridden("BIG BREASTS"))

        let again = TagGlossaryStore(directory: root)
        #expect(again.translation(of: "big breasts") == "大胸")

        // Clearing the correction goes back to the built-in table, not to nothing.
        again.setTranslation("   ", for: "big breasts")
        #expect(again.translation(of: "big breasts") == "巨乳")
        #expect(!again.isOverridden("big breasts"))
    }

    @Test("an empty tag has no translation")
    func empty() throws {
        let store = try store()
        #expect(store.translation(of: "   ") == nil)
        #expect(store.translation(of: "") == nil)
    }
}
