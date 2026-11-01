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
    /// `nil` and "comic" mean reading; "video" means watching. Optional so that
    /// shelves written before the field existed still decode.
    public var kind: String? = nil
    /// Playback position in seconds, for a video.
    public var seconds: Int? = nil
    /// The video's length, for a progress bar. Zero when the source never said.
    public var duration: Int? = nil

    /// The comic's identity, source included: two sources may hand out the
    /// same comic id for different comics.
    public var key: String { source + "/" + id }

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

    /// Watching counts as history: one list answers "what did I do on this day",
    /// and a second list for video would make the calendar lie.
    public var isVideo: Bool { kind == "video" }

    /// How far through the video, 0–100, for the same bar a chapter gets.
    public var videoPercent: Int? {
        guard let seconds, let duration, duration > 0 else { return percent }
        return PlaybackProgress.percent(position: Double(seconds), duration: Double(duration))
    }

    public init(
        provider: String,
        videoID: String,
        title: String,
        cover: String? = nil,
        episode: String? = nil,
        seconds: Int = 0,
        duration: Int = 0,
        time: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.source = provider
        self.id = videoID
        self.title = title
        self.author = nil
        self.cover = cover
        self.chapter = episode
        self.chapterIndex = 0
        self.page = nil
        self.percent = PlaybackProgress.percent(position: Double(seconds), duration: Double(duration))
        self.time = time
        self.kind = "video"
        self.seconds = seconds
        self.duration = duration
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

/// A page kept from a chapter, as the desktop client stores it: a reference
/// to the source's image, never a downloaded copy.
public struct KeptPage: Codable, Hashable, Identifiable, Sendable {
    public var source: String
    public var comicID: String
    public var comicTitle: String
    public var chapterID: String
    public var chapterIndex: Int
    public var chapterName: String?
    /// 1-based, as the reader counts.
    public var page: Int
    public var url: String
    public var time: Int

    /// One page per source, comic and address.
    public var id: String { source + "/" + comicID + "/" + url }

    private enum CodingKeys: String, CodingKey {
        case source
        case comicID = "comicId"
        case comicTitle
        case chapterID = "chapterId"
        case chapterIndex
        case chapterName
        case page
        case url
        case time
    }

    public init(
        source: String,
        comicID: String,
        comicTitle: String,
        chapterID: String,
        chapterIndex: Int,
        chapterName: String? = nil,
        page: Int,
        url: String,
        time: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.source = source
        self.comicID = comicID
        self.comicTitle = comicTitle
        self.chapterID = chapterID
        self.chapterIndex = chapterIndex
        self.chapterName = chapterName
        self.page = page
        self.url = url
        self.time = time
    }
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
    /// Pages kept from a chapter, newest first.
    public private(set) var pictures: [KeptPage] = []
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

    /// Where to start a video this environment has watched before.
    ///
    /// A finished episode starts from the beginning: resuming two minutes before
    /// the credits is not a favour. nil means "no opinion", so a caller that
    /// knows better (a server's own position) can keep its own guess.
    public func playbackStart(provider: String, videoID: String) -> Double? {
        guard let entry = entry(source: provider, id: videoID), entry.isVideo,
              let seconds = entry.seconds, let duration = entry.duration else { return nil }
        guard PlaybackProgress.isResumable(position: Double(seconds), duration: Double(duration)) else {
            return nil
        }
        return Double(seconds)
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

    public var counts: (history: Int, favourites: Int, pictures: Int) {
        (history.count, folders.reduce(0) { $0 + $1.items.count }, pictures.count)
    }

    /// The kept pages, newest first.
    public func keptPages(limit: Int = 60) -> [KeptPage] {
        Array(pictures.prefix(max(0, limit)))
    }

    /// The page to reopen at, given the chapter being opened and how many
    /// pages it has. Nil means "start at the top": a different chapter, or a
    /// page the shelf never got as far as.
    public func resumePage(source: String, id: String, chapterIndex: Int, pageCount: Int) -> Int? {
        guard pageCount > 0,
              let entry = entry(source: source, id: id),
              entry.chapterIndex == chapterIndex,
              let page = entry.page, page > 1, page <= pageCount
        else { return nil }
        return page
    }

    /// Whether this page is already kept, so the reader can show it.
    public func isKept(source: String, comicID: String, url: String) -> Bool {
        pictures.contains { $0.source == source && $0.comicID == comicID && $0.url == url }
    }

    // MARK: Writing

    /// Records a position, moving the comic to the front; one comic appears
    /// once, at its latest chapter.
    /// Records where watching stopped. Called when playback starts and when the
    /// player closes, so an episode opened and abandoned still shows up.
    public func recordVideo(provider: String, videoID: String, title: String, cover: String? = nil,
                            episode: String? = nil, seconds: Double, duration: Double) {
        guard !provider.isEmpty, !videoID.isEmpty else { return }
        record(ShelfHistory(provider: provider, videoID: videoID, title: title, cover: cover,
                            episode: episode,
                            seconds: Int(seconds.rounded()),
                            duration: Int(duration.rounded())))
    }

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

    // MARK: Kept pages

    /// Keeps one page, moving it to the front. Returns false when it was
    /// already there under the same address.
    @discardableResult
    public func keepPage(_ page: KeptPage) -> Bool {
        guard !page.source.isEmpty, !page.comicID.isEmpty, !page.url.isEmpty else {
            lastError = "a kept page needs a source, a comic and an address"
            return false
        }
        let moved = pictures.contains { $0.id == page.id }
        pictures.removeAll { $0.id == page.id }
        pictures.insert(page, at: 0)
        save()
        return !moved
    }

    public func forgetPage(_ page: KeptPage) {
        pictures.removeAll { $0.id == page.id }
        save()
    }

    /// Merges a page from an import without pushing an older copy over a
    /// newer one.
    @discardableResult
    public func merge(_ page: KeptPage) -> Bool {
        if let existing = pictures.first(where: { $0.id == page.id }), existing.time >= page.time {
            return false
        }
        _ = keepPage(page)
        return true
    }

    // MARK: Storage

    private struct File: Codable {
        var history: [ShelfHistory]
        var folders: [ShelfFolder]
        /// Omitted when empty, so an older desktop build reads this file as
        /// before.
        var pictures: [KeptPage]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let file = try decoder.decode(File.self, from: data)
            history = file.history
            folders = file.folders
            pictures = file.pictures ?? []
        } catch {
            // A broken file is reported, not silently replaced: the reader
            // can still see the error and the file stays for repair.
            lastError = "reading shelf.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard !inMemory else { return }
        do {
            let file = File(history: history, folders: folders,
                            pictures: pictures.isEmpty ? nil : pictures)
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
