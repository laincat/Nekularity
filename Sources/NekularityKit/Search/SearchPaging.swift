import Foundation

/// Which page a search asks for next, and whether the source pages with a
/// cursor. A source may declare `search.load` (page numbers), `search.loadNext`
/// (an opaque token) or both, so the choice is made once per search and then
/// remembered: asking twice could move the source to a different page.
public struct SearchPaging: Equatable, Sendable {
    /// "page", "cursor" or "unknown" until the first answer decides.
    public enum Mode: String, Equatable, Sendable {
        case page, cursor
    }

    public private(set) var mode: Mode?
    /// 1-based page number for `search.load`; 0 before the first request.
    public private(set) var page = 0
    /// The token to send to `search.loadNext`; nil asks for the first page.
    public private(set) var cursor: String?
    /// The last page number a source reported, or the page it stopped on.
    public private(set) var maxPage: Int?
    /// True once a page failed: paging stops until the search restarts.
    public private(set) var stopped = false

    public init() {}

    /// The page number or cursor to request next. Nil means the search is over.
    public var next: (page: Int, cursor: String?)? {
        guard !stopped else { return nil }
        if mode == .cursor {
            // An empty token is the source saying it has nothing more.
            guard let cursor, !cursor.isEmpty else { return nil }
            return (page: page + 1, cursor: cursor)
        }
        if let maxPage, page >= maxPage { return nil }
        return (page: page + 1, cursor: nil)
    }

    /// Records the answer to a request. `declaresCursor` is the source's own
    /// declaration, read for the first request only: later answers must not
    /// change how the search pages.
    public mutating func record(_ result: ComicPage, declaresCursor: Bool) {
        let mode = self.mode ?? (declaresCursor ? .cursor : .page)
        self.mode = mode
        page = next?.page ?? (page + 1)
        switch mode {
        case .cursor:
            // An empty token is the source saying it has nothing more.
            cursor = result.next
            maxPage = (result.next ?? "").isEmpty ? page : nil
        case .page:
            maxPage = result.maxPage ?? (result.comics.isEmpty ? page : nil)
        }
    }

    /// Records a failure: the search keeps what it has and stops paging.
    public mutating func fail() {
        stopped = true
        maxPage = max(page, 1)
    }
}
