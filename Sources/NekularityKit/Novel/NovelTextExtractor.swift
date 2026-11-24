import Foundation

/// Safe plain-text representation of one novel chapter extracted from raw HTML.
public struct NovelChapterDocument: Sendable, Hashable {
    /// Non-empty, whitespace-normalised paragraphs in reading order.
    public var paragraphs: [String]

    public init(paragraphs: [String]) {
        self.paragraphs = paragraphs
    }

    /// Combined plain text with blank-line paragraph breaks.
    public var plainText: String {
        paragraphs.joined(separator: "\n\n")
    }

    /// Total visible character count across all paragraphs.
    public var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.count }
    }

    public var isEmpty: Bool {
        paragraphs.isEmpty
    }
}

/// Converts raw chapter HTML returned by Core's `NovelChapter` into clean
/// plain-text paragraphs without invoking WebKit, JavaScript or network loads.
///
/// Mirrors Core's `novel/adapt.ExtractText` behaviour: dangerous or non-content
/// subtrees (`script`, `style`, `noscript`, `svg`, `iframe`, `template`, `head`)
/// and comments are dropped completely, block elements and `<br>` start new
/// paragraphs, entities are decoded in a single pass, and whitespace is
/// normalised.
public enum NovelTextExtractor {
    private static let skippedTags: Set<String> = [
        "script", "style", "noscript", "svg", "iframe", "template", "head",
    ]

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "blockquote", "li", "tr", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "footer", "aside",
        "main", "pre", "dt", "dd", "figcaption", "table", "ul", "ol",
    ]

    private static let namedEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " ",
        "ensp": " ",
        "emsp": " ",
        "thinsp": " ",
        "mdash": "\u{2014}",
        "ndash": "\u{2013}",
        "hellip": "\u{2026}",
        "ldquo": "\u{201C}",
        "rdquo": "\u{201D}",
        "lsquo": "\u{2018}",
        "rsquo": "\u{2019}",
        "copy": "\u{00A9}",
        "middot": "\u{00B7}",
    ]

    public static func extract(html rawHTML: String) -> NovelChapterDocument {
        NovelChapterDocument(paragraphs: extractParagraphs(html: rawHTML))
    }

    public static func extractPlainText(html rawHTML: String) -> String {
        extract(html: rawHTML).plainText
    }

    public static func extractParagraphs(html rawHTML: String) -> [String] {
        guard !rawHTML.isEmpty else { return [] }
        let scalars = Array(rawHTML.unicodeScalars)
        let count = scalars.count
        var out = ""
        out.reserveCapacity(rawHTML.count)
        var i = 0
        var textStart = 0

        func flushText(upTo end: Int) {
            guard end > textStart else { return }
            let slice = String(String.UnicodeScalarView(scalars[textStart..<end]))
            out.append(decodeEntities(slice))
        }

        while i < count {
            if scalars[i] != "<" {
                i += 1
                continue
            }

            // HTML comment: <!-- ... -->
            if matchesPrefix(scalars, at: i, ascii: "<!--") {
                flushText(upTo: i)
                if let close = findASCII(scalars, from: i + 4, needle: "-->") {
                    i = close + 3
                } else {
                    i = count
                }
                textStart = i
                continue
            }

            // Declaration or processing instruction: <!DOCTYPE ...>, <?xml ...?>
            if i + 1 < count, scalars[i + 1] == "!" || scalars[i + 1] == "?" {
                flushText(upTo: i)
                if let close = findTagEnd(scalars, from: i + 2) {
                    i = close + 1
                } else {
                    i = count
                }
                textStart = i
                continue
            }

            // Opening or closing tag: <tag ...> or </tag>
            let isClosing = (i + 1 < count && scalars[i + 1] == "/")
            let nameStart = isClosing ? i + 2 : i + 1
            guard nameStart < count, isASCIILetter(scalars[nameStart]) else {
                // Stray '<' inside prose (e.g. "a < b"): keep as literal text.
                i += 1
                continue
            }

            var nameEnd = nameStart
            while nameEnd < count, isTagNameScalar(scalars[nameEnd]) {
                nameEnd += 1
            }
            guard let tagEnd = findTagEnd(scalars, from: nameEnd) else {
                // Unterminated tag at EOF: drop the incomplete markup safely.
                flushText(upTo: i)
                i = count
                textStart = i
                break
            }

            flushText(upTo: i)
            let tagName = asciiLowercased(scalars[nameStart..<nameEnd])
            let selfClosing = !isClosing && isSelfClosingTag(scalars, nameEnd: nameEnd, tagEnd: tagEnd)
            i = tagEnd + 1

            if !isClosing && !selfClosing && skippedTags.contains(tagName) {
                i = skipElementBody(scalars, from: i, tagName: tagName)
                textStart = i
                continue
            }

            if tagName == "br" {
                out.append("\n\n")
            } else if blockTags.contains(tagName) {
                out.append("\n\n")
            }
            textStart = i
        }

        flushText(upTo: count)
        return normalizeParagraphs(out)
    }

    // MARK: Scanner helpers

    private static func isASCIILetter(_ s: UnicodeScalar) -> Bool {
        (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122)
    }

    private static func isTagNameScalar(_ s: UnicodeScalar) -> Bool {
        isASCIILetter(s) || (s.value >= 48 && s.value <= 57) || s == "-" || s == ":"
    }

    private static func asciiLowercased(_ slice: ArraySlice<UnicodeScalar>) -> String {
        var result = ""
        result.reserveCapacity(slice.count)
        for s in slice {
            if s.value >= 65 && s.value <= 90, let lower = UnicodeScalar(s.value + 32) {
                result.unicodeScalars.append(lower)
            } else {
                result.unicodeScalars.append(s)
            }
        }
        return result
    }

    private static func matchesPrefix(_ scalars: [UnicodeScalar], at index: Int, ascii: String) -> Bool {
        let needle = Array(ascii.unicodeScalars)
        guard index + needle.count <= scalars.count else { return false }
        for offset in 0..<needle.count where scalars[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    private static func findASCII(_ scalars: [UnicodeScalar], from start: Int, needle: String) -> Int? {
        let target = Array(needle.unicodeScalars)
        guard !target.isEmpty, start + target.count <= scalars.count else { return nil }
        let limit = scalars.count - target.count
        var i = start
        while i <= limit {
            var matched = true
            for offset in 0..<target.count where scalars[i + offset] != target[offset] {
                matched = false
                break
            }
            if matched { return i }
            i += 1
        }
        return nil
    }

    /// Finds the closing `>` of a tag while respecting single/double quoted attributes.
    private static func findTagEnd(_ scalars: [UnicodeScalar], from start: Int) -> Int? {
        var i = start
        var quote: UnicodeScalar?
        while i < scalars.count {
            let s = scalars[i]
            if let q = quote {
                if s == q { quote = nil }
            } else {
                if s == "\"" || s == "'" {
                    quote = s
                } else if s == ">" {
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    private static func isSelfClosingTag(_ scalars: [UnicodeScalar], nameEnd: Int, tagEnd: Int) -> Bool {
        var j = tagEnd - 1
        while j >= nameEnd && (scalars[j] == " " || scalars[j] == "\t" || scalars[j] == "\n" || scalars[j] == "\r") {
            j -= 1
        }
        return j >= nameEnd && scalars[j] == "/"
    }

    /// Advances past the matching `</tagName>` (or EOF if unclosed).
    private static func skipElementBody(_ scalars: [UnicodeScalar], from start: Int, tagName: String) -> Int {
        let count = scalars.count
        var i = start
        let rawText = (tagName == "script" || tagName == "style")
        var depth = 1
        while i < count {
            if scalars[i] == "<" {
                let closing = (i + 1 < count && scalars[i + 1] == "/")
                let nameStart = closing ? i + 2 : i + 1
                if nameStart < count, isASCIILetter(scalars[nameStart]) {
                    var nameEnd = nameStart
                    while nameEnd < count, isTagNameScalar(scalars[nameEnd]) {
                        nameEnd += 1
                    }
                    let candidate = asciiLowercased(scalars[nameStart..<nameEnd])
                    if candidate == tagName {
                        if closing {
                            if let tagEnd = findTagEnd(scalars, from: nameEnd) {
                                depth -= 1
                                i = tagEnd + 1
                                if depth == 0 { return i }
                                continue
                            } else {
                                return count
                            }
                        } else if !rawText {
                            if let tagEnd = findTagEnd(scalars, from: nameEnd) {
                                if !isSelfClosingTag(scalars, nameEnd: nameEnd, tagEnd: tagEnd) {
                                    depth += 1
                                }
                                i = tagEnd + 1
                                continue
                            } else {
                                return count
                            }
                        }
                    }
                }
            }
            i += 1
        }
        return count
    }

    // MARK: Entities and normalisation

    /// Single-pass HTML entity decoder (never double-decodes `&amp;lt;`).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let scalars = Array(text.unicodeScalars)
        let count = scalars.count
        var out = ""
        out.reserveCapacity(text.count)
        var i = 0

        while i < count {
            if scalars[i] != "&" {
                out.unicodeScalars.append(scalars[i])
                i += 1
                continue
            }
            // Scan at most 16 scalars for a terminating ';'.
            let maxEnd = min(count, i + 16)
            var semi: Int?
            var j = i + 1
            while j < maxEnd {
                let s = scalars[j]
                if s == ";" {
                    semi = j
                    break
                }
                if s == "&" || s == " " || s == "\n" || s == "\t" || s == "<" {
                    break
                }
                j += 1
            }
            if let semi, semi > i + 1 {
                let body = String(String.UnicodeScalarView(scalars[(i + 1)..<semi]))
                if let decoded = decodeEntityBody(body) {
                    out.append(decoded)
                    i = semi + 1
                    continue
                }
            }
            out.unicodeScalars.append("&")
            i += 1
        }
        return out
    }

    private static func decodeEntityBody(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let codePoint: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                codePoint = UInt32(digits.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(digits, radix: 10)
            }
            guard let codePoint, codePoint != 0, let scalar = UnicodeScalar(codePoint) else {
                return nil
            }
            return String(Character(scalar))
        }
        return namedEntities[body.lowercased()]
    }

    private static func normalizeParagraphs(_ raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")

        var paragraphs: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let cleaned = collapseSpaces(line)
            if !cleaned.isEmpty {
                paragraphs.append(cleaned)
            }
        }
        return paragraphs
    }

    private static func collapseSpaces(_ slice: Substring) -> String {
        var result = ""
        result.reserveCapacity(slice.count)
        var inSpace = false
        for ch in slice {
            if ch.isWhitespace {
                if !inSpace && !result.isEmpty {
                    result.append(" ")
                    inSpace = true
                }
            } else {
                inSpace = false
                result.append(ch)
            }
        }
        if result.last == " " {
            result.removeLast()
        }
        return result
    }
}

extension NovelChapterContent {
    /// Safely extracts clean plain-text paragraphs from this chapter's raw HTML.
    public func extractedDocument() -> NovelChapterDocument {
        NovelTextExtractor.extract(html: html)
    }
}
