import Foundation
import Observation

/// Minimal novel Core surface needed by reading coordinators and tests.
public protocol NovelProviderClient: Sendable {
    func novelPopular(key: String, page: Int) async throws -> NovelPage
    func novelSearch(key: String, keyword: String, page: Int) async throws -> NovelPage
    func novelDetail(key: String, id novelID: String) async throws -> NovelDetail
    func novelChapter(key: String, novelID: String, chapterID: String) async throws -> NovelChapterContent
}

extension CoreClient: NovelProviderClient {}

/// Minimal reading data coordinator for one novel.
///
/// Loads metadata and chapters from Core, extracts safe plain-text paragraphs
/// via `NovelTextExtractor`, tracks bookshelf membership and chapter reading
/// progress in `NovelShelfStore`, and guards against stale out-of-order chapter
/// responses via a monotonic request generation counter.
@MainActor
@Observable
public final class NovelReaderCoordinator {
    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public let sourceKey: String
    public let novelID: String

    public private(set) var detail: NovelDetail?
    public private(set) var currentChapterIndex: Int = 0
    public private(set) var currentChapter: NovelChapter?
    public private(set) var rawHTML: String = ""
    public private(set) var document: NovelChapterDocument = .init(paragraphs: [])
    public private(set) var currentParagraphIndex: Int = 0
    public private(set) var state: LoadState = .idle
    public private(set) var isOnShelf: Bool

    @ObservationIgnored private let client: any NovelProviderClient
    @ObservationIgnored private let shelf: NovelShelfStore
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    public init(sourceKey: String, novelID: String, client: any NovelProviderClient, shelf: NovelShelfStore) {
        self.sourceKey = sourceKey
        self.novelID = novelID
        self.client = client
        self.shelf = shelf
        self.isOnShelf = shelf.contains(source: sourceKey, novelID: novelID)
    }

    public var chapters: [NovelChapter] { detail?.chapters ?? [] }
    public var hasPreviousChapter: Bool { currentChapterIndex > 0 && !chapters.isEmpty }
    public var hasNextChapter: Bool { currentChapterIndex + 1 < chapters.count }

    /// Loads the novel's metadata and chapter list, then optionally opens the
    /// saved reading position (or the first chapter).
    public func loadDetail(autoOpenChapter: Bool = true) async {
        let generation = nextGeneration()
        state = .loading
        do {
            let loaded = try await client.novelDetail(key: sourceKey, id: novelID)
            guard generation == requestGeneration else { return }
            detail = loaded
            isOnShelf = shelf.contains(source: sourceKey, novelID: novelID)
            if isOnShelf {
                _ = shelf.add(NovelShelfItem(source: sourceKey, detail: loaded))
            }
            guard autoOpenChapter, !loaded.chapters.isEmpty else {
                state = .loaded
                return
            }
            let saved = shelf.readingProgress(source: sourceKey, novelID: novelID)
            let startIndex = resolveChapterIndex(in: loaded.chapters, saved: saved)
            let startParagraph = (saved?.chapterID == loaded.chapters[startIndex].id) ? (saved?.paragraphIndex ?? 0) : 0
            await openChapter(at: startIndex, initialParagraph: startParagraph)
        } catch let error as CoreError where error.isCancelled {
            if generation == requestGeneration {
                state = detail == nil ? .idle : .loaded
            }
        } catch {
            if generation == requestGeneration {
                let message = (error as? CoreError)?.errorDescription ?? CoreError.readable(error.localizedDescription)
                state = .failed(message)
            }
        }
    }

    /// Loads one chapter by index, extracts clean paragraphs and persists the
    /// new chapter position.
    public func openChapter(at index: Int, initialParagraph: Int = 0) async {
        guard let detail, detail.chapters.indices.contains(index) else {
            state = .failed("章节不存在")
            return
        }
        let chapter = detail.chapters[index]
        let generation = nextGeneration()
        state = .loading
        do {
            let content = try await client.novelChapter(key: sourceKey, novelID: detail.id, chapterID: chapter.id)
            guard generation == requestGeneration else { return }
            let extracted = content.extractedDocument()
            let clampedParagraph = extracted.paragraphs.isEmpty
                ? 0
                : min(max(0, initialParagraph), extracted.paragraphs.count - 1)

            currentChapterIndex = index
            currentChapter = chapter
            rawHTML = content.html
            document = extracted
            currentParagraphIndex = clampedParagraph
            state = .loaded

            let progressFraction = Self.progressFraction(paragraphIndex: clampedParagraph,
                                                         paragraphCount: extracted.paragraphs.count)
            shelf.recordProgress(NovelReadingProgress(
                source: sourceKey,
                novelID: detail.id,
                title: detail.title,
                author: detail.author,
                cover: detail.cover,
                chapterID: chapter.id,
                chapterTitle: chapter.title,
                chapterIndex: index,
                paragraphIndex: clampedParagraph,
                progress: progressFraction
            ))
        } catch let error as CoreError where error.isCancelled {
            if generation == requestGeneration {
                state = currentChapter == nil ? .idle : .loaded
            }
        } catch {
            if generation == requestGeneration {
                let message = (error as? CoreError)?.errorDescription ?? CoreError.readable(error.localizedDescription)
                state = .failed(message)
            }
        }
    }

    public func openPreviousChapter() async {
        guard hasPreviousChapter else { return }
        await openChapter(at: currentChapterIndex - 1)
    }

    public func openNextChapter() async {
        guard hasNextChapter else { return }
        await openChapter(at: currentChapterIndex + 1)
    }

    /// Updates paragraph progress inside the current chapter using coalesced
    /// persistence.
    public func updateReadingPosition(paragraphIndex: Int) {
        guard let detail, let chapter = currentChapter else { return }
        let clamped = document.paragraphs.isEmpty
            ? 0
            : min(max(0, paragraphIndex), document.paragraphs.count - 1)
        currentParagraphIndex = clamped
        let fraction = Self.progressFraction(paragraphIndex: clamped, paragraphCount: document.paragraphs.count)
        let updated = shelf.updateProgress(
            source: sourceKey,
            novelID: detail.id,
            chapterID: chapter.id,
            chapterTitle: chapter.title,
            chapterIndex: currentChapterIndex,
            paragraphIndex: clamped,
            progress: fraction
        )
        if !updated {
            shelf.recordProgress(NovelReadingProgress(
                source: sourceKey,
                novelID: detail.id,
                title: detail.title,
                author: detail.author,
                cover: detail.cover,
                chapterID: chapter.id,
                chapterTitle: chapter.title,
                chapterIndex: currentChapterIndex,
                paragraphIndex: clamped,
                progress: fraction
            ))
        }
    }

    /// Toggles bookshelf membership for the loaded novel and returns the new state.
    @discardableResult
    public func toggleShelf() -> Bool {
        if shelf.contains(source: sourceKey, novelID: novelID) {
            shelf.remove(source: sourceKey, novelID: novelID)
            isOnShelf = false
        } else if let detail {
            _ = shelf.add(NovelShelfItem(source: sourceKey, detail: detail))
            isOnShelf = true
        }
        return isOnShelf
    }

    public func flushProgress() {
        shelf.flush()
    }

    // MARK: Helpers

    private func nextGeneration() -> UInt64 {
        requestGeneration &+= 1
        return requestGeneration
    }

    private func resolveChapterIndex(in chapters: [NovelChapter], saved: NovelReadingProgress?) -> Int {
        guard let saved else { return 0 }
        if let matched = chapters.firstIndex(where: { $0.id == saved.chapterID }) {
            return matched
        }
        return min(max(0, saved.chapterIndex), chapters.count - 1)
    }

    static func progressFraction(paragraphIndex: Int, paragraphCount: Int) -> Double {
        guard paragraphCount > 0 else { return 0 }
        if paragraphCount == 1 { return 1.0 }
        return min(1.0, max(0.0, Double(paragraphIndex) / Double(paragraphCount - 1)))
    }
}
