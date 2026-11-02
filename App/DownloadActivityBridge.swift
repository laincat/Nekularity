import ActivityKit
import Foundation
import NekularityKit

/// Keeps one Live Activity in step with whatever is downloading.
///
/// One activity, not one per chapter: the island has room for a single story, and two
/// activities started in a row is a queue of islands the user has to dismiss. The
/// chapter that started first is the one it tells.
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
        let running = downloads.active.sorted { $0.key < $1.key }
        guard let (id, request) = running.first,
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
