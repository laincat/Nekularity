import ActivityKit
import Foundation

/// A chapter being saved, as the Lock Screen and the Dynamic Island see it.
///
/// The attributes are what does not change while the activity runs; the state is what
/// every page changes. Live Activities are a navigation-layer surface like any other,
/// so nothing here draws content — a title, a count and a ring.
public struct DownloadActivity: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var done: Int
        public var total: Int
        public var failure: String?

        public init(done: Int, total: Int, failure: String? = nil) {
            self.done = done
            self.total = total
            self.failure = failure
        }

        public var fraction: Double { DownloadProgressText.fraction(done: done, total: total) }
        public var percent: Int { DownloadProgressText.percent(done: done, total: total) }
        public var compact: String { DownloadProgressText.compact(done: done, total: total, failure: failure) }
        public var detail: String { DownloadProgressText.detail(done: done, total: total, failure: failure) }
        public var isFinished: Bool { failure == nil && total > 0 && done >= total }
    }

    public var comicTitle: String
    public var chapterTitle: String

    public init(comicTitle: String, chapterTitle: String) {
        self.comicTitle = comicTitle
        self.chapterTitle = chapterTitle
    }

    /// The chapter name, cut to what the expanded island can show. A source's chapter
    /// titles are often a sentence, and an island that scrolls is worse than one that
    /// ends in an ellipsis.
    public var shortChapter: String {
        chapterTitle.count <= 18 ? chapterTitle : String(chapterTitle.prefix(17)) + "…"
    }
}
