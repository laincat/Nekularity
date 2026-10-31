import Foundation

// Codable types for the JSON VeneraCat Core returns. Comic data comes from
// community scripts, so decoding is lenient: a field of the wrong type is
// treated as missing instead of failing the whole page.

/// An installed plugin (Core `plugin.Record` without the script body).
public struct PluginRecord: Codable, Sendable, Hashable, Identifiable {
    public var type: String
    public var key: String
    public var name: String
    public var version: String
    public var origin: String?
    public var indexUrl: String?
    public var enabled: Bool
    public var attribution: Attribution?
    public var warnings: [String]?

    public var id: String { key }
    public var isComic: Bool { type == "comic" }
}

/// Optional author and homepage. Missing values are shown as missing.
public struct Attribution: Codable, Sendable, Hashable {
    public struct Author: Codable, Sendable, Hashable {
        public var name: String
        public var url: String?
    }
    public var authors: [Author]?
    public var homepage: String?
}

/// One entry of a comic source index (`index.json`).
public struct IndexEntry: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var key: String
    public var version: String
    public var url: String
    public var description: String?
    public var minAppVersion: String?
    public var attribution: Attribution?
    public var id: String { key }

    public init(name: String, key: String, version: String, url: String, description: String? = nil,
                minAppVersion: String? = nil, attribution: Attribution? = nil) {
        self.name = name; self.key = key; self.version = version; self.url = url
        self.description = description; self.minAppVersion = minAppVersion; self.attribution = attribution
    }
}

/// An index compared with the installed sources by Core.
public struct ComicIndex: Codable, Sendable {
    public struct Problem: Codable, Sendable, Hashable {
        public var index: Int
        public var key: String?
        public var reason: String
    }

    public struct Row: Codable, Sendable, Hashable, Identifiable {
        public var name: String
        public var key: String
        public var version: String
        public var url: String
        public var description: String?
        public var minAppVersion: String?
        public var attribution: Attribution?
        /// "new", "update", "installed", "other" (installed from another
        /// index) or "too-new" (needs a newer app).
        public var status: String
        public var installedVersion: String?
        public var id: String { key }

        public var entry: IndexEntry {
            IndexEntry(name: name, key: key, version: version, url: url, description: description,
                       minAppVersion: minAppVersion, attribution: attribution)
        }
    }

    public var rows: [Row]
    public var problems: [Problem]?
}

/// One browse a source offers (an entry of its `explore` list).
public struct ExplorePage: Codable, Sendable, Hashable, Identifiable {
    public var title: String
    /// "singlePageWithMultiPart", "multiPartPage", "multiPageComicList" or
    /// "mixed".
    public var type: String
    public var id: String { title + "|" + type }
}

/// A titled group of comics in one browse.
public struct ExploreSection: Sendable, Hashable {
    public var title: String
    public var comics: [Comic]
}

/// What one browse returned.
public struct ExploreResult: Sendable, Hashable {
    public var sections: [ExploreSection]
    /// For "multiPageComicList" browses; 0 when unknown.
    public var maxPage: Int
}

/// One group of a source's search filters (`search.optionList`).
public struct SearchOptionGroup: Codable, Sendable, Hashable {
    public var label: String
    /// "select" or "multi-select"; empty means "select".
    public var type: String?
    public var values: [String]
    public var labels: [String]
    /// The key search.load expects when the user has not chosen.
    public var `default`: String?
    /// The source's declared defaults for a multi-select group.
    public var defaultValues: [String]?

    public var isMultiSelect: Bool { type == "multi-select" }
    public var defaultKey: String { `default` ?? values.first ?? "" }

    /// Multi-select values cross the source API as a JSON array inside one string.
    public var defaultSearchValue: String {
        guard isMultiSelect else { return defaultKey }
        return Self.encodeSelections(defaultValues ?? [])
    }

    public static func encodeSelections(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let result = String(data: data, encoding: .utf8) else { return "[]" }
        return result
    }

    public static func decodeSelections(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

/// One entry of a source's settings declaration: what the source wants drawn
/// in its settings screen.
public struct SourceSetting: Decodable, Sendable, Hashable, Identifiable {
    public var key: String
    public var title: String
    /// "select", "switch", "input" or "callback".
    public var type: String?
    /// The value the source wants when nothing is stored, as JSON text: a
    /// source may declare a number or a boolean.
    public var `default`: JSONValue?
    /// The choices of a select, in the source's order.
    public var options: [SettingOption]?
    /// A regular expression an input's text must match.
    public var validator: String?

    public var id: String { key }

    public var kind: Kind {
        switch type {
        case "switch": .toggle
        case "input": .text
        case "callback": .action
        default: .choice
        }
    }

    public enum Kind: Sendable { case choice, toggle, text, action }

    public struct SettingOption: Decodable, Sendable, Hashable {
        public var value: JSONValue
        public var text: String?
    }
}

/// A comic in a list.
public struct Comic: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var cover: String?
    public var tags: [String]
    public var description: String?

    enum CodingKeys: String, CodingKey { case id, title, subtitle, subTitle, cover, tags, description }

    public init(id: String, title: String, subtitle: String? = nil, cover: String? = nil, tags: [String] = [], description: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.cover = cover; self.tags = tags; self.description = description
    }

    /// Builds a comic from an already parsed value, for browses.
    init(json: JSONValue) throws {
        guard case .object(let o) = json else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a comic"))
        }
        guard let id = o["id"]?.stringValue, !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "comic without id"))
        }
        self.id = id
        title = o["title"]?.stringValue ?? ""
        subtitle = o["subtitle"]?.stringValue ?? o["subTitle"]?.stringValue
        cover = o["cover"]?.stringValue
        tags = o["tags"]?.array?.compactMap(\.stringValue) ?? []
        description = o["description"]?.stringValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "comic without id")
        }
        self.id = id
        title = c.lenientString(.title) ?? ""
        subtitle = c.lenientString(.subtitle) ?? c.lenientString(.subTitle)
        cover = c.lenientString(.cover)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        description = c.lenientString(.description)
    }
}

/// A page of search results: `{comics, maxPage}` or `{comics, next}`.
public struct ComicPage: Decodable, Sendable {
    public var comics: [Comic]
    public var maxPage: Int?
    /// Cursor for sources that page with tokens instead of numbers.
    public var next: String?

    enum CodingKeys: String, CodingKey { case comics, maxPage, next }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One malformed comic must not hide the rest of the page.
        comics = ((try? c.decode([Lenient<Comic>].self, forKey: .comics)) ?? []).compactMap(\.value)
        maxPage = c.lenientInt(.maxPage)
        next = c.lenientString(.next)
    }
}

/// Comic details from `comic.loadInfo`.
public struct ComicDetails: Decodable, Sendable {
    public var title: String
    public var subtitle: String?
    public var cover: String?
    public var description: String?
    /// Tag groups in source order, e.g. 作者 → [..].
    public var tags: [(group: String, values: [String])]
    /// Chapters in reading order. Grouped chapters are flattened, keeping
    /// the group name.
    public var chapters: [Chapter]

    public struct Chapter: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var group: String?
    }

    enum CodingKeys: String, CodingKey { case title, subtitle, subTitle, cover, description, tags, chapters }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenientString(.title) ?? ""
        subtitle = c.lenientString(.subtitle) ?? c.lenientString(.subTitle)
        cover = c.lenientString(.cover)
        description = c.lenientString(.description)

        // Core keeps object keys in the order the script inserted them;
        // OrderedObject preserves that order, which Dictionary would lose.
        tags = []
        if let groups = try? c.decode(OrderedObject.self, forKey: .tags) {
            for (group, value) in groups.entries {
                if case .array(let items) = value {
                    tags.append((group, items.compactMap(\.stringValue)))
                }
            }
        }
        chapters = []
        if let obj = try? c.decode(OrderedObject.self, forKey: .chapters) {
            for (key, value) in obj.entries {
                switch value {
                case .object(let group):
                    // Grouped: {group: {id: title}}.
                    for (id, title) in group.entries {
                        chapters.append(Chapter(id: id, title: title.stringValue ?? id, group: key))
                    }
                default:
                    chapters.append(Chapter(id: key, title: value.stringValue ?? key, group: nil))
                }
            }
        }
    }
}

/// Images of one chapter from `comic.loadEp`.
public struct ChapterImages: Decodable, Sendable {
    public var images: [String]
}

// MARK: - Lenient decoding helpers

struct Lenient<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// A string, or a number written as text. Sources mix both for ids.
    func lenientString(_ key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let n = try? decode(JSONValue.self, forKey: key), case .number(let text) = n { return text }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key) { return Int(s) }
        return nil
    }
}
