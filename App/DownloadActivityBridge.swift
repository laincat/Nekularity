// ActivityKit does not annotate `Activity` as Sendable, so awaiting one of its methods
// from the main actor reads to Swift 6 as sending it across isolation domains. The
// framework is thread-safe by design — Apple's own samples call these from anywhere —
// but the annotations are missing, and this is what @preconcurrency is for. It is a
// statement about the framework, not a blanket switch in this file.
@preconcurrency import ActivityKit
import Foundation
import NekularityKit

/// Keeps one Live Activity in step with whatever is downloading.
///
/// One activity, not one per chapter: the island has room for a single story, and two
/// activities started in a row is a queue of islands the user has to dismiss. The
/// chapter already shown stays visible until it finishes.
///
/// Everything here stays on the main actor. Handing an `Activity` to a detached task
/// was rejected under strict concurrency for good reason — it is not `Sendable` — so the
/// updates are awaited where the activity lives instead.
@MainActor
final class DownloadActivityBridge {
    private var activity: Activity<DownloadActivity>?
    private var shown: String?

    /// Called whenever the download queue changes.
    func sync(_ downloads: DownloadStore) async {
        guard let id = DownloadActivityChoice.chapter(active: Array(downloads.active.keys),
                                                      shown: shown),
              let request = downloads.active[id],
              let progress = downloads.progress[id] else {
            await end()
            return
        }

        let state = DownloadActivity.ContentState(done: progress.done,
                                                 total: progress.total,
                                                 failure: progress.failure)
        if let activity, shown == id {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        await end()
        // Authorization is the user's: a denied Live Activity is not an error to show,
        // it is an answer.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DownloadActivity(comicTitle: request.comicTitle,
                                             chapterTitle: request.chapterTitle),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            shown = id
        } catch {
            activity = nil
            shown = nil
        }
    }

    /// Ends the activity. `dismissImmediately` because a finished download is not a
    /// result to dwell on: the chapter is in the library, which is where it belongs.
    func end() async {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
