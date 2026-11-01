import Foundation
import Observation

/// A signed-in environment: its own sources, cookies, AI sign-ins, shelf and
/// downloads.
///
/// The reference app calls this an 环境 and puts it at the top of 我的. It is the
/// only shape that makes "two accounts" honest: switching has to take the
/// installed sources and their cookies with it, otherwise the second account
/// inherits the first one's sessions — the exact thing a second account exists to
/// avoid.
public struct Profile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var created: Date

    public init(id: String = UUID().uuidString, name: String, created: Date = Date()) {
        self.id = id
        self.name = name
        self.created = created
    }
}

/// The list of environments, and which one is open.
///
/// Everything an environment owns lives under `Profiles/<id>`: `sources.json`,
/// `cookies.json`, `shelf.json`, `searches.json`, `Magpie/`, `Downloads/`,
/// `Media/`. Themes are app-wide on purpose — a look is not an account.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile] = []
    public private(set) var activeID: String = ""

    private let support: URL
    private let defaults: UserDefaults
    private let manifest: URL

    /// Files that used to live directly under the support directory, before
    /// there were environments. They belong to the first one.
    /// `plugins.json` is the one that matters: `SourceStore` writes the records
    /// there, so a migration list without it moves everything *except* the
    /// sources — which looks exactly like "the upgrade deleted my sources".
    private static let legacyItems = ["plugins.json", "sources.json", "cookies.json", "shelf.json",
                                      "searches.json", "Magpie", "Downloads", "Media"]

    public init(support: URL, defaults: UserDefaults = .standard) {
        self.support = support
        self.defaults = defaults
        manifest = support.appending(path: "profiles.json")
        load()
        migrateLegacyIfNeeded()
        if profiles.isEmpty {
            let first = Profile(name: "默认环境")
            profiles = [first]
            activeID = first.id
            save()
        }
        if !profiles.contains(where: { $0.id == activeID }) {
            activeID = profiles[0].id
            save()
        }
    }

    public var active: Profile {
        profiles.first { $0.id == activeID } ?? profiles[0]
    }

    /// Where one environment keeps everything.
    public func directory(for id: String) -> URL {
        support.appending(path: "Profiles/\(id)", directoryHint: .isDirectory)
    }

    public var activeDirectory: URL { directory(for: activeID) }

    /// The Keychain service for an environment's AI sign-ins.
    ///
    /// The first environment keeps the original service name so an existing
    /// sign-in survives this change; the others get their own, because a token
    /// that two environments shared would sign one account into the other.
    public func keychainService(for id: String) -> String {
        let base = "com.laincat.nekularity.magpie"
        return id == profiles.first?.id ? base : base + "." + id
    }

    @discardableResult
    public func create(name: String) throws -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(name: trimmed.isEmpty ? "新环境" : trimmed)
        try FileManager.default.createDirectory(at: directory(for: profile.id), withIntermediateDirectories: true)
        profiles.append(profile)
        save()
        return profile
    }

    public func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        save()
    }

    /// Deletes an environment and everything it owned.
    ///
    /// The last one cannot be removed: an app with no environment has nowhere to
    /// put a source. Deleting the open one switches to another first, so the
    /// caller never holds a directory that is being removed.
    public func remove(_ id: String) throws {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if activeID == id {
            let survivor = profiles[index == 0 ? 1 : 0]
            activate(survivor.id)
        }
        try? FileManager.default.removeItem(at: directory(for: id))
        profiles.removeAll { $0.id == id }
        if !profiles.contains(where: { $0.id == activeID }) { activeID = profiles[0].id }
        save()
    }

    public func activate(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: manifest),
              let saved = try? JSONDecoder().decode([Profile].self, from: data) else { return }
        profiles = saved
        activeID = defaults.string(forKey: "activeProfile") ?? saved.first?.id ?? ""
    }

    private func save() {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: manifest, options: .atomic)
        }
        defaults.set(activeID, forKey: "activeProfile")
    }

    /// An install from before environments existed keeps its data: the files move
    /// into the first environment instead of being orphaned at the root, where
    /// nothing would read them again.
    private func migrateLegacyIfNeeded() {
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return }

        // A environment directory with no manifest means a migration was
        // interrupted between moving the files and recording that it had run.
        // Creating a *new* first environment there would leave the moved data in a
        // directory nothing points at, which is the same as deleting it.
        if let adopted = adoptedExistingDirectory() {
            profiles = [adopted]
            activeID = adopted.id
            save()
            moveLegacyItems(into: directory(for: adopted.id))
            return
        }

        let present = Self.legacyItems.filter {
            FileManager.default.fileExists(atPath: support.appending(path: $0).path)
        }
        guard !present.isEmpty else { return }
        let first = Profile(name: "默认环境")
        let root = directory(for: first.id)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Recorded before the files are moved, so an interruption leaves a manifest
        // that points at the directory instead of a directory nothing points at.
        profiles = [first]
        activeID = first.id
        save()
        moveLegacyItems(into: root)
    }

    /// A directory under `Profiles/` that already holds something, if any.
    private func adoptedExistingDirectory() -> Profile? {
        let parent = support.appending(path: "Profiles", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: parent,
                                                                        includingPropertiesForKeys: nil) else {
            return nil
        }
        let directories = entries.filter {(try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        // Newest first: if more than one survived an interruption, the most recent
        // is the one that was being migrated.
        let newest = directories.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left > right
        }.first
        guard let newest else { return nil }
        return Profile(id: newest.lastPathComponent, name: "默认环境")
    }

    /// Moves anything still at the support root into an environment.
    private func moveLegacyItems(into root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for item in Self.legacyItems where FileManager.default.fileExists(atPath: support.appending(path: item).path) {
            let destination = root.appending(path: item)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: support.appending(path: item), to: destination)
        }
    }
}
