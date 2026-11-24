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

    public static let comicType = "comic"
    public static let videoJSType = "video-js"
    public static let novelJSType = "novel-js"
    public static let kazumiRuleType = "kazumi-rule"
    public static let builtinType = "builtin"

    public var id: String { key }
    public var isComic: Bool { type == Self.comicType }
    public var isNovel: Bool { type == Self.novelJSType }
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

        /// Chapters arrive decoded, but a caller sometimes has to build one: a
        /// downloaded chapter opened from the downloads screen has no comic page
        /// around it to take the list from.
        public init(id: String, title: String, group: String? = nil) {
            self.id = id
            self.title = title
            self.group = group
        }
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

// MARK: - Novel models

/// One novel entry in a popular list or search result (mirrors Core `novel.Item`).
public struct NovelItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var cover: String?
    public var author: String?

    public init(id: String, title: String, cover: String? = nil, author: String? = nil) {
        self.id = id
        self.title = title
        self.cover = cover
        self.author = author
    }

    enum CodingKeys: String, CodingKey { case id, title, cover, author }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        title = c.lenientString(.title) ?? ""
        cover = c.lenientString(.cover)
        author = c.lenientString(.author)
    }
}

/// One page of novel items returned by `NovelPopular` or `NovelSearch` (mirrors Core `novel.Page`).
public struct NovelPage: Codable, Sendable, Hashable {
    public var items: [NovelItem]
    /// 0 when the source did not report a page limit.
    public var maxPage: Int

    public init(items: [NovelItem], maxPage: Int = 0) {
        self.items = items
        self.maxPage = maxPage
    }

    enum CodingKeys: String, CodingKey { case items, maxPage }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([Lenient<NovelItem>].self, forKey: .items))?.compactMap(\.value) ?? []
        maxPage = c.lenientInt(.maxPage) ?? 0
    }
}

/// One chapter entry in a novel's table of contents (mirrors Core `novel.Chapter`).
public struct NovelChapter: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var time: String?

    public init(id: String, title: String, time: String? = nil) {
        self.id = id
        self.title = title
        self.time = time
    }

    enum CodingKeys: String, CodingKey { case id, title, time }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        title = c.lenientString(.title) ?? ""
        time = c.lenientString(.time)
    }
}

/// Metadata and chapter list returned by `NovelDetail` (mirrors Core `novel.Detail`).
public struct NovelDetail: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var cover: String?
    public var author: String?
    public var summary: String?
    public var status: String?
    public var tags: [String]
    public var chapters: [NovelChapter]

    public init(
        id: String,
        title: String,
        cover: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        status: String? = nil,
        tags: [String] = [],
        chapters: [NovelChapter] = []
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.author = author
        self.summary = summary
        self.status = status
        self.tags = tags
        self.chapters = chapters
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cover, author, summary, status, tags, chapters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        title = c.lenientString(.title) ?? ""
        cover = c.lenientString(.cover)
        author = c.lenientString(.author)
        summary = c.lenientString(.summary)
        status = c.lenientString(.status)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        chapters = (try? c.decodeIfPresent([Lenient<NovelChapter>].self, forKey: .chapters))?.compactMap(\.value) ?? []
    }
}

/// Raw chapter HTML returned by `NovelChapter` (mirrors Core `novel.ChapterContent`).
///
/// Core returns the HTML verbatim without altering it; sanitisation and
/// plain-text paragraph extraction happen in `NovelTextExtractor`.
public struct NovelChapterContent: Codable, Sendable, Hashable {
    public var html: String

    public init(html: String) {
        self.html = html
    }

    enum CodingKeys: String, CodingKey { case html }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        html = (try? c.decodeIfPresent(String.self, forKey: .html)) ?? ""
    }
}

// MARK: - Shared source collection models

/// Shared cross-platform source collection (mirrors Core `subscription.Collection`).
public struct SourceCollection: Codable, Sendable, Hashable, Identifiable {
    public static let schema = "veneracat-source/1-draft"
    public static let capabilityComicJS = "comic-source.js"
    public static let capabilityVideoJS = "video-source.js"
    public static let capabilityNovelJS = "novel-source.js"
    public static let defaultCapabilities: [String] = [
        capabilityComicJS,
        capabilityVideoJS,
        capabilityNovelJS,
    ]

    public struct Support: Codable, Sendable, Hashable {
        public var platforms: [String]
        public var requiresCapabilities: [String]

        public init(platforms: [String], requiresCapabilities: [String]) {
            self.platforms = platforms
            self.requiresCapabilities = requiresCapabilities
        }
    }

    public struct Artifact: Codable, Sendable, Hashable {
        public var url: String
        public var sha256: String
        public var bytes: Int64

        public init(url: String, sha256: String, bytes: Int64) {
            self.url = url
            self.sha256 = sha256
            self.bytes = bytes
        }
    }

    public struct Design: Codable, Sendable, Hashable {
        public var url: String
        public var sha256: String

        public init(url: String, sha256: String) {
            self.url = url
            self.sha256 = sha256
        }
    }

    public struct Entry: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var kind: String
        public var name: String
        public var version: String
        public var status: String
        public var key: String?
        public var license: String?
        public var supports: Support
        public var artifact: Artifact?
        public var design: Design?

        public init(
            id: String,
            kind: String,
            name: String,
            version: String,
            status: String,
            key: String? = nil,
            license: String? = nil,
            supports: Support,
            artifact: Artifact? = nil,
            design: Design? = nil
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.version = version
            self.status = status
            self.key = key
            self.license = license
            self.supports = supports
            self.artifact = artifact
            self.design = design
        }

        /// Maps a collection entry kind or capability requirement onto Core's
        /// `plugin.Type` string, or nil when this client cannot install it.
        public var pluginType: String? {
            switch kind {
            case PluginRecord.comicType, "comic-source", SourceCollection.capabilityComicJS:
                return PluginRecord.comicType
            case PluginRecord.videoJSType, "video-source", SourceCollection.capabilityVideoJS:
                return PluginRecord.videoJSType
            case PluginRecord.novelJSType, "novel-source", SourceCollection.capabilityNovelJS:
                return PluginRecord.novelJSType
            case PluginRecord.kazumiRuleType:
                return PluginRecord.kazumiRuleType
            default:
                if supports.requiresCapabilities.contains(SourceCollection.capabilityNovelJS) {
                    return PluginRecord.novelJSType
                }
                return nil
            }
        }

        public var isInstallable: Bool {
            status != "planned" && artifact != nil && pluginType != nil
        }

        /// Evaluates platform and capability compatibility locally (mirroring Core's rule).
        public func compatibility(
            platform: String = "ios",
            capabilities: [String] = SourceCollection.defaultCapabilities
        ) -> SourceCollectionCompatibility {
            var missing: [String] = []
            if !supports.platforms.contains(platform) {
                missing.append("platform:\(platform)")
            }
            let available = Set(capabilities)
            for capability in supports.requiresCapabilities where !available.contains(capability) {
                missing.append(capability)
            }
            return SourceCollectionCompatibility(id: id, compatible: missing.isEmpty, missing: missing)
        }
    }

    public var schema: String
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case id, name, version, description, entries
    }

    public init(
        schema: String = SourceCollection.schema,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        entries: [Entry]
    ) {
        self.schema = schema
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.entries = entries
    }
}

/// Compatibility report for one entry in a `SourceCollection`.
public struct SourceCollectionCompatibility: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var compatible: Bool
    public var missing: [String]

    public init(id: String, compatible: Bool, missing: [String] = []) {
        self.id = id
        self.compatible = compatible
        self.missing = missing
    }

    enum CodingKeys: String, CodingKey { case id, compatible, missing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        compatible = try c.decode(Bool.self, forKey: .compatible)
        missing = (try? c.decodeIfPresent([String].self, forKey: .missing)) ?? []
    }
}

/// Core's `ParseSourceCollection` output: parsed collection plus per-entry compatibility rows.
public struct SourceCollectionCheck: Codable, Sendable, Hashable {
    public var collection: SourceCollection
    public var compatibility: [SourceCollectionCompatibility]

    public init(collection: SourceCollection, compatibility: [SourceCollectionCompatibility]) {
        self.collection = collection
        self.compatibility = compatibility
    }

    public func compatibility(for entryID: String) -> SourceCollectionCompatibility? {
        compatibility.first { $0.id == entryID }
    }

    public func isCompatible(_ entryID: String) -> Bool {
        compatibility(for: entryID)?.compatible == true
    }

    public var compatibleEntries: [SourceCollection.Entry] {
        let allowed = Set(compatibility.filter(\.compatible).map(\.id))
        return collection.entries.filter { allowed.contains($0.id) }
    }
}

// MARK: - Novel adaptation models (Wave 4B)

/// Rendering state of one storyboard panel (mirrors Core `adapt.ImageStatus`).
public enum AdaptImageStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pending
    case generating
    case done
    case failed
}

/// Purpose of a reference image passed to Core's image renderer (mirrors Core `adapt.ImageRefKind`).
public enum AdaptImageRefKind: String, Codable, Sendable, Hashable, CaseIterable {
    case style
    case character
}

/// Supported static comic image providers in Core `mobile/adapt.go`.
public enum AdaptImageProvider: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case gemini
    case openai

    public var id: String { rawValue }
}

/// Machine-readable error codes returned by Core `mobile/adapt.go` on partial or failed runs.
public enum AdaptErrorCode: String, Codable, Sendable, Hashable, CaseIterable {
    case budgetExceeded = "budget_exceeded"
    case contentBlocked = "content_blocked"
    case invalidStoryboard = "invalid_storyboard"
    case emptyChapter = "empty_chapter"
    case canceled = "canceled"
    case deadlineExceeded = "deadline_exceeded"
    case error = "error"

    /// Human-readable Chinese description for UI display.
    public var readableMessage: String {
        switch self {
        case .budgetExceeded:
            "已达到改编预算上限,可在提高预算后从断点继续"
        case .contentBlocked:
            "该分镜画面触发了模型内容安全拦截,可调整提示词后重试"
        case .invalidStoryboard:
            "模型返回的分镜 JSON 格式无效,请重试或更换模型"
        case .emptyChapter:
            "章节正文为空,无法生成分镜"
        case .canceled:
            "操作已取消"
        case .deadlineExceeded:
            "网络超时,请稍后重试"
        case .error:
            "改编处理失败,请稍后重试"
        }
    }
}

/// Reference image passed inline to Core's image renderer (mirrors Core `adaptImageRefWire`).
public struct AdaptImageRef: Codable, Sendable, Hashable {
    public var id: String?
    public var kind: AdaptImageRefKind?
    public var label: String?
    public var mimeType: String?
    public var dataBase64: String?

    public init(
        id: String? = nil,
        kind: AdaptImageRefKind? = nil,
        label: String? = nil,
        mimeType: String? = nil,
        dataBase64: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
    }

    public init(
        id: String? = nil,
        kind: AdaptImageRefKind? = nil,
        label: String? = nil,
        mimeType: String? = nil,
        data: Data
    ) {
        self.init(
            id: id,
            kind: kind,
            label: label,
            mimeType: mimeType,
            dataBase64: data.isEmpty ? nil : data.base64EncodedString()
        )
    }

    /// Decoded raw image bytes when `dataBase64` is valid base64.
    public var decodedData: Data? {
        guard let dataBase64, !dataBase64.isEmpty else { return nil }
        return Data(base64Encoded: dataBase64)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, label, mimeType, dataBase64, data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        kind = try c.decodeIfPresent(AdaptImageRefKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        if let b64 = try c.decodeIfPresent(String.self, forKey: .dataBase64), !b64.isEmpty {
            dataBase64 = b64
        } else {
            dataBase64 = try c.decodeIfPresent(String.self, forKey: .data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        try c.encodeIfPresent(dataBase64, forKey: .dataBase64)
    }
}

/// Local comic style reference metadata (mirrors Core `adapt.StyleRef`).
public struct AdaptStyleRef: Codable, Sendable, Hashable {
    public var comicSourceKey: String?
    public var comicID: String?
    public var comicTitle: String?
    public var referencePageIDs: [String]
    public var styleNotes: String?

    public init(
        comicSourceKey: String? = nil,
        comicID: String? = nil,
        comicTitle: String? = nil,
        referencePageIDs: [String] = [],
        styleNotes: String? = nil
    ) {
        self.comicSourceKey = comicSourceKey
        self.comicID = comicID
        self.comicTitle = comicTitle
        self.referencePageIDs = referencePageIDs
        self.styleNotes = styleNotes
    }

    enum CodingKeys: String, CodingKey {
        case comicSourceKey
        case comicID = "comicId"
        case comicTitle
        case referencePageIDs = "referencePageIds"
        case styleNotes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comicSourceKey = try c.decodeIfPresent(String.self, forKey: .comicSourceKey)
        comicID = try c.decodeIfPresent(String.self, forKey: .comicID)
        comicTitle = try c.decodeIfPresent(String.self, forKey: .comicTitle)
        referencePageIDs = (try? c.decodeIfPresent([String].self, forKey: .referencePageIDs)) ?? []
        styleNotes = try c.decodeIfPresent(String.self, forKey: .styleNotes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(comicSourceKey, forKey: .comicSourceKey)
        try c.encodeIfPresent(comicID, forKey: .comicID)
        try c.encodeIfPresent(comicTitle, forKey: .comicTitle)
        if !referencePageIDs.isEmpty {
            try c.encode(referencePageIDs, forKey: .referencePageIDs)
        }
        try c.encodeIfPresent(styleNotes, forKey: .styleNotes)
    }
}

/// Cross-chapter character identity (mirrors Core `adapt.Character`).
public struct AdaptCharacter: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var appearance: String?
    public var outfit: String?
    public var traits: [String]
    public var firstChapterID: String?
    public var notes: String?

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        appearance: String? = nil,
        outfit: String? = nil,
        traits: [String] = [],
        firstChapterID: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.appearance = appearance
        self.outfit = outfit
        self.traits = traits
        self.firstChapterID = firstChapterID
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, appearance, outfit, traits
        case firstChapterID = "firstChapterId"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        aliases = (try? c.decodeIfPresent([String].self, forKey: .aliases)) ?? []
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance)
        outfit = try c.decodeIfPresent(String.self, forKey: .outfit)
        traits = (try? c.decodeIfPresent([String].self, forKey: .traits)) ?? []
        firstChapterID = try c.decodeIfPresent(String.self, forKey: .firstChapterID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
        try c.encodeIfPresent(appearance, forKey: .appearance)
        try c.encodeIfPresent(outfit, forKey: .outfit)
        if !traits.isEmpty { try c.encode(traits, forKey: .traits) }
        try c.encodeIfPresent(firstChapterID, forKey: .firstChapterID)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

/// Canonical character roster of an `AdaptProject` (mirrors Core `adapt.CharacterSheet`).
public struct AdaptCharacterSheet: Codable, Sendable, Hashable {
    public var characters: [AdaptCharacter]

    public init(characters: [AdaptCharacter] = []) {
        self.characters = characters
    }

    enum CodingKeys: String, CodingKey { case characters }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characters = (try? c.decodeIfPresent([AdaptCharacter].self, forKey: .characters)) ?? []
    }
}

/// One dialogue, thought, narration, or SFX line in a panel (mirrors Core `adapt.Dialogue`).
public struct AdaptDialogue: Codable, Sendable, Hashable {
    public var speaker: String?
    public var text: String
    public var kind: String?

    public init(speaker: String? = nil, text: String, kind: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey { case speaker, text, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
    }
}

/// Single static comic frame inside a scene (mirrors Core `adapt.Panel`).
public struct AdaptPanel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var shot: String
    public var action: String
    public var characters: [String]
    public var dialogues: [AdaptDialogue]
    public var prompt: String
    public var imageStatus: AdaptImageStatus
    public var imageRefID: String?
    public var imageError: String?

    public init(
        id: String,
        shot: String,
        action: String,
        characters: [String] = [],
        dialogues: [AdaptDialogue] = [],
        prompt: String,
        imageStatus: AdaptImageStatus = .pending,
        imageRefID: String? = nil,
        imageError: String? = nil
    ) {
        self.id = id
        self.shot = shot
        self.action = action
        self.characters = characters
        self.dialogues = dialogues
        self.prompt = prompt
        self.imageStatus = imageStatus
        self.imageRefID = imageRefID
        self.imageError = imageError
    }

    enum CodingKeys: String, CodingKey {
        case id, shot, action, characters, dialogues, prompt, imageStatus
        case imageRefID = "imageRefId"
        case imageError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        shot = (try? c.decodeIfPresent(String.self, forKey: .shot)) ?? ""
        action = (try? c.decodeIfPresent(String.self, forKey: .action)) ?? ""
        characters = (try? c.decodeIfPresent([String].self, forKey: .characters)) ?? []
        dialogues = (try? c.decodeIfPresent([AdaptDialogue].self, forKey: .dialogues)) ?? []
        prompt = (try? c.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
        imageStatus = (try? c.decodeIfPresent(AdaptImageStatus.self, forKey: .imageStatus)) ?? .pending
        imageRefID = try c.decodeIfPresent(String.self, forKey: .imageRefID)
        imageError = try c.decodeIfPresent(String.self, forKey: .imageError)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(shot, forKey: .shot)
        try c.encode(action, forKey: .action)
        if !characters.isEmpty { try c.encode(characters, forKey: .characters) }
        if !dialogues.isEmpty { try c.encode(dialogues, forKey: .dialogues) }
        try c.encode(prompt, forKey: .prompt)
        try c.encode(imageStatus, forKey: .imageStatus)
        try c.encodeIfPresent(imageRefID, forKey: .imageRefID)
        try c.encodeIfPresent(imageError, forKey: .imageError)
    }
}

/// Group of consecutive panels sharing a location and mood (mirrors Core `adapt.Scene`).
public struct AdaptScene: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var setting: String
    public var mood: String?
    public var panels: [AdaptPanel]

    public init(id: String, setting: String, mood: String? = nil, panels: [AdaptPanel] = []) {
        self.id = id
        self.setting = setting
        self.mood = mood
        self.panels = panels
    }

    enum CodingKeys: String, CodingKey { case id, setting, mood, panels }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        setting = (try? c.decodeIfPresent(String.self, forKey: .setting)) ?? ""
        mood = try c.decodeIfPresent(String.self, forKey: .mood)
        panels = (try? c.decodeIfPresent([AdaptPanel].self, forKey: .panels)) ?? []
    }
}

/// Adapted panel script for one novel chapter (mirrors Core `adapt.Storyboard`).
public struct AdaptStoryboard: Codable, Sendable, Hashable {
    public var chapterID: String
    public var chapterTitle: String?
    public var scenes: [AdaptScene]

    public init(chapterID: String, chapterTitle: String? = nil, scenes: [AdaptScene] = []) {
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.scenes = scenes
    }

    /// Total number of panels across all scenes in this chapter.
    public var panelCount: Int {
        scenes.reduce(0) { $0 + $1.panels.count }
    }

    /// Number of panels whose `imageStatus` is `.done`.
    public var donePanelCount: Int {
        scenes.reduce(0) { total, scene in
            total + scene.panels.filter { $0.imageStatus == .done }.count
        }
    }

    enum CodingKeys: String, CodingKey {
        case chapterID = "chapterId"
        case chapterTitle, scenes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = (try? c.decodeIfPresent(String.self, forKey: .chapterID)) ?? ""
        chapterTitle = try c.decodeIfPresent(String.self, forKey: .chapterTitle)
        scenes = (try? c.decodeIfPresent([AdaptScene].self, forKey: .scenes)) ?? []
    }
}

/// Spending caps enforced by Core before every text/image generation call (mirrors Core `adapt.Budget`).
/// Zero fields mean unlimited.
public struct AdaptBudget: Codable, Sendable, Hashable {
    public var maxCalls: Int64
    public var maxImageCalls: Int64
    public var maxInputTokens: Int64
    public var maxOutputTokens: Int64
    public var maxTotalTokens: Int64

    public init(
        maxCalls: Int64 = 0,
        maxImageCalls: Int64 = 0,
        maxInputTokens: Int64 = 0,
        maxOutputTokens: Int64 = 0,
        maxTotalTokens: Int64 = 0
    ) {
        self.maxCalls = maxCalls
        self.maxImageCalls = maxImageCalls
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.maxTotalTokens = maxTotalTokens
    }

    enum CodingKeys: String, CodingKey {
        case maxCalls, maxImageCalls, maxInputTokens, maxOutputTokens, maxTotalTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxCalls = (try? c.decodeIfPresent(Int64.self, forKey: .maxCalls)) ?? 0
        maxImageCalls = (try? c.decodeIfPresent(Int64.self, forKey: .maxImageCalls)) ?? 0
        maxInputTokens = (try? c.decodeIfPresent(Int64.self, forKey: .maxInputTokens)) ?? 0
        maxOutputTokens = (try? c.decodeIfPresent(Int64.self, forKey: .maxOutputTokens)) ?? 0
        maxTotalTokens = (try? c.decodeIfPresent(Int64.self, forKey: .maxTotalTokens)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if maxCalls > 0 { try c.encode(maxCalls, forKey: .maxCalls) }
        if maxImageCalls > 0 { try c.encode(maxImageCalls, forKey: .maxImageCalls) }
        if maxInputTokens > 0 { try c.encode(maxInputTokens, forKey: .maxInputTokens) }
        if maxOutputTokens > 0 { try c.encode(maxOutputTokens, forKey: .maxOutputTokens) }
        if maxTotalTokens > 0 { try c.encode(maxTotalTokens, forKey: .maxTotalTokens) }
    }
}

/// Cumulative generator calls and token counts (mirrors Core `adapt.Usage`).
public struct AdaptUsage: Codable, Sendable, Hashable {
    public var calls: Int64
    public var imageCalls: Int64
    public var inputTokens: Int64
    public var outputTokens: Int64
    public var totalTokens: Int64

    public init(
        calls: Int64 = 0,
        imageCalls: Int64 = 0,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        totalTokens: Int64 = 0
    ) {
        self.calls = calls
        self.imageCalls = imageCalls
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case calls, imageCalls, inputTokens, outputTokens, totalTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calls = (try? c.decodeIfPresent(Int64.self, forKey: .calls)) ?? 0
        imageCalls = (try? c.decodeIfPresent(Int64.self, forKey: .imageCalls)) ?? 0
        inputTokens = (try? c.decodeIfPresent(Int64.self, forKey: .inputTokens)) ?? 0
        outputTokens = (try? c.decodeIfPresent(Int64.self, forKey: .outputTokens)) ?? 0
        totalTokens = (try? c.decodeIfPresent(Int64.self, forKey: .totalTokens)) ?? 0
    }
}

/// Serialisable adaptation workspace for one novel (mirrors Core `adapt.Project`).
public struct AdaptProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var novelSourceKey: String?
    public var novelID: String?
    public var title: String
    public var styleRef: AdaptStyleRef?
    public var characters: AdaptCharacterSheet
    public var storyboards: [String: AdaptStoryboard]
    public var budget: AdaptBudget
    public var usage: AdaptUsage

    public init(
        id: String,
        novelSourceKey: String? = nil,
        novelID: String? = nil,
        title: String,
        styleRef: AdaptStyleRef? = nil,
        characters: AdaptCharacterSheet = AdaptCharacterSheet(),
        storyboards: [String: AdaptStoryboard] = [:],
        budget: AdaptBudget = AdaptBudget(),
        usage: AdaptUsage = AdaptUsage()
    ) {
        self.id = id
        self.novelSourceKey = novelSourceKey
        self.novelID = novelID
        self.title = title
        self.styleRef = styleRef
        self.characters = characters
        self.storyboards = storyboards
        self.budget = budget
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case id, novelSourceKey
        case novelID = "novelId"
        case title, styleRef, characters, storyboards, budget, usage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        novelSourceKey = try c.decodeIfPresent(String.self, forKey: .novelSourceKey)
        novelID = try c.decodeIfPresent(String.self, forKey: .novelID)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        styleRef = try c.decodeIfPresent(AdaptStyleRef.self, forKey: .styleRef)
        characters = (try? c.decodeIfPresent(AdaptCharacterSheet.self, forKey: .characters)) ?? AdaptCharacterSheet()
        if let rawMap = try? c.decodeIfPresent([String: AdaptStoryboard?].self, forKey: .storyboards) {
            storyboards = rawMap.compactMapValues { $0 }
        } else {
            storyboards = [:]
        }
        budget = (try? c.decodeIfPresent(AdaptBudget.self, forKey: .budget)) ?? AdaptBudget()
        usage = (try? c.decodeIfPresent(AdaptUsage.self, forKey: .usage)) ?? AdaptUsage()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(novelSourceKey, forKey: .novelSourceKey)
        try c.encodeIfPresent(novelID, forKey: .novelID)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(styleRef, forKey: .styleRef)
        try c.encode(characters, forKey: .characters)
        if !storyboards.isEmpty { try c.encode(storyboards, forKey: .storyboards) }
        try c.encode(budget, forKey: .budget)
        try c.encode(usage, forKey: .usage)
    }
}

/// Resumable multi-chunk chapter adaptation state (mirrors Core `adapt.AdaptCheckpoint`).
public struct AdaptCheckpoint: Codable, Sendable, Hashable {
    public var chapterID: String
    public var chapterTitle: String?
    public var totalChunks: Int
    public var completedChunks: Int
    public var maxChunkRunes: Int
    public var storyboard: AdaptStoryboard?
    public var characters: AdaptCharacterSheet
    public var addedCharacters: [AdaptCharacter]
    public var usage: AdaptUsage
    public var sceneSeq: Int
    public var panelSeq: Int

    public init(
        chapterID: String,
        chapterTitle: String? = nil,
        totalChunks: Int,
        completedChunks: Int,
        maxChunkRunes: Int = 0,
        storyboard: AdaptStoryboard? = nil,
        characters: AdaptCharacterSheet = AdaptCharacterSheet(),
        addedCharacters: [AdaptCharacter] = [],
        usage: AdaptUsage = AdaptUsage(),
        sceneSeq: Int = 0,
        panelSeq: Int = 0
    ) {
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.totalChunks = totalChunks
        self.completedChunks = completedChunks
        self.maxChunkRunes = maxChunkRunes
        self.storyboard = storyboard
        self.characters = characters
        self.addedCharacters = addedCharacters
        self.usage = usage
        self.sceneSeq = sceneSeq
        self.panelSeq = panelSeq
    }

    enum CodingKeys: String, CodingKey {
        case chapterID = "chapterId"
        case chapterTitle, totalChunks, completedChunks, maxChunkRunes
        case storyboard, characters, addedCharacters, usage, sceneSeq, panelSeq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = (try? c.decodeIfPresent(String.self, forKey: .chapterID)) ?? ""
        chapterTitle = try c.decodeIfPresent(String.self, forKey: .chapterTitle)
        totalChunks = (try? c.decodeIfPresent(Int.self, forKey: .totalChunks)) ?? 0
        completedChunks = (try? c.decodeIfPresent(Int.self, forKey: .completedChunks)) ?? 0
        maxChunkRunes = (try? c.decodeIfPresent(Int.self, forKey: .maxChunkRunes)) ?? 0
        storyboard = try c.decodeIfPresent(AdaptStoryboard.self, forKey: .storyboard)
        characters = (try? c.decodeIfPresent(AdaptCharacterSheet.self, forKey: .characters)) ?? AdaptCharacterSheet()
        addedCharacters = (try? c.decodeIfPresent([AdaptCharacter].self, forKey: .addedCharacters)) ?? []
        usage = (try? c.decodeIfPresent(AdaptUsage.self, forKey: .usage)) ?? AdaptUsage()
        sceneSeq = (try? c.decodeIfPresent(Int.self, forKey: .sceneSeq)) ?? 0
        panelSeq = (try? c.decodeIfPresent(Int.self, forKey: .panelSeq)) ?? 0
    }
}

/// Chunking and checkpoint resume options (mirrors Core `adapt.AdaptOptions`).
public struct AdaptOptions: Codable, Sendable, Hashable {
    public var maxChunkRunes: Int?
    public var checkpoint: AdaptCheckpoint?

    public init(maxChunkRunes: Int? = nil, checkpoint: AdaptCheckpoint? = nil) {
        self.maxChunkRunes = maxChunkRunes
        self.checkpoint = checkpoint
    }
}

/// Chapter adaptation summary (mirrors Core `adapt.AdaptResult`).
public struct AdaptResult: Codable, Sendable, Hashable {
    public var storyboard: AdaptStoryboard?
    public var addedCharacters: [AdaptCharacter]
    public var chunks: Int
    public var completedChunks: Int
    public var usage: AdaptUsage
    public var checkpoint: AdaptCheckpoint?

    public init(
        storyboard: AdaptStoryboard? = nil,
        addedCharacters: [AdaptCharacter] = [],
        chunks: Int = 0,
        completedChunks: Int = 0,
        usage: AdaptUsage = AdaptUsage(),
        checkpoint: AdaptCheckpoint? = nil
    ) {
        self.storyboard = storyboard
        self.addedCharacters = addedCharacters
        self.chunks = chunks
        self.completedChunks = completedChunks
        self.usage = usage
        self.checkpoint = checkpoint
    }

    enum CodingKeys: String, CodingKey {
        case storyboard, addedCharacters, chunks, completedChunks, usage, checkpoint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storyboard = try c.decodeIfPresent(AdaptStoryboard.self, forKey: .storyboard)
        addedCharacters = (try? c.decodeIfPresent([AdaptCharacter].self, forKey: .addedCharacters)) ?? []
        chunks = (try? c.decodeIfPresent(Int.self, forKey: .chunks)) ?? 0
        completedChunks = (try? c.decodeIfPresent(Int.self, forKey: .completedChunks)) ?? 0
        usage = (try? c.decodeIfPresent(AdaptUsage.self, forKey: .usage)) ?? AdaptUsage()
        checkpoint = try c.decodeIfPresent(AdaptCheckpoint.self, forKey: .checkpoint)
    }
}

/// Ephemeral text-model configuration sent to Core `AdaptChapter` (mirrors `adaptTextConfigWire`).
///
/// Carries an `apiKey` in memory for the single Core call; never persist this
/// struct to disk.
public struct AdaptTextConfig: Codable, Sendable, Hashable {
    public var `protocol`: StandardProtocol
    public var baseURL: String?
    public var apiKey: String
    public var anthropicVersion: String?
    public var partition: String?
    public var model: String
    public var maxTokens: Int?
    public var temperature: Double?
    public var jsonMode: Bool?
    public var reasoningEffort: String?

    public init(
        protocol standard: StandardProtocol,
        baseURL: String? = nil,
        apiKey: String,
        anthropicVersion: String? = nil,
        partition: String? = StandardAI.partition,
        model: String,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        jsonMode: Bool? = nil,
        reasoningEffort: String? = nil
    ) {
        self.protocol = standard
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.anthropicVersion = anthropicVersion
        self.partition = partition
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.jsonMode = jsonMode
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case baseURL = "baseUrl"
        case apiKey, anthropicVersion, partition, model, maxTokens, temperature, jsonMode, reasoningEffort
    }
}

/// Ephemeral image-model configuration sent to Core `RenderPanel` / `RenderStoryboard`
/// (mirrors `adaptImageConfigWire`). Never persist this struct to disk.
public struct AdaptImageConfig: Codable, Sendable, Hashable {
    public var provider: AdaptImageProvider
    public var baseURL: String?
    public var apiKey: String
    public var model: String
    public var partition: String?
    public var responseModalities: [String]?
    public var size: String?
    public var quality: String?
    public var outputFormat: String?
    public var responseFormat: String?

    public init(
        provider: AdaptImageProvider,
        baseURL: String? = nil,
        apiKey: String,
        model: String,
        partition: String? = StandardAI.partition,
        responseModalities: [String]? = nil,
        size: String? = nil,
        quality: String? = nil,
        outputFormat: String? = nil,
        responseFormat: String? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.partition = partition
        self.responseModalities = responseModalities
        self.size = size
        self.quality = quality
        self.outputFormat = outputFormat
        self.responseFormat = responseFormat
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL = "baseUrl"
        case apiKey, model, partition, responseModalities, size, quality, outputFormat, responseFormat
    }
}

/// Panel and storyboard rendering options (mirrors Core `adaptRenderOptionsWire`).
public struct AdaptRenderOptions: Codable, Sendable, Hashable {
    public var aspectRatio: String?
    public var size: String?
    public var maxRetries: Int?
    public var forceRerender: Bool
    public var continueOnError: Bool
    public var styleReferences: [AdaptImageRef]
    public var characterReferences: [String: [AdaptImageRef]]
    public var feedbackCharacterRefs: Bool

    public init(
        aspectRatio: String? = nil,
        size: String? = nil,
        maxRetries: Int? = nil,
        forceRerender: Bool = false,
        continueOnError: Bool = false,
        styleReferences: [AdaptImageRef] = [],
        characterReferences: [String: [AdaptImageRef]] = [:],
        feedbackCharacterRefs: Bool = false
    ) {
        self.aspectRatio = aspectRatio
        self.size = size
        self.maxRetries = maxRetries
        self.forceRerender = forceRerender
        self.continueOnError = continueOnError
        self.styleReferences = styleReferences
        self.characterReferences = characterReferences
        self.feedbackCharacterRefs = feedbackCharacterRefs
    }

    enum CodingKeys: String, CodingKey {
        case aspectRatio, size, maxRetries, forceRerender, continueOnError
        case styleReferences, characterReferences, feedbackCharacterRefs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try c.decodeIfPresent(String.self, forKey: .aspectRatio)
        size = try c.decodeIfPresent(String.self, forKey: .size)
        maxRetries = try c.decodeIfPresent(Int.self, forKey: .maxRetries)
        forceRerender = (try? c.decodeIfPresent(Bool.self, forKey: .forceRerender)) ?? false
        continueOnError = (try? c.decodeIfPresent(Bool.self, forKey: .continueOnError)) ?? false
        styleReferences = (try? c.decodeIfPresent([AdaptImageRef].self, forKey: .styleReferences)) ?? []
        characterReferences = (try? c.decodeIfPresent([String: [AdaptImageRef]].self, forKey: .characterReferences)) ?? [:]
        feedbackCharacterRefs = (try? c.decodeIfPresent(Bool.self, forKey: .feedbackCharacterRefs)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(maxRetries, forKey: .maxRetries)
        if forceRerender { try c.encode(true, forKey: .forceRerender) }
        if continueOnError { try c.encode(true, forKey: .continueOnError) }
        if !styleReferences.isEmpty { try c.encode(styleReferences, forKey: .styleReferences) }
        if !characterReferences.isEmpty { try c.encode(characterReferences, forKey: .characterReferences) }
        if feedbackCharacterRefs { try c.encode(true, forKey: .feedbackCharacterRefs) }
    }
}

/// Request payload for Core `AdaptChapter` (mirrors `adaptChapterRequestWire`).
public struct AdaptChapterRequest: Codable, Sendable, Hashable {
    public var project: AdaptProject
    public var chapter: NovelChapter
    public var content: NovelChapterContent
    public var text: AdaptTextConfig
    public var options: AdaptOptions?

    public init(
        project: AdaptProject,
        chapter: NovelChapter,
        content: NovelChapterContent,
        text: AdaptTextConfig,
        options: AdaptOptions? = nil
    ) {
        self.project = project
        self.chapter = chapter
        self.content = content
        self.text = text
        self.options = options
    }
}

/// Response payload from Core `AdaptChapter` (mirrors `adaptChapterResponseWire`).
public struct AdaptChapterResponse: Codable, Sendable, Hashable {
    public var completed: Bool
    public var project: AdaptProject
    public var result: AdaptResult?
    public var error: String?
    public var errorCode: String?

    public var parsedErrorCode: AdaptErrorCode? {
        errorCode.flatMap(AdaptErrorCode.init(rawValue:))
    }

    public init(
        completed: Bool,
        project: AdaptProject,
        result: AdaptResult? = nil,
        error: String? = nil,
        errorCode: String? = nil
    ) {
        self.completed = completed
        self.project = project
        self.result = result
        self.error = error
        self.errorCode = errorCode
    }
}

/// Request payload for Core `RenderPanel` (mirrors `renderPanelRequestWire`).
public struct RenderPanelRequest: Codable, Sendable, Hashable {
    public var project: AdaptProject
    public var chapterID: String
    public var sceneID: String?
    public var panelID: String
    public var image: AdaptImageConfig
    public var options: AdaptRenderOptions?

    public init(
        project: AdaptProject,
        chapterID: String,
        sceneID: String? = nil,
        panelID: String,
        image: AdaptImageConfig,
        options: AdaptRenderOptions? = nil
    ) {
        self.project = project
        self.chapterID = chapterID
        self.sceneID = sceneID
        self.panelID = panelID
        self.image = image
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case project
        case chapterID = "chapterId"
        case sceneID = "sceneId"
        case panelID = "panelId"
        case image, options
    }
}

/// Response payload from Core `RenderPanel` (mirrors `renderPanelResponseWire`).
public struct RenderPanelResponse: Codable, Sendable, Hashable {
    public var project: AdaptProject
    public var sceneID: String
    public var panelID: String
    public var refID: String?
    public var skipped: Bool
    public var mimeType: String?
    public var dataBase64: String?
    public var revisedPrompt: String?
    public var usage: AdaptUsage

    /// Decoded raw image bytes when the panel was rendered and returned inline.
    public var imageData: Data? {
        guard let dataBase64, !dataBase64.isEmpty else { return nil }
        return Data(base64Encoded: dataBase64)
    }

    public init(
        project: AdaptProject,
        sceneID: String,
        panelID: String,
        refID: String? = nil,
        skipped: Bool = false,
        mimeType: String? = nil,
        dataBase64: String? = nil,
        revisedPrompt: String? = nil,
        usage: AdaptUsage = AdaptUsage()
    ) {
        self.project = project
        self.sceneID = sceneID
        self.panelID = panelID
        self.refID = refID
        self.skipped = skipped
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
        self.revisedPrompt = revisedPrompt
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case project
        case sceneID = "sceneId"
        case panelID = "panelId"
        case refID = "refId"
        case skipped, mimeType, dataBase64, revisedPrompt, usage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decode(AdaptProject.self, forKey: .project)
        sceneID = (try? c.decodeIfPresent(String.self, forKey: .sceneID)) ?? ""
        panelID = (try? c.decodeIfPresent(String.self, forKey: .panelID)) ?? ""
        refID = try c.decodeIfPresent(String.self, forKey: .refID)
        skipped = (try? c.decodeIfPresent(Bool.self, forKey: .skipped)) ?? false
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        dataBase64 = try c.decodeIfPresent(String.self, forKey: .dataBase64)
        revisedPrompt = try c.decodeIfPresent(String.self, forKey: .revisedPrompt)
        usage = (try? c.decodeIfPresent(AdaptUsage.self, forKey: .usage)) ?? AdaptUsage()
    }
}

/// Request payload for Core `RenderStoryboard` (mirrors `renderStoryboardRequestWire`).
public struct RenderStoryboardRequest: Codable, Sendable, Hashable {
    public var project: AdaptProject
    public var chapterID: String
    public var image: AdaptImageConfig
    public var options: AdaptRenderOptions?

    public init(
        project: AdaptProject,
        chapterID: String,
        image: AdaptImageConfig,
        options: AdaptRenderOptions? = nil
    ) {
        self.project = project
        self.chapterID = chapterID
        self.image = image
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case project
        case chapterID = "chapterId"
        case image, options
    }
}

/// One rendered panel image returned by `RenderStoryboard` (mirrors `renderedPanelImageWire`).
public struct RenderedPanelImage: Codable, Sendable, Hashable {
    public var sceneID: String
    public var panelID: String
    public var refID: String
    public var mimeType: String
    public var dataBase64: String

    public var imageData: Data? {
        Data(base64Encoded: dataBase64)
    }

    public init(sceneID: String, panelID: String, refID: String, mimeType: String, dataBase64: String) {
        self.sceneID = sceneID
        self.panelID = panelID
        self.refID = refID
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
    }

    enum CodingKeys: String, CodingKey {
        case sceneID = "sceneId"
        case panelID = "panelId"
        case refID = "refId"
        case mimeType, dataBase64
    }
}

/// One failed panel reported by `RenderStoryboard` (mirrors `panelFailureWire`).
public struct AdaptPanelFailure: Codable, Sendable, Hashable {
    public var sceneID: String
    public var panelID: String
    public var error: String
    public var errorCode: String

    public var parsedErrorCode: AdaptErrorCode? {
        AdaptErrorCode(rawValue: errorCode)
    }

    public init(sceneID: String, panelID: String, error: String, errorCode: String) {
        self.sceneID = sceneID
        self.panelID = panelID
        self.error = error
        self.errorCode = errorCode
    }

    enum CodingKeys: String, CodingKey {
        case sceneID = "sceneId"
        case panelID = "panelId"
        case error, errorCode
    }
}

/// Summary of one `RenderStoryboard` execution (mirrors `renderSummaryWire`).
public struct RenderSummary: Codable, Sendable, Hashable {
    public var chapterID: String
    public var rendered: Int
    public var skipped: Int
    public var failed: Int
    public var blocked: Int
    public var usage: AdaptUsage
    public var failures: [AdaptPanelFailure]

    public init(
        chapterID: String,
        rendered: Int = 0,
        skipped: Int = 0,
        failed: Int = 0,
        blocked: Int = 0,
        usage: AdaptUsage = AdaptUsage(),
        failures: [AdaptPanelFailure] = []
    ) {
        self.chapterID = chapterID
        self.rendered = rendered
        self.skipped = skipped
        self.failed = failed
        self.blocked = blocked
        self.usage = usage
        self.failures = failures
    }

    enum CodingKeys: String, CodingKey {
        case chapterID = "chapterId"
        case rendered, skipped, failed, blocked, usage, failures
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = (try? c.decodeIfPresent(String.self, forKey: .chapterID)) ?? ""
        rendered = (try? c.decodeIfPresent(Int.self, forKey: .rendered)) ?? 0
        skipped = (try? c.decodeIfPresent(Int.self, forKey: .skipped)) ?? 0
        failed = (try? c.decodeIfPresent(Int.self, forKey: .failed)) ?? 0
        blocked = (try? c.decodeIfPresent(Int.self, forKey: .blocked)) ?? 0
        usage = (try? c.decodeIfPresent(AdaptUsage.self, forKey: .usage)) ?? AdaptUsage()
        failures = (try? c.decodeIfPresent([AdaptPanelFailure].self, forKey: .failures)) ?? []
    }
}

/// Response payload from Core `RenderStoryboard` (mirrors `renderStoryboardResponseWire`).
public struct RenderStoryboardResponse: Codable, Sendable, Hashable {
    public var completed: Bool
    public var project: AdaptProject
    public var result: RenderSummary
    public var images: [RenderedPanelImage]
    public var error: String?
    public var errorCode: String?

    public var parsedErrorCode: AdaptErrorCode? {
        errorCode.flatMap(AdaptErrorCode.init(rawValue:))
    }

    public init(
        completed: Bool,
        project: AdaptProject,
        result: RenderSummary,
        images: [RenderedPanelImage] = [],
        error: String? = nil,
        errorCode: String? = nil
    ) {
        self.completed = completed
        self.project = project
        self.result = result
        self.images = images
        self.error = error
        self.errorCode = errorCode
    }

    enum CodingKeys: String, CodingKey {
        case completed, project, result, images, error, errorCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? false
        project = try c.decode(AdaptProject.self, forKey: .project)
        result = try c.decode(RenderSummary.self, forKey: .result)
        images = (try? c.decodeIfPresent([RenderedPanelImage].self, forKey: .images)) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
    }
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
