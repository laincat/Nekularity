import Foundation
import Testing
@testable import NekularityKit

@MainActor
@Suite struct ShelfStoreTests {
    func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)")
    }

    func comic(_ id: String, title: String = "标题") -> ShelfComic {
        ShelfComic(source: "copy_manga", id: id, title: title, author: "作者", cover: "https://x/1.jpg")
    }

    @Test func oneEntryPerComicNewestFirst() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 1 话", chapterIndex: 0, time: 10))
        store.record(ShelfHistory(comic: comic("2"), chapter: "第 1 话", chapterIndex: 0, time: 20))
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 9 话", chapterIndex: 8, time: 30))

        let history = store.recentHistory()
        #expect(history.count == 2)
        #expect(history.first?.id == "1")
        #expect(history.first?.chapter == "第 9 话")
        #expect(history.last?.id == "2")
    }

    @Test func historyNeedsIdentity() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: ShelfComic(source: "", id: "", title: "x")))
        #expect(store.recentHistory().isEmpty)
        #expect(store.lastError != nil)
    }

    @Test func progressKeepsTheEntryInPlace() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("old"), time: 10))
        store.record(ShelfHistory(comic: comic("new"), time: 20))

        #expect(store.updateProgress(source: "copy_manga", id: "old", chapter: "第 5 话",
                                    chapterIndex: 4, page: 12, percent: 37))
        let history = store.recentHistory()
        #expect(history.first?.id == "new")
        #expect(history.last?.chapter == "第 5 话")
        #expect(history.last?.percent == 37)
        #expect(history.last?.page == 12)

        // Out of range values are clamped, and an unknown comic is not added.
        store.updateProgress(source: "copy_manga", id: "old", page: -3, percent: 250)
        #expect(store.recentHistory().last?.percent == 100)
        #expect(!store.updateProgress(source: "copy_manga", id: "absent"))
        #expect(store.recentHistory().count == 2)
    }

    @Test func importDoesNotLoseANewerLocalPosition() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 3 话", time: 50))
        #expect(!store.merge(ShelfHistory(comic: comic("1"), chapter: "第 1 话", time: 10)))
        #expect(store.recentHistory().first?.chapter == "第 3 话")
        #expect(store.merge(ShelfHistory(comic: comic("1"), chapter: "第 9 话", time: 90)))
        #expect(store.recentHistory().first?.chapter == "第 9 话")
    }

    @Test func foldersHoldOneCopyOfAComic() {
        let store = ShelfStore(directory: directory())
        #expect(store.add(comic("1")))
        #expect(!store.add(comic("1")))
        #expect(store.folderHolding(source: "copy_manga", id: "1") == ShelfStore.defaultFolder)
        #expect(store.counts.favourites == 1)

        store.remove(comic("1"))
        #expect(store.folderHolding(source: "copy_manga", id: "1") == nil)
    }

    @Test func foldersCanBeCreatedRenamedAndDeleted() {
        let store = ShelfStore(directory: directory())
        store.createFolder("  稍后读 ")
        store.createFolder("稍后读")
        #expect(store.folders.map(\.name) == ["稍后读"])

        store.add(comic("1"), to: "稍后读")
        store.renameFolder("稍后读", to: "以后看")
        #expect(store.folderHolding(source: "copy_manga", id: "1") == "以后看")
        #expect(store.folderNames().contains("收藏"))

        store.deleteFolder("以后看")
        #expect(store.folderHolding(source: "copy_manga", id: "1") == nil)
    }

    @Test func movingTakesTheComicOutOfItsFolder() {
        let store = ShelfStore(directory: directory())
        store.add(comic("1"), to: "甲")
        #expect(store.move(comic("1"), to: "乙"))
        #expect(store.folderHolding(source: "copy_manga", id: "1") == "乙")
        #expect(store.folder(named: "甲")?.items.isEmpty == true)
        #expect(!store.move(comic("1"), to: "乙"))
    }

    @Test func shelfSurvivesReopening() {
        let dir = directory()
        let store = ShelfStore(directory: dir)
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 2 话", chapterIndex: 1, time: 7))
        store.add(comic("2"))

        let again = ShelfStore(directory: dir)
        #expect(again.recentHistory().first?.chapter == "第 2 话")
        #expect(again.counts.favourites == 1)
        #expect(again.lastError == nil)
    }

    @Test func brokenFileIsReportedNotOverwritten() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: dir.appending(path: "shelf.json"))
        let store = ShelfStore(directory: dir)
        #expect(store.recentHistory().isEmpty)
        #expect(store.lastError != nil)
        // The file is still there, untouched by opening it.
        #expect(try Data(contentsOf: dir.appending(path: "shelf.json")) == Data("{".utf8))
    }

    @Test func entryFindsOneComicPosition() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 2 话", chapterIndex: 1, page: 7, percent: 33, time: 10))
        store.record(ShelfHistory(comic: comic("2"), chapter: "第 1 话", chapterIndex: 0, time: 20))
        #expect(store.entry(source: "copy_manga", id: "1")?.page == 7)
        #expect(store.entry(source: "copy_manga", id: "2")?.chapterIndex == 0)
        #expect(store.entry(source: "copy_manga", id: "3") == nil)
        // Another source with the same id is another comic.
        #expect(store.entry(source: "manga_dex", id: "1") == nil)
    }

    @Test func progressKeepsTheEntryPlace() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 1 话", chapterIndex: 0, time: 10))
        store.record(ShelfHistory(comic: comic("2"), chapter: "第 1 话", chapterIndex: 0, time: 20))
        #expect(store.updateProgress(source: "copy_manga", id: "1", page: 4, percent: 12))
        #expect(store.recentHistory().first?.id == "2")
        #expect(store.entry(source: "copy_manga", id: "1")?.page == 4)
        #expect(store.entry(source: "copy_manga", id: "1")?.percent == 12)
        // An unknown comic is not added by a scroll.
        #expect(!store.updateProgress(source: "copy_manga", id: "9", page: 2, percent: 5))
        #expect(store.entry(source: "copy_manga", id: "9") == nil)
    }

    @Test func resumePageOnlyForTheSameChapter() {
        let store = ShelfStore(directory: directory())
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 3 话", chapterIndex: 2, page: 7, time: 10))

        #expect(store.resumePage(source: "copy_manga", id: "1", chapterIndex: 2, pageCount: 20) == 7)
        // Another chapter starts at the top.
        #expect(store.resumePage(source: "copy_manga", id: "1", chapterIndex: 1, pageCount: 20) == nil)
        // A page past the end is not a position this chapter has.
        #expect(store.resumePage(source: "copy_manga", id: "1", chapterIndex: 2, pageCount: 5) == nil)
        // Page one is the top already.
        store.record(ShelfHistory(comic: comic("2"), chapter: "第 1 话", chapterIndex: 0, page: 1, time: 20))
        #expect(store.resumePage(source: "copy_manga", id: "2", chapterIndex: 0, pageCount: 10) == nil)
        // Unknown comics and empty chapters have nowhere to go.
        #expect(store.resumePage(source: "copy_manga", id: "9", chapterIndex: 0, pageCount: 10) == nil)
        #expect(store.resumePage(source: "copy_manga", id: "1", chapterIndex: 2, pageCount: 0) == nil)
    }

    func page(_ url: String, page: Int = 3, time: Int = 10) -> KeptPage {
        KeptPage(source: "copy_manga", comicID: "1", comicTitle: "标题",
                 chapterID: "ch-1", chapterIndex: 2, chapterName: "第03话",
                 page: page, url: url, time: time)
    }

    @Test func keptPagesAreOnePerAddressNewestFirst() {
        let store = ShelfStore(directory: directory())
        #expect(store.keepPage(page("https://x/a.jpg", time: 10)))
        #expect(store.keepPage(page("https://x/b.jpg", time: 20)))
        // Keeping the same address again moves it, it does not duplicate it.
        #expect(!store.keepPage(page("https://x/a.jpg", time: 30)))

        let kept = store.keptPages()
        #expect(kept.count == 2)
        #expect(kept.first?.url == "https://x/a.jpg")
        #expect(store.isKept(source: "copy_manga", comicID: "1", url: "https://x/b.jpg"))
        #expect(!store.isKept(source: "copy_manga", comicID: "2", url: "https://x/b.jpg"))
    }

    @Test func keptPageNeedsIdentity() {
        let store = ShelfStore(directory: directory())
        #expect(!store.keepPage(KeptPage(source: "", comicID: "1", comicTitle: "x",
                                         chapterID: "c", chapterIndex: 0, page: 1, url: "u")))
        #expect(store.keptPages().isEmpty)
        #expect(store.lastError != nil)
    }

    @Test func keptPagesUseTheDesktopKeyNames() throws {
        let dir = directory()
        let store = ShelfStore(directory: dir)
        store.keepPage(page("https://x/a.jpg"))
        let text = try String(contentsOf: dir.appending(path: "shelf.json"), encoding: .utf8)
        #expect(text.contains("\"comicId\""))
        #expect(text.contains("\"chapterId\""))
        #expect(text.contains("\"pictures\""))

        // The desktop client reads the same keys back.
        let reopened = ShelfStore(directory: dir)
        #expect(reopened.keptPages().first?.comicID == "1")
        #expect(reopened.keptPages().first?.chapterName == "第03话")
        #expect(reopened.keptPages().first?.page == 3)
        #expect(reopened.keptPages().first?.time == 10)
    }

    @Test func anEmptyShelfOmitsPictures() throws {
        let dir = directory()
        let store = ShelfStore(directory: dir)
        store.record(ShelfHistory(comic: comic("1"), time: 10))
        let text = try String(contentsOf: dir.appending(path: "shelf.json"), encoding: .utf8)
        #expect(!text.contains("pictures"))
    }

    @Test func importDoesNotPushAnOlderKeptPage() {
        let store = ShelfStore(directory: directory())
        store.keepPage(page("https://x/a.jpg", time: 50))
        #expect(!store.merge(page("https://x/a.jpg", time: 10)))
        #expect(store.keptPages().first?.time == 50)
        #expect(store.merge(page("https://x/b.jpg", time: 60)))
        #expect(store.keptPages().count == 2)
    }

    /// Taking one comic off the history leaves the others, and the change
    /// survives reopening: the desktop has the same rule, tested the same way.
    @Test func forgettingOneHistoryEntryKeepsTheOthers() {
        let dir = directory()
        let store = ShelfStore(directory: dir)
        store.record(ShelfHistory(comic: comic("1"), chapter: "第 1 话", chapterIndex: 0, time: 10))
        store.record(ShelfHistory(comic: comic("2"), chapter: "第 1 话", chapterIndex: 0, time: 20))

        store.forgetHistory(source: "copy_manga", id: "1")

        #expect(store.history.count == 1)
        #expect(store.history.first?.id == "2")
        #expect(ShelfStore(directory: dir).history.count == 1)
    }

    /// A forgotten kept page is gone from the file too, not only from memory.
    @Test func forgettingAPagePersists() {
        let dir = directory()
        let store = ShelfStore(directory: dir)
        let kept = page("https://x/a.jpg", time: 10)
        store.merge(kept)
        #expect(store.keptPages().count == 1)

        store.forgetPage(kept)

        #expect(store.keptPages().isEmpty)
        #expect(ShelfStore(directory: dir).keptPages().isEmpty)
    }
}

@Suite("Watching counts as history")
@MainActor
struct VideoHistoryTests {
    private func store() throws -> ShelfStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "shelf-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ShelfStore(directory: root)
    }

    @Test("a video lands in the same history list a chapter does")
    func recordsVideo() throws {
        let shelf = try store()
        shelf.recordVideo(provider: "probe", videoID: "1", title: "示例剧", episode: "第 1 集",
                          seconds: 60, duration: 240)
        let entry = try #require(shelf.history.first)
        #expect(entry.isVideo)
        #expect(entry.chapter == "第 1 集")
        #expect(entry.seconds == 60)
        // A quarter in: the same 0–100 the reader's progress bar uses.
        #expect(entry.videoPercent == 25)
        #expect(shelf.recentHistory().count == 1)
    }

    @Test("watching the same episode again moves it to the top instead of duplicating it")
    func replacesRatherThanAppends() throws {
        let shelf = try store()
        shelf.recordVideo(provider: "probe", videoID: "1", title: "示例剧", seconds: 10, duration: 100)
        shelf.recordVideo(provider: "probe", videoID: "2", title: "另一部", seconds: 5, duration: 100)
        shelf.recordVideo(provider: "probe", videoID: "1", title: "示例剧", seconds: 90, duration: 100)
        #expect(shelf.history.count == 2)
        #expect(shelf.history.first?.id == "1")
        #expect(shelf.history.first?.videoPercent == 90)
    }

    @Test("an unknown length leaves the percentage unknown rather than inventing one")
    func unknownDuration() throws {
        let shelf = try store()
        shelf.recordVideo(provider: "probe", videoID: "1", title: "示例剧", seconds: 30, duration: 0)
        #expect(shelf.history.first?.videoPercent == nil)
    }
}

@Suite("Resuming a video")
@MainActor
struct VideoResumeTests {
    private func store() throws -> ShelfStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "shelf-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ShelfStore(directory: root)
    }

    @Test("a watched position is offered, a finished one is not")
    func resumes() throws {
        let shelf = try store()
        shelf.recordVideo(provider: "p", videoID: "a", title: "甲", seconds: 120, duration: 600)
        shelf.recordVideo(provider: "p", videoID: "b", title: "乙", seconds: 595, duration: 600)
        shelf.recordVideo(provider: "p", videoID: "c", title: "丙", seconds: 2, duration: 600)
        #expect(shelf.playbackStart(provider: "p", videoID: "a") == 120)
        // Two minutes before the credits is not a favour.
        #expect(shelf.playbackStart(provider: "p", videoID: "b") == nil)
        // Two seconds in is not a position worth keeping.
        #expect(shelf.playbackStart(provider: "p", videoID: "c") == nil)
        #expect(shelf.playbackStart(provider: "p", videoID: "missing") == nil)
    }
}
