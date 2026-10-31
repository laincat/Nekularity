import Foundation

/// Keeps track of which search is the current one.
///
/// A search takes time, and the user may start another one before the first
/// finishes. The older request then answers with results for a keyword that is
/// no longer on screen, so it must not write into the model. Every search takes
/// a token when it starts and may only write while that token is still current.
@MainActor
public final class SearchGeneration {
    private var current = 0

    public init() {}

    /// Starts a new search and returns its token.
    public func begin() -> Int {
        current += 1
        return current
    }

    /// The token of the current search.
    public var currentToken: Int { current }

    /// Whether the token is still the current search.
    public func isCurrent(_ token: Int) -> Bool { token == current }

    /// Runs the write only when the token is still the current search. This is
    /// how a late answer stays out of the screen.
    public func commit(_ token: Int, _ write: () -> Void) {
        guard isCurrent(token) else { return }
        write()
    }
}
