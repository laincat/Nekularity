import Foundation

/// Which subtitle language a new episode starts with.
///
/// The engine does not read the system language itself: its preference lists are
/// empty unless the host fills them. So the client decides, in one place: a
/// language the person picked in the player wins, otherwise the system's own
/// language order. "Off" is a choice that is remembered too - someone who turns
/// subtitles off once should not have them reappear on the next episode.
///
/// Tags are reduced to what subtitle renditions declare: an ISO 639 language,
/// with the script kept for Chinese only (`zh-Hans`, `zh-Hant`), because a
/// Traditional track is not an acceptable answer to someone who reads Simplified.
public enum SubtitlePreference: Equatable, Sendable {
    /// Follow the system's language order.
    case system
    /// The person chose this language in the player.
    case language(String)
    /// The person turned subtitles off.
    case off

    /// The stored form: empty for `.system`, `"off"`, or a language tag.
    public var stored: String {
        switch self {
        case .system: return ""
        case .off: return "off"
        case .language(let tag): return tag
        }
    }

    public init(stored: String) {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "": self = .system
        case "off": self = .off
        default: self = .language(Self.normalise(trimmed) ?? trimmed)
        }
    }

    /// The languages to hand the engine, best first. Empty means "start with
    /// subtitles off".
    public func languages(system: [String] = Locale.preferredLanguages) -> [String] {
        switch self {
        case .off: return []
        case .language(let tag): return [tag]
        case .system:
            var seen = Set<String>()
            var result: [String] = []
            for tag in system {
                guard let value = Self.normalise(tag) else { continue }
                if seen.insert(value).inserted { result.append(value) }
            }
            return result
        }
    }

    /// `zh-Hans-CN` → `zh-Hans`, `en-GB` → `en`, `ja` → `ja`. Chinese without a
    /// script is resolved from the region the way the system does: Taiwan, Hong
    /// Kong and Macau read Traditional, everything else Simplified.
    public static func normalise(_ tag: String) -> String? {
        let parts = tag.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased(), !first.isEmpty else { return nil }
        guard first == "zh" else { return first }
        if parts.contains(where: { $0.caseInsensitiveCompare("Hant") == .orderedSame }) { return "zh-Hant" }
        if parts.contains(where: { $0.caseInsensitiveCompare("Hans") == .orderedSame }) { return "zh-Hans" }
        let traditional: Set<String> = ["TW", "HK", "MO"]
        if parts.dropFirst().contains(where: { traditional.contains($0.uppercased()) }) { return "zh-Hant" }
        return parts.count > 1 ? "zh-Hans" : "zh"
    }

    /// The track to start with: the first preferred language some track matches,
    /// by language and (for Chinese) script; nil when nothing matches or the
    /// preference is off. A track tagged plain `zh` matches either script, since
    /// a source that does not say which script is still Chinese.
    public static func pick<Track>(_ tracks: [Track], languages: [String],
                                   language: (Track) -> String?) -> Track? {
        for wanted in languages {
            for track in tracks {
                guard let tag = language(track), let have = normalise(tag) else { continue }
                if matches(have: have, wanted: wanted) { return track }
            }
        }
        return nil
    }

    static func matches(have: String, wanted: String) -> Bool {
        if have == wanted { return true }
        let haveBase = have.split(separator: "-").first.map(String.init) ?? have
        let wantedBase = wanted.split(separator: "-").first.map(String.init) ?? wanted
        guard haveBase == wantedBase else { return false }
        // Same language, different or missing script: only Chinese has scripts
        // here, and an unscripted `zh` on either side is accepted.
        return have == "zh" || wanted == "zh" || haveBase != "zh"
    }
}
