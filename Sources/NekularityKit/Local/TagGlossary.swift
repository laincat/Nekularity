import Foundation
import Observation

/// Chinese names for the English tags sources use.
///
/// A comic source reports tags in whatever language the site does, and the same
/// tag appears under a dozen spellings. Translating them here is a local table, not
/// a network call: it works offline, costs nothing, and the user can correct it.
/// A tag with no entry is shown exactly as the source wrote it — a wrong
/// translation is worse than an untranslated one, because it is an assertion about
/// the content.
public struct TagGlossary: Sendable {
    /// The built-in table, keyed by normalised form.
    public static let builtin: [String: String] = [
        "school girl": "校服女生",
        "schoolgirl": "校服女生",
        "big breasts": "巨乳",
        "small breasts": "贫乳",
        "huge breasts": "超巨乳",
        "sole female": "仅女性",
        "sole male": "仅男性",
        "sole dickgirl": "仅扶她",
        "glasses": "眼镜",
        "stockings": "丝袜",
        "pantyhose": "连裤袜",
        "thighhighs": "过膝袜",
        "swimsuit": "泳装",
        "school uniform": "校服",
        "miko": "巫女",
        "maid": "女仆",
        "nurse": "护士",
        "teacher": "教师",
        "office lady": "OL",
        "gyaru": "辣妹",
        "milf": "熟女",
        "loli": "萝莉",
        "shota": "正太",
        "futanari": "扶她",
        "yuri": "百合",
        "yaoi": "耽美",
        "femdom": "女攻",
        "maledom": "男攻",
        "vanilla": "纯爱",
        "netorare": "NTR",
        "ntr": "NTR",
        "cheating": "出轨",
        "incest": "近亲",
        "ahegao": "阿黑颜",
        "nakadashi": "内射",
        "creampie": "内射",
        "paizuri": "乳交",
        "bondage": "束缚",
        "sm": "SM",
        "tentacles": "触手",
        "monster": "怪物",
        "elf": "精灵",
        "kemonomimi": "兽耳",
        "catgirl": "猫娘",
        "cosplay": "角色扮演",
        "full color": "全彩",
        "full-colour": "全彩",
        "color": "彩色",
        "webtoon": "条漫",
        "oneshot": "短篇",
        "one shot": "短篇",
        "anthology": "合集",
        "completed": "已完结",
        "ongoing": "连载中",
        "uncensored": "无修正",
        "censored": "有修正",
        "mosaic censorship": "马赛克",
        "english": "英文",
        "chinese": "中文",
        "japanese": "日文",
        "korean": "韩文",
        "translated": "已翻译",
        "language:chinese": "中文",
        "language:english": "英文",
    ]

    /// Lowercased, trimmed, inner whitespace collapsed: `Big  Breasts` and
    /// `big breasts` are the same tag and should not need two entries.
    public static func normalise(_ tag: String) -> String {
        tag.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "_" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The glossary plus the user's own corrections.
@MainActor
@Observable
public final class TagGlossaryStore {
    public private(set) var overrides: [String: String] = [:]
    public private(set) var failure: String?

    private let directory: URL
    private let file: URL

    public init(directory: URL) {
        self.directory = directory
        file = directory.appending(path: "tag-glossary.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = decoded
        } else {
            _ = StoreRescue.keepCopy(of: file)
            failure = "标签翻译表读不出来,旧数据已另存一份"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            failure = "标签翻译表写不进去(\(error.localizedDescription))"
        }
    }

    /// The Chinese name for a tag, or nil when nobody has said what it means.
    public func translation(of tag: String) -> String? {
        let key = TagGlossary.normalise(tag)
        guard !key.isEmpty else { return nil }
        // The user's own entry wins: if they corrected a tag, the table is not
        // allowed to overrule them.
        if let mine = overrides[key], !mine.isEmpty { return mine }
        return TagGlossary.builtin[key]
    }

    /// Shows a tag in Chinese and leaves the original beside it.
    public func label(for tag: String) -> (text: String, translated: Bool) {
        guard let translated = translation(of: tag), translated != tag else {
            return (tag, false)
        }
        return (translated, true)
    }

    public func setTranslation(_ translated: String, for tag: String) {
        let key = TagGlossary.normalise(tag)
        guard !key.isEmpty else { return }
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides[key] = nil
        } else {
            overrides[key] = trimmed
        }
        save()
    }

    public func isOverridden(_ tag: String) -> Bool {
        overrides[TagGlossary.normalise(tag)] != nil
    }

    public var count: Int { overrides.count }
}
