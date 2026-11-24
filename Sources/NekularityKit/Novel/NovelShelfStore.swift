import Foundation
import Observation

/// One novel saved on the reader's bookshelf.
public struct NovelShelfItem: Codable, Hashable, Identifiable, Sendable {
    public var source: String
    public var novelID: String
    public var title: String
    public var author: String?
    public var cover: String?
    public var status: String?
    public var totalChapters: Int
    /// Unix seconds when added to the bookshelf.
    public var addedAt: Int
    /// Unix seconds when metadata was last refreshed.
    public var updatedAt: Int

    public var id: String { source + "/" + novelID }
    public var key: String { id }

    public init(
        source: String,
        novelID: String,
        title: String,
        author: String? = nil,
        cover: String? = nil,
        status: String? = nil,
        totalChapters: Int = 0,
        addedAt: Int = Int(Date().timeIntervalSince1970),
        updatedAt: Int? = nil
    ) {
        self.source = source
        self.novelID = novelID
        self.title = title
        self.author = author
        self.cover = cover
        self.status = status
        self.totalChapters = max(0, totalChapters)
        self.addedAt = addedAt
        self.updatedAt = updatedAt ?? addedAt
    }

    public init(source: String, detail: NovelDetail, now: Int = Int(Date().timeIntervalSince1970)) {
        self.init(
            source: source,
            novelID: detail.id,
            title: detail.title,
            author: detail.author,
            cover: detail.cover,
            status: detail.status,
            totalChapters: detail.chapters.count,
            addedAt: now,
            updatedAt: now
        )
    }

    public init(source: String, item: NovelItem, now: Int = Int(Date().timeIntervalSince1970)) {
        self.init(
            source: source,
            novelID: item.id,
            title: item.title,
            author: item.author,
            cover: item.cover,
            addedAt: now,
            updatedAt: now
        )
    }
}

/// Where reading stopped inside a novel.
public struct NovelReadingProgress: Codable, Hashable, Identifiable, Sendable {
    public var source: String
    public var novelID: String
    public var title: String
    public var author: String?
    public var cover: String?
    public var chapterID: String
    public var chapterTitle: String?
    public var chapterIndex: Int
    /// 0-based paragraph offset inside the current chapter.
    public var paragraphIndex: Int
    /// Reading fraction within the current chapter, clamped to 0...1.
    public var progress: Double
    /// Unix seconds when reading last advanced.
    public var updatedAt: Int

    public var id: String { source + "/" + novelID }
    public var key: String { id }

    /// Percentage 0–100 derived from `progress`.
    public var percent: Int {
        Int((min(1.0, max(0.0, progress)) * 100.0).rounded())
    }

    public init(
        source: String,
        novelID: String,
        title: String,
        author: String? = nil,
        cover: String? = nil,
        chapterID: String,
        chapterTitle: String? = nil,
        chapterIndex: Int = 0,
        paragraphIndex: Int = 0,
        progress: Double = 0,
        updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.source = source
        self.novelID = novelID
        self.title = title
        self.author = author
        self.cover = cover
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.chapterIndex = max(0, chapterIndex)
        self.paragraphIndex = max(0, paragraphIndex)
        self.progress = min(1.0, max(0.0, progress))
        self.updatedAt = updatedAt
    }
}

/// Persisted novel bookshelf and chapter reading progress, one file per profile.
///
/// Mirrors `ShelfStore`'s write discipline: rapid reading-progress updates
/// coalesce onto a single debounced write, `performBatch` folds multiple
/// mutations into a single atomic write, `flush()` commits pending changes
/// immediately, and a damaged file is copied aside via `StoreRescue` rather
/// than silently overwritten.
@MainActor
@Observable
public final class NovelShelfStore {
    public static let progressLimit = 500

    public private(set) var items: [NovelShelfItem] = []
    public private(set) var progress: [NovelReadingProgress] = []
    public private(set) var lastError: String?

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var inMemory = false
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var progressSaveTask: Task<Void, Never>?
    @ObservationIgnored var progressSaveDelay: Duration = .milliseconds(800)
    @ObservationIgnored private(set) var diskWriteCount = 0
    @ObservationIgnored var fileWriter: ((Data, URL) throws -> Void)?

    public init(directory: URL, filename: String = "novel_shelf.json") {
        let name = filename.split(separator: "/").last.map(String.init) ?? "novel_shelf.json"
        self.url = directory.appendingPathComponent(name == ".." ? "novel_shelf.json" : name)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    /// In-memory store for previews and unit tests.
    public init() {
        self.url = URL(fileURLWithPath: "/dev/null")
        self.inMemory = true
    }

    // MARK: Bookshelf

    public func contains(source: String, novelID: String) -> Bool {
        items.contains { $0.source == source && $0.novelID == novelID }
    }

    public func item(source: String, novelID: String) -> NovelShelfItem? {
        items.first { $0.source == source && $0.novelID == novelID }
    }

    /// Adds a novel to the bookshelf (or refreshes its metadata if already kept).
    /// Returns true if the item was newly added.
    @discardableResult
    public func add(_ item: NovelShelfItem) -> Bool {
        guard !item.source.isEmpty, !item.novelID.isEmpty else {
            lastError = "a novel shelf item needs a source and a novel id"
            return false
        }
        if let index = items.firstIndex(where: { $0.source == item.source && $0.novelID == item.novelID }) {
            var updated = item
            updated.addedAt = items[index].addedAt
            guard updated != items[index] else { return false }
            items[index] = updated
            save()
            return false
        }
        items.insert(item, at: 0)
        save()
        return true
    }

    /// Removes a novel from the bookshelf. Returns true if it was present.
    @discardableResult
    public func remove(source: String, novelID: String) -> Bool {
        let before = items.count
        items.removeAll { $0.source == source && $0.novelID == novelID }
        guard items.count != before else { return false }
        save()
        return true
    }

    // MARK: Reading progress

    public func recentProgress(limit: Int = 40) -> [NovelReadingProgress] {
        Array(progress.prefix(max(0, limit)))
    }

    public func readingProgress(source: String, novelID: String) -> NovelReadingProgress? {
        progress.first { $0.source == source && $0.novelID == novelID }
    }

    /// Records a reading position and moves the novel to the front of recent history.
    public func recordProgress(_ entry: NovelReadingProgress) {
        guard !entry.source.isEmpty, !entry.novelID.isEmpty, !entry.chapterID.isEmpty else {
            lastError = "a novel reading position needs a source, a novel id and a chapter id"
            return
        }
        progress.removeAll { $0.source == entry.source && $0.novelID == entry.novelID }
        progress.insert(entry, at: 0)
        if progress.count > Self.progressLimit {
            progress.removeLast(progress.count - Self.progressLimit)
        }
        save()
    }

    /// Updates how far the reader got inside a tracked novel without reordering
    /// history. Unchanged positions skip disk writes, and rapid updates coalesce
    /// onto a single debounced write until `flush()` or `progressSaveDelay`.
    @discardableResult
    public func updateProgress(
        source: String,
        novelID: String,
        chapterID: String? = nil,
        chapterTitle: String? = nil,
        chapterIndex: Int? = nil,
        paragraphIndex: Int? = nil,
        progress fraction: Double? = nil
    ) -> Bool {
        guard let index = progress.firstIndex(where: { $0.source == source && $0.novelID == novelID }) else {
            return false
        }
        var updated = progress[index]
        if let chapterID, !chapterID.isEmpty { updated.chapterID = chapterID }
        if let chapterTitle { updated.chapterTitle = chapterTitle }
        if let chapterIndex { updated.chapterIndex = max(0, chapterIndex) }
        if let paragraphIndex { updated.paragraphIndex = max(0, paragraphIndex) }
        if let fraction { updated.progress = min(1.0, max(0.0, fraction)) }
        guard updated != progress[index] else {
            return true
        }
        updated.updatedAt = Int(Date().timeIntervalSince1970)
        progress[index] = updated
        scheduleProgressSave()
        return true
    }

    /// Merges a progress entry without overwriting a newer local position.
    @discardableResult
    public func merge(_ entry: NovelReadingProgress) -> Bool {
        if let existing = progress.first(where: { $0.source == entry.source && $0.novelID == entry.novelID }),
           existing.updatedAt >= entry.updatedAt {
            return false
        }
        recordProgress(entry)
        return true
    }

    public func forgetProgress(source: String, novelID: String) {
        let before = progress.count
        progress.removeAll { $0.source == source && $0.novelID == novelID }
        guard progress.count != before else { return }
        save()
    }

    // MARK: Batching and flushing

    /// Groups multiple mutations into a single atomic write when the outermost
    /// batch finishes.
    public func performBatch(_ body: () -> Void) {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0, dirty {
                writeNow()
            }
        }
        body()
    }

    /// Writes any pending coalesced progress or failed write immediately.
    public func flush() {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        guard dirty else { return }
        writeNow()
    }

    // MARK: Storage

    private struct File: Codable {
        var items: [NovelShelfItem]
        var progress: [NovelReadingProgress]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let file = try decoder.decode(File.self, from: data)
            items = file.items
            progress = file.progress
        } catch {
            let kept = StoreRescue.keepCopy(of: url)
            lastError = "reading \(url.lastPathComponent): \(error.localizedDescription)"
                + (kept.map { ", 旧数据已另存为 \($0.lastPathComponent)" } ?? "")
        }
    }

    private func save() {
        dirty = true
        if batchDepth > 0 { return }
        writeNow()
    }

    private func scheduleProgressSave() {
        dirty = true
        if batchDepth > 0 { return }
        guard !inMemory else { return }
        progressSaveTask?.cancel()
        let delay = progressSaveDelay
        progressSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.flush()
        }
    }

    private func writeNow() {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        guard !inMemory else {
            dirty = false
            return
        }
        do {
            let file = File(items: items, progress: progress)
            let data = try encoder.encode(file)
            if let fileWriter {
                try fileWriter(data, url)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            diskWriteCount += 1
            dirty = false
            lastError = nil
        } catch {
            dirty = true
            lastError = "writing \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
