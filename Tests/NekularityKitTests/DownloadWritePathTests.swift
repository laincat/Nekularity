import Foundation
import Testing
@testable import NekularityKit

/// The write path with no Core and no network: the store takes the page fetch
/// as a function, so failure, retry and deletion are deterministic here.
@MainActor
@Suite("Download writes, failures and retries")
struct DownloadWritePathTests {
    private let id = "probe|comic|ch1"

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "download-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func request(_ pages: [String], chapterID: String = "ch1") -> DownloadStore.Request {
        .init(sourceKey: "probe", comicID: "comic", comicTitle: "Comic",
              chapterID: chapterID, chapterTitle: "Chapter \(chapterID.dropFirst(2))", pages: pages)
    }

    /// The store completes writes in a Task, so tests wait for the record
    /// rather than sleeping for a guessed duration.
    private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test func pagesAreWrittenAndIndexed() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg", "https://fixture.invalid/2.jpg"]

        store.download(request(pages)) { key in Data(key.url.utf8) }

        #expect(await waitFor { store.progress[id]?.done == 2 })
        #expect(store.chapters[id]?.files.count == 2)
        #expect(store.totalBytes > 0)
        let second = ImageLoader.Key(source: "probe", url: pages[1], comicID: "comic",
                                     chapterID: "ch1", isThumbnail: false)
        #expect(store.bytes(for: second) == Data(pages[1].utf8))
        // The manifest is on disk, so a later launch sees the chapter.
        let reopened = DownloadStore(root: dir)
        #expect(reopened.bytes(for: second) == Data(pages[1].utf8))
    }

    @Test func aFailedAttemptCanBeRetried() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg"]

        store.download(request(pages)) { _ in throw CoreError("upstream failed") }
        #expect(await waitFor { store.progress[id]?.failure != nil })
        #expect(store.chapters[id] == nil)
        #expect(store.isDownloaded(sourceKey: "probe", comicID: "comic", chapterID: "ch1") == false)

        // A failed attempt used to leave its progress record forever, and the
        // chapter could never be asked for again.
        store.download(request(pages)) { key in Data(key.url.utf8) }
        #expect(await waitFor { store.chapters[id] != nil })
        #expect(store.progress[id]?.failure == nil)
        #expect(store.chapters[id]?.files.count == 1)
    }

    @Test func removingADownloadAllowsItAgain() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg"]

        store.download(request(pages)) { key in Data(key.url.utf8) }
        #expect(await waitFor { store.chapters[id] != nil })
        store.remove(sourceKey: "probe", comicID: "comic", chapterID: "ch1")
        #expect(store.progress[id] == nil)
        #expect(store.chapters[id] == nil)

        // The old progress record used to block this second download.
        store.download(request(pages)) { key in Data(key.url.utf8) }
        #expect(await waitFor { store.chapters[id] != nil })
    }

    @Test func twoComicsWritingInParallelKeepTheirOwnPages() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let a = DownloadStore.Request(sourceKey: "probe", comicID: "comic-a", comicTitle: "A",
                                      chapterID: "ch1", chapterTitle: "Chapter 1",
                                      pages: ["https://fixture.invalid/shared.jpg"])
        let b = DownloadStore.Request(sourceKey: "probe", comicID: "comic-b", comicTitle: "B",
                                      chapterID: "ch1", chapterTitle: "Chapter 1",
                                      pages: ["https://fixture.invalid/shared.jpg"])

        store.download(a) { key in
            try await Task.sleep(nanoseconds: 20_000_000)
            return Data("a".utf8)
        }
        store.download(b) { _ in Data("b".utf8) }

        #expect(await waitFor { store.chapters.count == 2 })
        let pageA = ImageLoader.Key(source: "probe", url: "https://fixture.invalid/shared.jpg",
                                    comicID: "comic-a", chapterID: "ch1", isThumbnail: false)
        let pageB = ImageLoader.Key(source: "probe", url: "https://fixture.invalid/shared.jpg",
                                    comicID: "comic-b", chapterID: "ch1", isThumbnail: false)
        #expect(store.bytes(for: pageA) == Data("a".utf8))
        #expect(store.bytes(for: pageB) == Data("b".utf8))
    }

    @Test func removingWhileWritingDoesNotResurrectTheChapter() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg"]

        // A fetch that is still in flight when the chapter is removed.
        store.download(request(pages)) { key in
            try await Task.sleep(nanoseconds: 150_000_000)
            return Data(key.url.utf8)
        }
        #expect(await waitFor { store.active[id] != nil })
        store.remove(sourceKey: "probe", comicID: "comic", chapterID: "ch1")

        // Let the write finish after the removal; it must not add the chapter
        // back, and it must not report a failure the user did not cause.
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(store.chapters[id] == nil)
        #expect(store.progress[id] == nil)
        #expect(store.active[id] == nil)
        let page = ImageLoader.Key(source: "probe", url: pages[0], comicID: "comic",
                                   chapterID: "ch1", isThumbnail: false)
        #expect(store.bytes(for: page) == nil)
        #expect(DownloadStore(root: dir).chapters[id] == nil)
    }

    @Test func clearingStorageStopsPendingAndQueuedDownloads() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg"]

        // Four chapters: two run in parallel and two wait in the queue.
        var ids: [String] = []
        var requests: [DownloadStore.Request] = []
        for number in 1...4 {
            let request = request(pages, chapterID: "ch\(number)")
            ids.append("probe|comic|ch\(number)")
            requests.append(request)
            store.download(request) { key in
                try await Task.sleep(nanoseconds: 150_000_000)
                return Data(key.url.utf8)
            }
        }
        #expect(await waitFor { store.active.count == 2 })

        // Clearing storage must cover chapters that have no record yet, or the
        // running pair writes itself back and the queued pair starts after.
        store.removeAll()
        #expect(store.active.isEmpty)

        try? await Task.sleep(nanoseconds: 500_000_000)
        for id in ids {
            #expect(store.chapters[id] == nil)
            #expect(store.progress[id] == nil)
        }
        #expect(DownloadStore(root: dir).chapters.isEmpty)
    }

    /// Counts fetches so "asked again" is a number rather than a timing guess.
    private final class Fetches: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return count
        }
        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
    }

    @Test func aDownloadedChapterIsNotFetchedAgain() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let pages = ["https://fixture.invalid/1.jpg", "https://fixture.invalid/2.jpg"]
        let fetches = Fetches()

        store.download(request(pages)) { key in
            _ = fetches.next()
            return Data(key.url.utf8)
        }
        #expect(await waitFor { store.chapters[id] != nil })
        #expect(fetches.value == pages.count)

        // The same session must not refetch it.
        store.download(request(pages)) { key in
            _ = fetches.next()
            return Data(key.url.utf8)
        }
        // Neither must a fresh store, which only knows the chapter from the
        // manifest: `progress` is not persisted, so it cannot be the guard.
        DownloadStore(root: dir).download(request(pages)) { key in
            _ = fetches.next()
            return Data(key.url.utf8)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(fetches.value == pages.count)
    }
}
