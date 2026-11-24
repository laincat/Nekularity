import Foundation
import Testing
@testable import NekularityKit

@MainActor
@Suite("Novel shelf store")
struct NovelShelfStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "novel-shelf-\(UUID().uuidString)")
    }

    private func sampleItem(_ id: String = "n1", title: String = "星塔") -> NovelShelfItem {
        NovelShelfItem(
            source: "demo_novel",
            novelID: id,
            title: title,
            author: "Alice",
            cover: "https://novel.test/c.jpg",
            status: "ongoing",
            totalChapters: 12,
            addedAt: 100
        )
    }

    @Test func bookshelfItemsPersistAndDeduplicate() {
        let dir = directory()
        let store = NovelShelfStore(directory: dir)
        #expect(store.add(sampleItem("n1", title: "星塔")))
        #expect(!store.add(sampleItem("n1", title: "星塔")))
        #expect(store.contains(source: "demo_novel", novelID: "n1"))

        // Updating metadata preserves original addedAt.
        let updated = NovelShelfItem(
            source: "demo_novel",
            novelID: "n1",
            title: "星塔·修订版",
            totalChapters: 20,
            addedAt: 999,
            updatedAt: 200
        )
        #expect(!store.add(updated))
        #expect(store.item(source: "demo_novel", novelID: "n1")?.addedAt == 100)
        #expect(store.item(source: "demo_novel", novelID: "n1")?.totalChapters == 20)

        let reopened = NovelShelfStore(directory: dir)
        #expect(reopened.item(source: "demo_novel", novelID: "n1")?.title == "星塔·修订版")
        #expect(reopened.lastError == nil)

        #expect(reopened.remove(source: "demo_novel", novelID: "n1"))
        #expect(!reopened.contains(source: "demo_novel", novelID: "n1"))
    }

    @Test func invalidIdentityReportsErrorWithoutWriting() {
        let store = NovelShelfStore(directory: directory())
        #expect(!store.add(NovelShelfItem(source: "", novelID: "", title: "Bad")))
        #expect(store.items.isEmpty)
        #expect(store.lastError != nil)
        #expect(store.diskWriteCount == 0)
    }

    @Test func readingProgressCoalescesWritesAndSkipsUnchanged() {
        let dir = directory()
        let store = NovelShelfStore(directory: dir)
        store.progressSaveDelay = .seconds(60)

        store.recordProgress(NovelReadingProgress(
            source: "demo_novel",
            novelID: "n1",
            title: "星塔",
            chapterID: "ch1",
            chapterTitle: "第 1 章",
            chapterIndex: 0,
            paragraphIndex: 0,
            progress: 0.0,
            updatedAt: 10
        ))
        let baseline = store.diskWriteCount

        // Identical values do not schedule a write.
        #expect(store.updateProgress(source: "demo_novel", novelID: "n1", paragraphIndex: 0, progress: 0.0))
        store.flush()
        #expect(store.diskWriteCount == baseline)

        // Rapid scroll updates coalesce until flush().
        for p in 1...10 {
            #expect(store.updateProgress(
                source: "demo_novel",
                novelID: "n1",
                paragraphIndex: p,
                progress: Double(p) / 10.0
            ))
        }
        #expect(store.diskWriteCount == baseline)
        store.flush()
        #expect(store.diskWriteCount == baseline + 1)

        let reopened = NovelShelfStore(directory: dir)
        let saved = reopened.readingProgress(source: "demo_novel", novelID: "n1")
        #expect(saved?.paragraphIndex == 10)
        #expect(saved?.percent == 100)
    }

    @Test func batchImportWritesOnceAtomically() {
        let dir = directory()
        let store = NovelShelfStore(directory: dir)
        let baseline = store.diskWriteCount

        store.performBatch {
            for i in 1...20 {
                _ = store.add(sampleItem("n\(i)", title: "书 \(i)"))
                store.recordProgress(NovelReadingProgress(
                    source: "demo_novel",
                    novelID: "n\(i)",
                    title: "书 \(i)",
                    chapterID: "ch\(i)",
                    chapterIndex: i - 1,
                    paragraphIndex: i,
                    progress: 0.5,
                    updatedAt: i
                ))
            }
        }
        #expect(store.diskWriteCount == baseline + 1)

        let reopened = NovelShelfStore(directory: dir)
        #expect(reopened.items.count == 20)
        #expect(reopened.progress.count == 20)
    }

    @Test func mergeKeepsNewerLocalPositionAndFailedWriteRetriesOnFlush() {
        let dir = directory()
        let store = NovelShelfStore(directory: dir)
        store.progressSaveDelay = .seconds(60)
        store.recordProgress(NovelReadingProgress(
            source: "demo_novel",
            novelID: "n1",
            title: "星塔",
            chapterID: "ch5",
            chapterIndex: 4,
            paragraphIndex: 3,
            progress: 0.5,
            updatedAt: 50
        ))
        #expect(!store.merge(NovelReadingProgress(
            source: "demo_novel",
            novelID: "n1",
            title: "星塔",
            chapterID: "ch1",
            chapterIndex: 0,
            updatedAt: 10
        )))
        #expect(store.readingProgress(source: "demo_novel", novelID: "n1")?.chapterID == "ch5")

        let baseline = store.diskWriteCount
        var shouldFail = true
        store.fileWriter = { data, url in
            if shouldFail { throw CoreError("disk full") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        #expect(store.updateProgress(source: "demo_novel", novelID: "n1", paragraphIndex: 9, progress: 0.9))
        store.flush()
        #expect(store.lastError != nil)
        #expect(store.diskWriteCount == baseline)

        shouldFail = false
        store.flush()
        #expect(store.lastError == nil)
        #expect(store.diskWriteCount == baseline + 1)
    }

    @Test func brokenNovelShelfFileIsRescuedNotOverwritten() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "novel_shelf.json")
        try Data("{broken json".utf8).write(to: file)

        let store = NovelShelfStore(directory: dir)
        #expect(store.lastError != nil)
        #expect(store.items.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent.hasPrefix("novel_shelf.json.broken-") })
    }
}

@MainActor
@Suite("Novel reader coordinator")
struct NovelReaderCoordinatorTests {
    private func sampleDetail() -> NovelDetail {
        NovelDetail(
            id: "n1",
            title: "星塔",
            author: "Alice",
            status: "ongoing",
            tags: ["fantasy"],
            chapters: [
                NovelChapter(id: "ch1", title: "第一章"),
                NovelChapter(id: "ch2", title: "第二章"),
            ]
        )
    }

    @Test func loadsDetailResumesSavedChapterExtractsTextAndTracksProgress() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "novel-coord-\(UUID().uuidString)")
        let shelf = NovelShelfStore(directory: dir)
        shelf.progressSaveDelay = .seconds(60)
        // Pre-seed saved progress at chapter 2, paragraph 1.
        shelf.recordProgress(NovelReadingProgress(
            source: "demo",
            novelID: "n1",
            title: "星塔",
            chapterID: "ch2",
            chapterTitle: "第二章",
            chapterIndex: 1,
            paragraphIndex: 1,
            progress: 0.5
        ))

        let client = MockNovelClient(
            detail: .success(sampleDetail()),
            chapters: [
                "ch1": .success(NovelChapterContent(html: "<p>一之一</p><p>一之二</p>")),
                "ch2": .success(NovelChapterContent(html: "<p>二之一</p><script>bad()</script><p>二之二</p><p>二之三</p>")),
            ]
        )
        let coord = NovelReaderCoordinator(sourceKey: "demo", novelID: "n1", client: client, shelf: shelf)

        await coord.loadDetail()
        #expect(coord.state == .loaded)
        #expect(coord.currentChapter?.id == "ch2")
        #expect(coord.currentChapterIndex == 1)
        #expect(coord.currentParagraphIndex == 1)
        #expect(coord.document.paragraphs == ["二之一", "二之二", "二之三"])
        #expect(coord.hasPreviousChapter)
        #expect(!coord.hasNextChapter)

        let baseline = shelf.diskWriteCount
        coord.updateReadingPosition(paragraphIndex: 2)
        #expect(coord.currentParagraphIndex == 2)
        #expect(shelf.diskWriteCount == baseline)
        coord.flushProgress()
        #expect(shelf.diskWriteCount == baseline + 1)
        #expect(shelf.readingProgress(source: "demo", novelID: "n1")?.percent == 100)

        await coord.openPreviousChapter()
        #expect(coord.currentChapter?.id == "ch1")
        #expect(coord.document.paragraphs == ["一之一", "一之二"])

        #expect(coord.toggleShelf())
        #expect(coord.isOnShelf)
        #expect(shelf.contains(source: "demo", novelID: "n1"))
        #expect(!coord.toggleShelf())
        #expect(!shelf.contains(source: "demo", novelID: "n1"))
    }

    @Test func mapsCoreErrorsAndIgnoresCancellation() async {
        let shelf = NovelShelfStore()

        let disabledClient = MockNovelClient(detail: .failure(CoreError("plugin: disabled")))
        let disabledCoord = NovelReaderCoordinator(sourceKey: "demo", novelID: "n1", client: disabledClient, shelf: shelf)
        await disabledCoord.loadDetail()
        #expect(disabledCoord.state == .failed("该源已停用,请先在源管理中启用"))

        let cancelledClient = MockNovelClient(detail: .failure(CoreError("context canceled")))
        let cancelledCoord = NovelReaderCoordinator(sourceKey: "demo", novelID: "n1", client: cancelledClient, shelf: shelf)
        await cancelledCoord.loadDetail()
        #expect(cancelledCoord.state == .idle)
    }
}

private final class MockNovelClient: NovelProviderClient, @unchecked Sendable {
    let detailResult: Result<NovelDetail, Error>
    let chapters: [String: Result<NovelChapterContent, Error>]

    init(detail: Result<NovelDetail, Error>, chapters: [String: Result<NovelChapterContent, Error>] = [:]) {
        self.detailResult = detail
        self.chapters = chapters
    }

    func novelPopular(key: String, page: Int) async throws -> NovelPage {
        NovelPage(items: [], maxPage: 1)
    }

    func novelSearch(key: String, keyword: String, page: Int) async throws -> NovelPage {
        NovelPage(items: [], maxPage: 1)
    }

    func novelDetail(key: String, id novelID: String) async throws -> NovelDetail {
        try detailResult.get()
    }

    func novelChapter(key: String, novelID: String, chapterID: String) async throws -> NovelChapterContent {
        guard let result = chapters[chapterID] else {
            throw CoreError("novel: not found")
        }
        return try result.get()
    }
}
