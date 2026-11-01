import Foundation

/// One row in 媒体库, whatever it came from.
///
/// Local files and server items are the same thing to a reader: something to
/// watch, with a title, a picture and how far in they got. Keeping two lists
/// would make the user remember which screen a film was on.
public struct HubEntry: Identifiable, Hashable, Sendable {
    /// Where the bytes are.
    public enum Origin: Hashable, Sendable {
        case local(fileID: String)
        case server(serverID: String, itemID: String)
    }

    public var title: String
    /// Series name for an episode, empty for a film.
    public var subtitle: String
    public var poster: String?
    /// How far in, 0–1. Zero when unwatched or unknown.
    public var progress: Double
    /// The library it came from: 本机 or the server's name.
    public var sourceName: String
    public var origin: Origin

    public var id: String {
        switch origin {
        case .local(let fileID): "local/\(fileID)"
        case .server(let serverID, let itemID): "server/\(serverID)/\(itemID)"
        }
    }

    public init(title: String, subtitle: String = "", poster: String? = nil,
                progress: Double = 0, sourceName: String, origin: Origin) {
        self.title = title
        self.subtitle = subtitle
        self.poster = poster
        self.progress = progress
        self.sourceName = sourceName
        self.origin = origin
    }

    /// A finished film is not "continue watching" material.
    public var isInProgress: Bool { progress > 0.02 && progress < 0.95 }
}

/// Merging and searching, kept out of the screen so it can be tested without one.
public enum MediaHub {
    /// Every local file and every server item, as one list.
    ///
    /// Local files come first: they work with no network, so a reader who has
    /// both is not made to wait on a server round-trip to see their own films.
    public static func entries(local: [(id: String, title: String, poster: String?, progress: Double)],
                               servers: [(name: String, id: String, items: [MediaItem])]) -> [HubEntry] {
        var rows: [HubEntry] = local.map { item in
            HubEntry(title: item.title, poster: item.poster, progress: item.progress,
                     sourceName: "本机", origin: .local(fileID: item.id))
        }
        for server in servers {
            for item in server.items {
                rows.append(HubEntry(title: item.title,
                                     subtitle: item.series,
                                     poster: item.poster,
                                     progress: item.progress,
                                     sourceName: server.name,
                                     origin: .server(serverID: server.id, itemID: item.id)))
            }
        }
        return rows
    }

    /// Case- and width-insensitive contains, over the title and the series.
    ///
    /// A search that only matches the title hides an episode whose series is what
    /// the user typed, which is the common way people look for TV.
    public static func search(_ entries: [HubEntry], query: String) -> [HubEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(needle)
                || entry.subtitle.localizedCaseInsensitiveContains(needle)
        }
    }

    /// The rows worth offering to resume, most-watched-first is wrong here: the
    /// one to resume is simply the furthest along that is not finished.
    public static func continueWatching(_ entries: [HubEntry]) -> [HubEntry] {
        entries.filter(\.isInProgress).sorted { $0.progress > $1.progress }
    }

    /// The rows grouped by where they came from, in the order the groups appear.
    public static func grouped(_ entries: [HubEntry]) -> [(name: String, rows: [HubEntry])] {
        var order: [String] = []
        var buckets: [String: [HubEntry]] = [:]
        for entry in entries {
            if buckets[entry.sourceName] == nil { order.append(entry.sourceName) }
            buckets[entry.sourceName, default: []].append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}
