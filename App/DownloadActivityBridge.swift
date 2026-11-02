import ActivityKit
import Foundation
import NekularityKit

/// Keeps one Live Activity in step with whatever is downloading.
///
/// One activity, not one per chapter: the island has room for a single story, and two
/// activities started in a row is a queue of islands the user has to dismiss. The
/// chapter that started first is the one it tells.
@MainActor
final class DownloadActivityBridge {
    private var activity: Activity<DownloadActivity>?
    private var shown: String?

    /// Called whenever the download queue changes.
    func sync(_ downloads: DownloadStore) {
        let running = downloads.active.sorted { $0.key < $1.key }
        guard let (id, request) = running.first,
              let progress = downloads.progress[id] else {
            end()
            return
        }

        let state = DownloadActivity.ContentState(done: progress.done,
                                                  total: progress.total,
                                                  failure: progress.failure)
        if let activity, shown == id {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }

        end()
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
    func end() {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
