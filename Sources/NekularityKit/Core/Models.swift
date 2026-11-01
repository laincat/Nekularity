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
    /// The token for the next page of a browse that pages by cursor, which has
    /// no page numbers to ask for. Empty means there is no more.
    public var next: String

    public init(sections: [ExploreSection], maxPage: Int, next: String = "") {
        self.sections = sections
        self.maxPage = maxPage
        self.next = next
    }
}

/// What Core returns for one browse page, whatever shape the source declared.
struct ExplorePageWire: Decodable {
    struct Section: Decodable {
        var title: String
        var comics: [JSONValue]
    }

    var sections: [Section]
    var maxPage: Int
    var next: String
}

/// One group of a source's search filters (`search.optionList`).
/// How a source keeps favorites on its own side.
///
/// The shapes differ and do not overlap: nhentai has one folder and no folder
/// list, ehentai has folders but no list function, wnacg has both. A client
/// that guesses calls a function the source does not define.
public struct FavoritesSupport: Sendable, Hashable {
    /// The source keeps favorites at all.
    public var supported: Bool
    /// The source files favorites into folders and expects a folder id.
    public var multiFolder: Bool
    /// The source can list its folders.
    public var folders: Bool
    /// The source can list the comics in a folder.
    public var canLoad: Bool

    public init(supported: Bool, multiFolder: Bool, folders: Bool, canLoad: Bool) {
        self.supported = supported; self.multiFolder = multiFolder
        self.folders = folders; self.canLoad = canLoad
    }

    /// True when there is nothing to show: ehentai offers a toggle but no list.
    public var hasList: Bool { supported && canLoad }
}

/// A login a source performs on its own page.
///
/// The page is data; the two callbacks are named by `handle` inside the
/// source's runtime, because a function cannot cross into JSON. An empty
/// `handle` means the source logs in another way.
public struct WebviewLogin: Decodable, Sendable, Hashable {
    public var url: String
    public var handle: String
    public var callbacks: [String]?

    public init(url: String = "", handle: String = "", callbacks: [String]? = nil) {
        self.url = url
        self.handle = handle
        self.callbacks = callbacks
    }

    /// The source declared a page to log in on.
    public var isDeclared: Bool { !url.isEmpty && !handle.isEmpty }
}

/// How a source logs in.
///
/// Three styles exist among the official sources and they do not overlap:
/// ehentai has no password login at all, only an in-page one and a cookie form,
/// while nhentai offers nothing but the in-page one.
public struct AccountStyles: Codable, Sendable, Hashable {
    public var password: Bool
    public var webview: Bool
    public var cookies: Bool
    public var logout: Bool

    public init(password: Bool, webview: Bool, cookies: Bool, logout: Bool) {
        self.password = password; self.webview = webview
        self.cookies = cookies; self.logout = logout
    }

    public var needsAccount: Bool { password || webview || cookies }
    /// True when the source logs in only on its own page, with no form this
    /// client could draw instead. The page is still usable — `WebviewLoginSession`
    /// runs it — so a caller uses this to explain the flow, not to refuse it.
    public var onlyInPage: Bool { webview && !password && !cookies }
}

/// One dimension of a source's category page.
///
/// A `fixed` part lists values the user picks from. A `random` part is not
/// loaded at all: the interface takes `randomNumber` of its values and runs a
/// search, which is what `itemType: "search"` means.
public struct CategoryPart: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    /// "fixed" or "random"; empty means "fixed".
    public var type: String?
    public var itemType: String?
    public var categories: [String]
    /// One parameter per value when the source maps them; empty otherwise.
    public var params: [String]?
    /// The name a loader expects when it looks up the value by this dimension
    /// rather than by a per-value parameter.
    public var groupParam: String?
    public var randomNumber: Int?

    public var id: String { name }
    public var isRandom: Bool { type == "random" }
    public var searchesInsteadOfLoading: Bool { itemType == "search" }

    /// What `categoryComics.load` receives as its parameter: the per-value
    /// parameter, else the dimension's own name, else the value itself.
    public func param(for value: String) -> String {
        if let params, params.count == categories.count,
           let index = categories.firstIndex(of: value) {
            return params[index]
        }
        if let groupParam, !groupParam.isEmpty { return groupParam }
        return value
    }

    /// The same rule by position, for a caller that has not chosen a value yet
    /// (a tapped tag names a parameter, not a label).
    public func param(forValueAt index: Int) -> String {
        guard categories.indices.contains(index) else { return "" }
        if let params, params.count == categories.count { return params[index] }
        if let groupParam, !groupParam.isEmpty { return groupParam }
        return categories[index]
    }
}

/// One entry of a source's ranking page.
public struct RankingOption: Codable, Sendable, Hashable, Identifiable {
    public var value: String
    public var label: String

    public var id: String { value }
}

/// A source's ranking page: a flat option list and its own loader, separate
/// from the category dimensions.
public struct RankingPage: Codable, Sendable, Hashable {
    public var options: [RankingOption]
}

/// A source's category page: titled dimensions, the option groups its loader
/// takes, and the ranking page when it declares one.
public struct CategoryPage: Codable, Sendable, Hashable {
    public var title: String?
    public var parts: [CategoryPart]
    public var options: [SearchOptionGroup]?
    public var ranking: RankingPage?

    public func paramTarget(for param: String) -> (part: Int, value: Int)? {
        for (partIndex, part) in parts.enumerated() {
            for valueIndex in part.categories.indices
            where part.param(forValueAt: valueIndex) == param {
                return (partIndex, valueIndex)
            }
        }
        return nil
    }
}

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
/// One comment on a comic, as Core normalised it.
///
/// The handlers hang off the source's `comic` object, so a client that looks for
/// a top-level `loadComments` concludes every source keeps no comments.
public struct ComicComment: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var userName: String
    public var avatar: String
    public var content: String
    public var time: String
    public var replyCount: Int
    /// The source's own score, kept as text because sources write numbers,
    /// strings and nothing at all.
    public var score: String
    public var isLiked: Bool

    /// A source may return comments without ids; the position in the page is
    /// the only identity those have, and SwiftUI still needs one.
    var fallbackID: String = ""

    public var identity: String { id.isEmpty ? fallbackID : id }

    enum CodingKeys: String, CodingKey {
        case id, userName, avatar, content, time, replyCount, score, isLiked
    }

    public init(id: String, userName: String, avatar: String = "", content: String,
                time: String = "", replyCount: Int = 0, score: String = "", isLiked: Bool = false) {
        self.id = id
        self.userName = userName
        self.avatar = avatar
        self.content = content
        self.time = time
        self.replyCount = replyCount
        self.score = score
        self.isLiked = isLiked
    }
}

/// The source and comic a pasted address belongs to. Empty fields when no
/// source recognises the link, which is an ordinary "no".
public struct LinkTarget: Decodable, Sendable, Hashable {
    public var key: String
    public var id: String

    public var isEmpty: Bool { key.isEmpty || id.isEmpty }

    public init(key: String, id: String) {
        self.key = key
        self.id = id
    }
}

/// What a source means by tapping one of its own tags.
///
/// The meaning belongs to the source: copy_manga turns an author into a search
/// for "作者:<name>", manhuagui turns a 类型 into a category parameter. An empty
/// action means the source has no opinion, which is different from a failure.
public struct TagAction: Decodable, Sendable, Hashable {
    /// "search" or "category"; empty when the source has no opinion.
    public var action: String
    public var keyword: String
    public var param: String

    public init(action: String, keyword: String = "", param: String = "") {
        self.action = action
        self.keyword = keyword
        self.param = param
    }
}

/// What a source declares about comments.
public struct CommentSupport: Decodable, Sendable, Hashable {
    public var load: Bool
    public var send: Bool
    public var like: Bool

    public init(load: Bool, send: Bool, like: Bool) {
        self.load = load
        self.send = send
        self.like = like
    }
}

/// One page of a thread.
public struct CommentPage: Decodable, Sendable {
    public var comments: [ComicComment]
    public var maxPage: Int

    enum CodingKeys: String, CodingKey { case comments, maxPage }
}

/// One line a source printed, as Core kept it.
///
/// The lines also go to the host's log, which on a phone is a console nobody can
/// open; this is what the client shows instead.
public struct SourceLogEntry: Decodable, Sendable, Hashable, Identifiable {
    /// The source the line came from; empty for Core itself.
    public var key: String
    public var level: String
    public var title: String
    public var content: String
    /// Unix milliseconds.
    public var time: Int64

    public var id: String { "\(time)-\(key)-\(title)-\(content)" }

    public init(key: String, level: String, title: String, content: String, time: Int64) {
        self.key = key
        self.level = level
        self.title = title
        self.content = content
        self.time = time
    }
}

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
    /// What a callback setting wants its button to say; empty when the source
    /// leaves the label to the client.
    public var buttonText: String?

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
    /// The source's own handle on this comic's favorite entry. Six official
    /// sources take it as the fourth argument of favorites.addOrDelFavorite, and
    /// wnacg builds its delete URL from it: without it the removal asks for
    /// "del-id-undefined" and quietly does nothing.
    public var favoriteId: String?

    enum CodingKeys: String, CodingKey { case id, title, subtitle, subTitle, cover, tags, description, favoriteId }

    /// A comic the client knows by id only — a pasted link names an id and
    /// nothing else, and the details screen fills the rest in.
    public init(id: String, title: String = "", subtitle: String? = nil, cover: String? = nil,
                tags: [String] = [], description: String? = nil, favoriteId: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.cover = cover; self.tags = tags
        self.description = description; self.favoriteId = favoriteId
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
        favoriteId = o["favoriteId"]?.stringValue
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
        favoriteId = c.lenientString(.favoriteId)
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
    /// The source's handle on this comic's favorite entry, when loadInfo
    /// reports one; removal needs it on some sources.
    public var favoriteId: String?
    /// The source's secondary identifier for this comic, which some comment
    /// threads are keyed by.
    public var subId: String?
    /// What the source rates this comic, out of five. Core has carried this from
    /// the start; the client simply was not reading it.
    public var stars: Double?
    /// How many readers liked it, when the source counts.
    public var likesCount: Int?
    /// Whether this account already liked it, so a control can show its state.
    public var isLiked: Bool?

    public struct Chapter: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var group: String?
    }

    enum CodingKeys: String, CodingKey {
        case title, subtitle, subTitle, cover, description, tags, chapters, favoriteId, subId,
             stars, likesCount, isLiked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favoriteId = c.lenientString(.favoriteId)
        stars = c.lenientDouble(.stars)
        likesCount = c.lenientInt(.likesCount)
        isLiked = try? c.decodeIfPresent(Bool.self, forKey: .isLiked)
        // A source uses this to place a comment thread under the right work; a
        // declared but undecoded field would mean every thread got "" instead.
        subId = c.lenientString(.subId)
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

    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key) { return Int(s) }
        return nil
    }
}
