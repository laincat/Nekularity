import Foundation
import Observation

/// One comment to draw over the picture.
public struct DanmakuComment: Hashable, Sendable, Identifiable {
    /// Seconds from the start of the video.
    public var time: Double
    public var text: String
    /// 1 scrolling, 4 bottom, 5 top — the numbering the format already uses.
    public var mode: Int
    public var color: Int
    public var size: Int

    public var id: String { "\(time)/\(text)" }

    public init(time: Double, text: String, mode: Int = 1, color: Int = 0xFFFFFF, size: Int = 25) {
        self.time = time
        self.text = text
        self.mode = mode
        self.color = color
        self.size = size
    }

    /// Where it sits, as this app draws it: top and bottom are pinned, everything
    /// else scrolls. A format label is not a layout, so it is translated once here
    /// rather than in the view.
    public enum Placement: Sendable { case scroll, top, bottom }

    public var placement: Placement {
        switch mode {
        case 4: .bottom
        case 5: .top
        default: .scroll
        }
    }
}

/// Reads the danmaku formats that exist as files, so no account is needed.
///
/// Bilibili's XML is the one every downloader emits; JSON in DanDanPlay's shape is
/// the other. Reading them is the whole feature that does not require being signed
/// in to somebody's service, so it is the part that is implemented rather than
/// stubbed.
public enum DanmakuParser {
    public static func parse(xml: String) -> [DanmakuComment] {
        // A hand-rolled scan rather than XMLParser: the payload is a flat list of
        // <d> elements and a delegate would be more code for less certainty about
        // order.
        var comments: [DanmakuComment] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<d "), let close = rest.range(of: "</d>", range: open.upperBound..<rest.endIndex) {
            let tag = rest[open.upperBound..<close.lowerBound]
            guard let pStart = tag.range(of: "p=\"") else {
                rest = rest[close.upperBound...]
                continue
            }
            let afterP = tag[pStart.upperBound...]
            guard let pEnd = afterP.firstIndex(of: "\"") else {
                rest = rest[close.upperBound...]
                continue
            }
            let fields = afterP[..<pEnd].split(separator: ",", omittingEmptySubsequences: false)
            // The body starts after the opening tag's own `>`, wherever it is.
            guard let gt = tag.firstIndex(of: ">") else {
                rest = rest[close.upperBound...]
                continue
            }
            let body = decodeEntities(String(tag[tag.index(after: gt)...]))
            rest = rest[close.upperBound...]
            guard fields.count >= 4, let time = Double(fields[0]) else { continue }
            comments.append(DanmakuComment(
                time: time,
                text: body,
                mode: Int(fields[1]) ?? 1,
                color: Int(fields[3]) ?? 0xFFFFFF,
                size: fields.count > 2 ? (Int(fields[2]) ?? 25) : 25))
        }
        return comments.sorted { $0.time < $1.time }
    }

    /// The JSON shape DanDanPlay hands out, so a file from either place works.
    public static func parse(json: String) -> [DanmakuComment] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["comments"] as? [[String: Any]] else { return [] }
        var comments: [DanmakuComment] = []
        for item in list {
            // `p` is "time,mode,colour" in this format; `time` may also be there.
            let p = (item["p"] as? String)?.split(separator: ",").map(String.init) ?? []
            let time = (p.first.flatMap(Double.init)) ?? (item["time"] as? Double) ?? 0
            guard let text = (item["m"] as? String) ?? (item["text"] as? String), !text.isEmpty else { continue }
            comments.append(DanmakuComment(time: time, text: text,
                                           mode: p.count > 1 ? (Int(p[1]) ?? 1) : 1,
                                           color: p.count > 2 ? (Int(p[2]) ?? 0xFFFFFF) : 0xFFFFFF))
        }
        return comments.sorted { $0.time < $1.time }
    }

    /// The comments to draw right now.
    ///
    /// A window rather than "every comment before now": the whole point of a
    /// danmaku list is that it is huge, and filtering the whole array on every
    /// tick is how a phone drops frames.
    public static func active(_ comments: [DanmakuComment], at time: Double,
                              window: Double = 4, limit: Int = 40) -> [DanmakuComment] {
        guard window > 0 else { return [] }
        var shown: [DanmakuComment] = []
        for comment in comments {
            if comment.time > time { break }
            if comment.time > time - window { shown.append(comment) }
        }
        // Newest last, so the newest line is the one nearest the picture.
        return Array(shown.suffix(limit))
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&apos;", "'"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: character)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The opening a user marked once, so the next episode can skip it.
///
/// Not detected: every show's opening is a different length and a guess would skip
/// the first line of dialogue on the ones it got wrong. Marking it once per show
/// is one gesture and cannot be wrong.
public struct IntroMark: Codable, Hashable, Sendable {
    /// Where the opening starts, seconds.
    public var start: Double
    /// Where the episode proper begins, seconds.
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// Whether a position is inside the opening, with a second of slack at the end
    /// so pressing skip at 89.7 s of a 90 s opening still works.
    public func contains(_ position: Double) -> Bool {
        position >= start - 1 && position < end - 1
    }
}

@MainActor
@Observable
public final class IntroStore {
    /// Keyed by the show, not the episode: one opening per show is what a viewer
    /// cares about.
    public private(set) var marks: [String: IntroMark] = [:]
    public private(set) var failure: String?

    private let directory: URL
    private let file: URL

    public init(directory: URL) {
        self.directory = directory
        file = directory.appending(path: "intros.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([String: IntroMark].self, from: data) {
            marks = decoded
        } else {
            failure = "片头标记读不出来,已忽略"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(marks)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            failure = "片头标记写不进去(\(error.localizedDescription))"
        }
    }

    /// A show's key: provider plus title, since two providers may name one show
    /// differently and two shows may share a name across providers.
    public static func key(provider: String, title: String) -> String {
        provider.lowercased() + "/" + title
    }

    public func mark(provider: String, title: String, start: Double, end: Double) {
        guard end > start, start >= 0 else {
            failure = "片头起点要在终点之前"
            return
        }
        marks[Self.key(provider: provider, title: title)] = IntroMark(start: start, end: end)
        save()
    }

    public func mark(provider: String, title: String) -> IntroMark? {
        marks[Self.key(provider: provider, title: title)]
    }

    public func forget(provider: String, title: String) {
        marks[Self.key(provider: provider, title: title)] = nil
        save()
    }
}
