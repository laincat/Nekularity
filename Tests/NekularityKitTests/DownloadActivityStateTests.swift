import Foundation
import Testing
@testable import NekularityKit

/// The island's state is decided in the kit, so it can be tested on macOS where
/// ActivityKit does not exist. The framework-side call is only an adapter.
@MainActor
@Suite("Download Live Activity state")
struct DownloadActivityStateTests {
    private let id = "probe|comic|ch1"

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "download-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func request(_ pages: [String] = ["https://fixture.invalid/1.jpg"])
        -> DownloadStore.Request {
        .init(sourceKey: "probe", comicID: "comic", comicTitle: "Comic",
              chapterID: "ch1", chapterTitle: "Chapter 1", pages: pages)
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func entry(_ id: String, failure: String? = nil) -> DownloadActivitySelection.Entry {
        .init(id: id, comicTitle: "Comic \(id)", chapterTitle: "Chapter \(id)",
              done: failure == nil ? 1 : 0, total: 3, failure: failure)
    }

    /// `retry` reuses the fetcher saved with the failure, so the first call has
    /// to fail and the next one succeed for that test to mean anything.
    private final class FailFirstFetch: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func shouldFail() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }

    @Test func aRunningChapterWinsOverAnOlderFailure() {
        let state = DownloadActivitySelection.select(
            running: [entry("run")], failed: [entry("fail", failure: "upstream failed")],
            shown: "fail")
        #expect(state?.id == "run")
        #expect(state?.isFailure == false)
    }

    @Test func shownChapterStaysVisibleAmongRunningChapters() {
        let state = DownloadActivitySelection.select(
            running: [entry("a"), entry("b")], failed: [], shown: "b")
        #expect(state?.id == "b")
    }

    @Test func aFailureIsShownWhenNothingIsRunning() {
        let state = DownloadActivitySelection.select(
            running: [], failed: [entry("fail", failure: "upstream failed")], shown: nil)
        #expect(state?.id == "fail")
        #expect(state?.isFailure == true)
        #expect(state?.failure == "upstream failed")
        #expect(state?.total == 3)
    }

    @Test func nothingRunningAndNothingFailedMeansNoActivity() {
        #expect(DownloadActivitySelection.select(running: [], failed: [], shown: nil) == nil)
    }

    /// What used to happen: the failure cleared `active`, the signature became
    /// empty, and the bridge ended the activity without ever showing the failure.
    @Test func aFailedDownloadProducesAFailureStateAndSignature() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)

        store.download(request()) { _ in throw CoreError("upstream failed") }
        #expect(await waitFor { store.failures[self.id] != nil })

        let signature = store.activitySignature
        let failedLine = signature.first { $0.hasPrefix("fail|\(self.id)|") }
        #expect(failedLine != nil)
        #expect(failedLine?.isEmpty == false)

        let state = store.activityState(shown: nil)
        #expect(state?.isFailure == true)
        #expect(state?.comicTitle == "Comic")
        #expect(state?.chapterTitle == "Chapter 1")
        #expect(state?.failure == store.failures[self.id]?.message)
        #expect(state?.failure?.isEmpty == false)
        #expect(failedLine == "fail|\(self.id)|\(state?.failure ?? "")")
        #expect(DownloadProgressText.compact(done: state?.done ?? 0,
                                             total: state?.total ?? 0,
                                             failure: state?.failure) == "失败")
    }

    /// Dismissing or retrying a failure changes the signature, which is the only
    /// thing that makes the view call the bridge again.
    @Test func dismissingAFailureRemovesItsState() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)

        store.download(request()) { _ in throw CoreError("upstream failed") }
        #expect(await waitFor { store.failures[self.id] != nil })
        #expect(store.activityState(shown: nil)?.isFailure == true)

        store.discardFailure(self.id)
        #expect(!store.activitySignature.contains { $0.hasPrefix("fail|") })
        #expect(store.activityState(shown: nil) == nil)
    }

    @Test func retryingAFailureEndsItAndFinishesTheChapter() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(root: dir)
        let once = FailFirstFetch()

        store.download(request()) { key in
            if once.shouldFail() { throw CoreError("upstream failed") }
            return Data(key.url.utf8)
        }
        #expect(await waitFor { store.failures[self.id] != nil })
        let first = store.activitySignature
        #expect(first.contains { $0.hasPrefix("fail|") })

        store.retry(self.id)
        #expect(await waitFor { store.chapters[self.id] != nil })
        #expect(!store.activitySignature.contains { $0.hasPrefix("fail|") })
        #expect(store.activityState(shown: nil) == nil)
        #expect(store.activitySignature != first)
    }
}
