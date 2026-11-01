import Foundation
import Observation

/// What the home screen shows, and in what order.
///
/// A block is either one of the app's own lists or **a section a source
/// provides** — a source's recommendations, its ranking, its own favourites.
/// That is the difference between a home screen of local records and a home
/// screen that reads what the installed plugins can offer.
public struct HomeBlock: Codable, Sendable, Hashable, Identifiable {
    /// A list the app builds itself.
    public enum Template: String, Codable, Sendable, CaseIterable, Identifiable {
        case history
        case favorites
        case continueWatching
        case upcoming
        case localComics
        case searches
        case downloads
        case localVideos
        case videoSources

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .history: "继续阅读"
            case .favorites: "收藏"
            case .continueWatching: "继续观看"
            case .upcoming: "即将播出"
            case .localComics: "本地漫画"
            case .searches: "最近搜索"
            case .downloads: "已下载"
            case .localVideos: "本机视频"
            case .videoSources: "视频源"
            }
        }

        public var symbol: String {
            switch self {
            case .history: "book"
            case .favorites: "heart"
            case .continueWatching: "play.rectangle.fill"
            case .upcoming: "calendar.badge.clock"
            case .localComics: "folder"
            case .searches: "magnifyingglass"
            case .downloads: "arrow.down.circle"
            case .localVideos: "play.rectangle"
            case .videoSources: "antenna.radiowaves.left.and.right"
            }
        }

        /// How wide a block wants to be. A strip of covers is unreadable at half
        /// a phone, so it takes the full width; the small counters pair up.
        public var isWide: Bool {
            switch self {
            case .history, .searches, .continueWatching, .upcoming, .localComics: true
            case .favorites, .downloads, .localVideos, .videoSources: false
            }
        }
    }

    /// A browse page a source declares, such as "推荐" or "排行".
    ///
    /// `index` is the page's position in the source's own list: the title alone
    /// is not stable across versions of a source, the position is what Core's
    /// `explore` call takes.
    public struct SourceRef: Codable, Sendable, Hashable {
        public var key: String
        public var sourceName: String
        public var index: Int
        public var title: String

        public init(key: String, sourceName: String, index: Int, title: String) {
            self.key = key
            self.sourceName = sourceName
            self.index = index
            self.title = title
        }
    }

    public enum Kind: Codable, Sendable, Hashable {
        case template(Template)
        case source(SourceRef)
    }

    public var kind: Kind
    public var enabled: Bool

    public var id: String {
        switch kind {
        case .template(let template): "template:\(template.rawValue)"
        case .source(let ref): "source:\(ref.key)#\(ref.index)"
        }
    }

    public var title: String {
        switch kind {
        case .template(let template): template.title
        case .source(let ref): ref.title
        }
    }

    public var subtitle: String? {
        switch kind {
        case .template: nil
        case .source(let ref): ref.sourceName
        }
    }

    public var symbol: String {
        switch kind {
        case .template(let template): template.symbol
        case .source: "square.stack"
        }
    }

    public var isWide: Bool {
        switch kind {
        case .template(let template): template.isWide
        case .source: true
        }
    }

    public init(template: Template, enabled: Bool = true) {
        kind = .template(template)
        self.enabled = enabled
    }

    public init(source ref: SourceRef, enabled: Bool = true) {
        kind = .source(ref)
        self.enabled = enabled
    }
}

/// The block arrangement, kept across launches.
@MainActor
@Observable
public final class HomeLayout {
    public private(set) var blocks: [HomeBlock]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        blocks = Self.load(defaults) ?? HomeBlock.Template.allCases.map { HomeBlock(template: $0) }
    }

    public var visible: [HomeBlock] { blocks.filter(\.enabled) }

    /// Sections the user added from a source.
    public var sourceBlocks: [HomeBlock] {
        blocks.filter { if case .source = $0.kind { true } else { false } }
    }

    /// Moves the blocks at `from` so they land before `to`.
    ///
    /// Written out rather than taken from SwiftUI's `move(fromOffsets:toOffset:)`:
    /// the kit has no SwiftUI, and a test target linking only the kit failed to
    /// resolve that symbol.
    public func move(from: IndexSet, to: Int) {
        let moving = from.sorted().compactMap { index in
            blocks.indices.contains(index) ? blocks[index] : nil
        }
        guard !moving.isEmpty else { return }
        let removed = from.sorted().reversed().compactMap { index in
            blocks.indices.contains(index) ? index : nil
        }
        for index in removed { blocks.remove(at: index) }
        let destination = max(0, min(blocks.count, to - from.filter { $0 < to }.count))
        blocks.insert(contentsOf: moving, at: destination)
        save()
    }

    public func move(_ block: HomeBlock, by delta: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let target = index + delta
        guard blocks.indices.contains(target) else { return }
        move(from: IndexSet(integer: index), to: delta > 0 ? target + 1 : target)
    }

    public func toggle(_ template: HomeBlock.Template) {
        setEnabled(template, !(blocks.first { $0.id == "template:\(template.rawValue)" }?.enabled ?? false))
    }

    /// Hides or shows a block by identity, whatever kind it is.
    public func setEnabled(_ block: HomeBlock, _ on: Bool) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index].enabled = on
        save()
    }

    public func setEnabled(_ template: HomeBlock.Template, _ on: Bool) {
        let id = "template:\(template.rawValue)"
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].enabled = on
        } else {
            blocks.append(HomeBlock(template: template, enabled: on))
        }
        save()
    }

    /// Adds a source section. Adding the same section twice is a no-op rather
    /// than two identical cards.
    public func add(_ ref: HomeBlock.SourceRef) {
        let block = HomeBlock(source: ref)
        guard !blocks.contains(where: { $0.id == block.id }) else { return }
        blocks.append(block)
        save()
    }

    public func remove(_ block: HomeBlock) {
        blocks.removeAll { $0.id == block.id }
        save()
    }

    /// Back to the shipped arrangement.
    public func reset() {
        blocks = HomeBlock.Template.allCases.map { HomeBlock(template: $0) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(blocks) else { return }
        defaults.set(data, forKey: "homeBlocksV2")
    }

    private static func load(_ defaults: UserDefaults) -> [HomeBlock]? {
        guard let data = defaults.data(forKey: "homeBlocksV2"),
              let saved = try? JSONDecoder().decode([HomeBlock].self, from: data) else { return nil }
        // A template removed in a later version must not resurrect, and a new one
        // must appear; source sections are the user's and are kept as they are.
        var out: [HomeBlock] = []
        var seen = Set<String>()
        for block in saved where !seen.contains(block.id) {
            seen.insert(block.id)
            out.append(block)
        }
        for template in HomeBlock.Template.allCases
        where !seen.contains("template:\(template.rawValue)") {
            out.append(HomeBlock(template: template))
        }
        return out
    }
}
