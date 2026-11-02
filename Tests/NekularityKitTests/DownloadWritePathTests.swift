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

    private func request(_ pages: [String]) -> DownloadStore.Request {
        .init(sourceKey: "probe", comicID: "comic", comicTitle: "Comic",
              chapterID: "ch1", chapterTitle: "Chapter 1", pages: pages)
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
}
