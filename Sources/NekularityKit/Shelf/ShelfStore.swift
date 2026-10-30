import Foundation
import Observation

/// One comic as the shelf remembers it.
public struct ShelfComic: Codable, Hashable, Identifiable, Sendable {
    public var source: String
    public var id: String
    public var title: String
    public var author: String?
    public var cover: String?

    public init(source: String, id: String, title: String, author: String? = nil, cover: String? = nil) {
        self.source = source
        self.id = id
        self.title = title
        self.author = author
        self.cover = cover
    }

    /// The identity the shelf uses: a comic is one comic per source.
    public var key: String { source + "/" + id }
}

/// Where reading stopped in one comic.
public struct ShelfHistory: Codable, Hashable, Sendable {
    public var source: String
    public var id: String
    public var title: String
    public var author: String?
    public var cover: String?
    /// The chapter's title as the source gave it.
    public var chapter: String?
    /// Its index in the chapter list when it was read.
    public var chapterIndex: Int
    /// The page last seen, nil when unknown.
    public var page: Int?
    /// How far into the chapter reading stopped, 0–100.
    public var percent: Int?
    /// When the chapter was last opened, in seconds.
    public var time: Int

    public init(
        comic: ShelfComic,
        chapter: String? = nil,
        chapterIndex: Int = 0,
        page: Int? = nil,
        percent: Int? = nil,
        time: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.source = comic.source
        self.id = comic.id
        self.title = comic.title
        self.author = comic.author
        self.cover = comic.cover
        self.chapter = chapter
        self.chapterIndex = chapterIndex
        self.page = page
        self.percent = percent
        self.time = time
    }

    public var comic: ShelfComic {
        ShelfComic(source: source, id: id, title: title, author: author, cover: cover)
    }
}

/// A named list of comics.
public struct ShelfFolder: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var items: [ShelfComic]

    public init(name: String, items: [ShelfComic] = []) {
        self.name = name
        self.items = items
    }

    public var id: String { name }
}

/// Reading history and favourites, kept in one JSON file per profile.
///
/// The shapes match the desktop client's `shelf.json`, so a profile can be
/// read by either. The file is small — history is capped and folders hold a
/// few hundred comics — so it is written whole on the main actor rather than
/// off it: a reader that loses a position because a write was still in
/// flight is worse than a millisecond of writing.
@MainActor
@Observable
public final class ShelfStore {
    /// Where a comic goes when the reader keeps it without choosing.
    public static let defaultFolder = "收藏"
    /// How many reading positions are remembered.
    public static let historyLimit = 500

    public private(set) var history: [ShelfHistory] = []
    public private(set) var folders: [ShelfFolder] = []
    public private(set) var lastError: String?

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opens the shelf in a directory, creating the file on first write.
    public init(directory: URL) {
        self.url = directory.appendingPathComponent("shelf.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    /// A shelf that keeps its data in memory, for previews and tests.
    public init() {
        self.url = URL(fileURLWithPath: "/dev/null")
        self.inMemory = true
    }

    private var inMemory = false

    // MARK: Reading

    /// The most recent positions, newest first.
    public func recentHistory(limit: Int = 40) -> [ShelfHistory] {
        Array(history.prefix(max(0, limit)))
    }

    /// The reading position for one comic, if the shelf knows it.
    public func entry(source: String, id: String) -> ShelfHistory? {
        history.first { $0.source == source && $0.id == id }
    }

    /// The folder holding a comic, if any.
    public func folderHolding(source: String, id: String) -> String? {
        for folder in folders where folder.items.contains(where: { $0.source == source && $0.id == id }) {
            return folder.name
        }
        return nil
    }

    public func folder(named name: String) -> ShelfFolder? {
        folders.first { $0.name == name }
    }

    /// Folder names, with the default one always offered.
    public func folderNames() -> [String] {
        var names = [Self.defaultFolder]
        for folder in folders where !names.contains(folder.name) {
            names.append(folder.name)
        }
        return names
    }

    public var counts: (history: Int, favourites: Int) {
        (history.count, folders.reduce(0) { $0 + $1.items.count })
    }

    // MARK: Writing

    /// Records a position, moving the comic to the front; one comic appears
    /// once, at its latest chapter.
    public func record(_ entry: ShelfHistory) {
        guard !entry.source.isEmpty, !entry.id.isEmpty else {
            lastError = "a reading position needs a source and an id"
            return
        }
        history.removeAll { $0.source == entry.source && $0.id == entry.id }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        save()
    }

    /// Writes how far the reader got, keeping the entry's place in the list:
    /// scrolling is not reading a new chapter. A comic the shelf does not
    /// know is not added.
    @discardableResult
    public func updateProgress(
        source: String,
        id: String,
        chapter: String? = nil,
        chapterIndex: Int? = nil,
        page: Int? = nil,
        percent: Int? = nil
    ) -> Bool {
        guard let index = history.firstIndex(where: { $0.source == source && $0.id == id }) else {
            return false
        }
        if let chapter { history[index].chapter = chapter }
        if let chapterIndex { history[index].chapterIndex = chapterIndex }
        if let page { history[index].page = max(0, page) }
        if let percent { history[index].percent = min(100, max(0, percent)) }
        history[index].time = Int(Date().timeIntervalSince1970)
        save()
        return true
    }

    /// Merges a position from an import without losing a newer local one.
    @discardableResult
    public func merge(_ entry: ShelfHistory) -> Bool {
        if let existing = history.first(where: { $0.source == entry.source && $0.id == entry.id }),
           existing.time >= entry.time {
            return false
        }
        record(entry)
        return true
    }

    public func forgetHistory(source: String, id: String) {
        history.removeAll { $0.source == source && $0.id == id }
        save()
    }

    /// Keeps a comic in a folder, creating the folder. Returns whether it was
    /// new there.
    @discardableResult
    public func add(_ comic: ShelfComic, to folderName: String = ShelfStore.defaultFolder) -> Bool {
        let name = folderName.isEmpty ? Self.defaultFolder : folderName
        if let index = folders.firstIndex(where: { $0.name == name }) {
            if folders[index].items.contains(where: { $0.key == comic.key }) { return false }
            folders[index].items.append(comic)
        } else {
            folders.append(ShelfFolder(name: name, items: [comic]))
        }
        save()
        return true
    }

    public func remove(_ comic: ShelfComic, from folderName: String? = nil) {
        let name = folderName ?? folderHolding(source: comic.source, id: comic.id) ?? Self.defaultFolder
        guard let index = folders.firstIndex(where: { $0.name == name }) else { return }
        folders[index].items.removeAll { $0.key == comic.key }
        save()
    }

    /// Moves a comic between folders, reporting whether anything changed.
    @discardableResult
    public func move(_ comic: ShelfComic, to folderName: String) -> Bool {
        let name = folderName.isEmpty ? Self.defaultFolder : folderName
        if folderHolding(source: comic.source, id: comic.id) == name { return false }
        remove(comic)
        return add(comic, to: name)
    }

    public func createFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !folders.contains(where: { $0.name == trimmed }) else { return }
        folders.append(ShelfFolder(name: trimmed))
        save()
    }

    public func renameFolder(_ name: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name,
              !folders.contains(where: { $0.name == trimmed }),
              let index = folders.firstIndex(where: { $0.name == name })
        else { return }
        folders[index].name = trimmed
        save()
    }

    public func deleteFolder(_ name: String) {
        folders.removeAll { $0.name == name }
        save()
    }

    // MARK: Storage

    private struct File: Codable {
        var history: [ShelfHistory]
        var folders: [ShelfFolder]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let file = try decoder.decode(File.self, from: data)
            history = file.history
            folders = file.folders
        } catch {
            // A broken file is reported, not silently replaced: the reader
            // can still see the error and the file stays for repair.
            lastError = "reading shelf.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard !inMemory else { return }
        do {
            let file = File(history: history, folders: folders)
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = "writing shelf.json: \(error.localizedDescription)"
        }
    }
}
