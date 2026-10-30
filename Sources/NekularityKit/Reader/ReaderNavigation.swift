import Foundation

/// Where a reader can move, kept out of the view so it can be tested.
///
/// The rules are small but they are exactly the ones a reader notices when
/// they are wrong: jumping at the end of the book, or jumping before the
/// reader has actually scrolled anywhere.
public enum ReaderNavigation {
    /// Whether there is a chapter before this one.
    public static func canGoPrevious(index: Int) -> Bool {
        index > 0
    }

    /// Whether there is a chapter after this one.
    public static func canGoNext(index: Int, chapterCount: Int) -> Bool {
        index + 1 < chapterCount
    }

    /// The chapter to open after the reader reaches the end of this one, or
    /// `nil` to stay put.
    ///
    /// Staying put is the answer more often than not: auto-continue is off by
    /// default, a single-page chapter is not a scroll, and a reader still on
    /// page one has not scrolled at all. `lastPage` is the highest page the
    /// reader has reached, so it guards against opening a chapter on appear.
    public static func autoNextIndex(autoNext: Bool, pageCount: Int, lastPage: Int,
                                     index: Int, chapterCount: Int) -> Int? {
        guard autoNext, pageCount > 1, lastPage > 1 else { return nil }
        guard canGoNext(index: index, chapterCount: chapterCount) else { return nil }
        return index + 1
    }
}
