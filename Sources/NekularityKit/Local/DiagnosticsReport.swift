import Foundation

/// What a build can say about itself without being asked a question.
///
/// The reason this exists: verifying a real device used to mean "install it and
/// tell me what you see", which produces a screenshot and no facts. A report the
/// user can copy turns that into something checkable — which sources loaded, which
/// accounts are stored, whether the app was even allowed to keep playing in the
/// background.
public struct DiagnosticsReport: Sendable {
    public struct Line: Sendable, Hashable {
        public var title: String
        public var value: String
        /// nil when the line states a fact rather than passing or failing a check.
        public var ok: Bool?

        public init(_ title: String, _ value: String, ok: Bool? = nil) {
            self.title = title
            self.value = value
            self.ok = ok
        }
    }

    public struct Section: Sendable, Hashable, Identifiable {
        public var name: String
        public var lines: [Line]
        public var id: String { name }

        public init(_ name: String, _ lines: [Line]) {
            self.name = name
            self.lines = lines
        }
    }

    public var sections: [Section]
    /// When the report was taken, so a pasted report is not mistaken for a fresh one.
    public var takenAt: Date

    public init(sections: [Section], takenAt: Date = Date()) {
        self.sections = sections
        self.takenAt = takenAt
    }

    /// Plain text, because it is going to be pasted into a message.
    ///
    /// No secrets: this is written to be pasted, so it carries counts, versions and
    /// booleans — never a token, a cookie value or a password.
    public func text() -> String {
        var out = ["Nekularity 自检 · " + Self.stamp(takenAt)]
        for section in sections {
            out.append("")
            out.append("[" + section.name + "]")
            for line in section.lines {
                let mark = line.ok.map { $0 ? "✓ " : "✗ " } ?? "· "
                out.append("  " + mark + line.title + ":" + line.value)
            }
        }
        return out.joined(separator: "\n")
    }

    /// How many checks failed, which is the number a report is read for.
    public var failures: Int {
        sections.flatMap(\.lines).filter { $0.ok == false }.count
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss'Z'"
        return formatter.string(from: date)
    }
}
