import Foundation

/// Deciding whether the search box holds an address or a keyword.
///
/// It lives in the kit rather than in the screen so it can be tested: the rule
/// decides whether a press spends a round of source calls on a link lookup, and
/// getting it wrong turns every keyword into one.
public enum LinkDetection {
    /// Whether the text is an address one of the sources might claim.
    ///
    /// A dot alone is not enough: "12.5" and "v1.2" have one and must stay
    /// keywords, so the last label has to look like a domain — at least two
    /// characters, all letters.
    public static func looksLikeLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\t") else { return false }
        if trimmed.contains("://") { return true }
        guard let dot = trimmed.lastIndex(of: ".") else { return false }
        var tail = String(trimmed[trimmed.index(after: dot)...])
        if let cut = tail.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            tail = String(tail[..<cut])
        }
        guard tail.count >= 2 else { return false }
        return tail.allSatisfy { $0.isLetter }
    }
}
