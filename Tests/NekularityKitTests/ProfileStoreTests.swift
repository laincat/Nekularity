import Foundation
import Testing

@testable import NekularityKit

@Suite("ProfileStore")
@MainActor
struct ProfileStoreTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "profile-test-\(UUID().uuidString)")!
    }

    @Test("a fresh install gets one environment, and it is the open one")
    func firstLaunch() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(support: root, defaults: defaults())
        #expect(store.profiles.count == 1)
        #expect(store.active.name == "默认环境")
        #expect(store.activeID == store.profiles[0].id)
    }

    @Test("each environment has its own directory, and the first keeps the original Keychain service")
    func separation() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(support: root, defaults: defaults())
        let first = store.profiles[0]
        let second = try store.create(name: "小号")

        #expect(store.directory(for: first.id) != store.directory(for: second.id))
        // The first environment must keep the name an existing sign-in is stored
        // under, or upgrading would silently sign the user out.
        #expect(store.keychainService(for: first.id) == "com.laincat.nekularity.magpie")
        #expect(store.keychainService(for: second.id) != store.keychainService(for: first.id))
    }

    @Test("switching, renaming and reopening survive a relaunch")
    func persistence() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults()
        let store = ProfileStore(support: root, defaults: defaults)
        let second = try store.create(name: "小号")
        store.rename(second.id, to: "工作")
        store.activate(second.id)

        let again = ProfileStore(support: root, defaults: defaults)
        #expect(again.activeID == second.id)
        #expect(again.active.name == "工作")
        #expect(again.profiles.count == 2)
    }

    @Test("deleting the open environment switches away first, and the last one cannot be deleted")
    func removal() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(support: root, defaults: defaults())
        let first = store.profiles[0]
        let second = try store.create(name: "小号")
        store.activate(second.id)
        let secondDir = store.directory(for: second.id)
        try Data("x".utf8).write(to: secondDir.appending(path: "cookies.json"))

        try store.remove(second.id)
        #expect(store.profiles.count == 1)
        #expect(store.activeID == first.id)
        #expect(!FileManager.default.fileExists(atPath: secondDir.path), "deleting an environment must delete its files")

        // The survivor stays.
        try store.remove(first.id)
        #expect(store.profiles.count == 1)
    }

    @Test("an install from before environments keeps its data in the first one")
    func migratesLegacyFiles() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        // What the old layout left behind.
        try Data("{}".utf8).write(to: root.appending(path: "sources.json"))
        try Data("{}".utf8).write(to: root.appending(path: "cookies.json"))

        let store = ProfileStore(support: root, defaults: defaults())
        let dir = store.activeDirectory
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "sources.json").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "cookies.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "sources.json").path),
                "a migrated file must not stay at the root where nothing reads it")
    }
}
