import Foundation

/// What one Live Activity should be saying, without depending on ActivityKit.
///
/// The kit's tests run on macOS, where ActivityKit does not exist, and the part
/// worth testing is which chapter the island shows — not the framework call.
/// A finished download has no state; a failed one does, because a chapter that
/// silently never arrives is exactly what the failure text exists to explain.
public struct DownloadActivityState: Equatable, Sendable {
    public var id: String
    public var comicTitle: String
    public var chapterTitle: String
    public var done: Int
    public var total: Int
    public var failure: String?

    public var isFailure: Bool { failure != nil }

    public init(id: String, comicTitle: String, chapterTitle: String,
                done: Int, total: Int, failure: String?) {
        self.id = id
        self.comicTitle = comicTitle
        self.chapterTitle = chapterTitle
        self.done = done
        self.total = total
        self.failure = failure
    }
}

/// Chooses the one chapter the island should show. Running chapters come first:
/// a download that is making progress is more useful than an older failure. The
/// chapter already shown stays visible until it finishes or is dismissed, so
/// two downloads do not flip the island back and forth.
public enum DownloadActivitySelection {
    public struct Entry: Equatable, Sendable {
        public var id: String
        public var comicTitle: String
        public var chapterTitle: String
        public var done: Int
        public var total: Int
        public var failure: String?

        public init(id: String, comicTitle: String, chapterTitle: String,
                    done: Int, total: Int, failure: String?) {
            self.id = id
            self.comicTitle = comicTitle
            self.chapterTitle = chapterTitle
            self.done = done
            self.total = total
            self.failure = failure
        }
    }

    public static func select(running: [Entry], failed: [Entry], shown: String?) -> DownloadActivityState? {
        let choose = { (entries: [Entry]) -> Entry? in
            let ids = entries.map { $0.id }
            guard let id = DownloadActivityChoice.chapter(active: ids, shown: shown)
            else { return nil }
            return entries.first { $0.id == id }
        }
        let entry = choose(running) ?? choose(failed)
        guard let entry else { return nil }
        return DownloadActivityState(id: entry.id, comicTitle: entry.comicTitle,
                                     chapterTitle: entry.chapterTitle, done: entry.done,
                                     total: entry.total, failure: entry.failure)
    }
}
