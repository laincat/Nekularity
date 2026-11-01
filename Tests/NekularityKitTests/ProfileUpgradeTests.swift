import Foundation
import Testing

@testable import NekularityKit

/// The upgrade path end to end: a directory that looks like an install from before
/// environments existed, opened by this version.
///
/// These are the tests for the failure a user cannot undo — the shelf and sources
/// they had before the update. Everything else in this app can be rebuilt from the
/// network; that cannot.
@Suite("Upgrading an install from before environments")
@MainActor
struct ProfileUpgradeTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "upgrade-\(UUID().uuidString)")!
    }

    /// What an older install left at the support root.
    private func writeOldInstall(_ dir: URL) throws {
        try Data("{\"records\":[]}".utf8).write(to: dir.appending(path: "plugins.json"))
        try Data("{\"cookies\":[]}".utf8).write(to: dir.appending(path: "cookies.json"))
        try Data("{\"history\":[]}".utf8).write(to: dir.appending(path: "shelf.json"))
        try Data("{\"queries\":[]}".utf8).write(to: dir.appending(path: "searches.json"))
        for folder in ["Magpie", "Downloads", "Media"] {
            try FileManager.default.createDirectory(at: dir.appending(path: folder), withIntermediateDirectories: true)
            try Data("keep me".utf8).write(to: dir.appending(path: folder).appending(path: "marker"))
        }
    }

    @Test("everything an old install owned ends up in the first environment")
    func movesEverything() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeOldInstall(dir)

        let store = ProfileStore(support: dir, defaults: defaults())
        let active = store.activeDirectory
        for item in ["plugins.json", "cookies.json", "shelf.json", "searches.json"] {
            #expect(FileManager.default.fileExists(atPath: active.appending(path: item).path),
                    "\(item) did not move into the environment")
            #expect(!FileManager.default.fileExists(atPath: dir.appending(path: item).path),
                    "\(item) was copied rather than moved")
        }
        for folder in ["Magpie", "Downloads", "Media"] {
            #expect(FileManager.default.fileExists(atPath: active.appending(path: folder)
                .appending(path: "marker").path))
        }
        // Themes are app-wide and must stay where they were.
        #expect(!FileManager.default.fileExists(atPath: active.appending(path: "Themes").path))
    }

    @Test("reopening does not migrate twice, and a second environment starts empty")
    func doesNotSteal() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeOldInstall(dir)
        let defaults = defaults()
        let first = ProfileStore(support: dir, defaults: defaults)
        let firstDirectory = first.activeDirectory

        // Something written after the upgrade, in the first environment.
        try Data("{\"history\":[1]}".utf8).write(to: firstDirectory.appending(path: "shelf.json"))

        let second = ProfileStore(support: dir, defaults: defaults)
        #expect(second.profiles.count == 1)
        #expect(second.activeDirectory == firstDirectory)
        let shelf = try String(contentsOf: second.activeDirectory.appending(path: "shelf.json"), encoding: .utf8)
        #expect(shelf.contains("history"))
        #expect(shelf.contains("[1]") == false)

        let extra = try second.create(name: "小号")
        #expect(!FileManager.default.fileExists(atPath: second.directory(for: extra.id)
            .appending(path: "shelf.json").path))
    }

    @Test("an interrupted migration is adopted, not orphaned")
    func adoptsAnInterruptedMigration() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The state a crash between "move the files" and "write the manifest" leaves:
        // a directory full of data, and no profile pointing at it.
        let orphanID = UUID().uuidString
        let orphan = dir.appending(path: "Profiles/\(orphanID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("{\"history\":[42]}".utf8).write(to: orphan.appending(path: "shelf.json"))
        // And a file that had not been moved yet.
        try Data("{\"cookies\":[]}".utf8).write(to: dir.appending(path: "cookies.json"))

        let store = ProfileStore(support: dir, defaults: defaults())
        #expect(store.activeID == orphanID, "a directory holding data must be adopted, not replaced")
        #expect(FileManager.default.fileExists(atPath: orphan.appending(path: "cookies.json").path),
                "the file that had not moved yet still belongs to it")
        let shelf = try String(contentsOf: orphan.appending(path: "shelf.json"), encoding: .utf8)
        #expect(shelf.contains("42"))
    }
}
