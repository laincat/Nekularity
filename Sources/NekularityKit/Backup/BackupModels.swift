import Foundation

/// What Core's `planBackup` returns: the rows a restore would write.
///
/// Every collection is optional because Core omits empty ones, and a missing
/// collection means "nothing to do", not "decode failed".
public struct BackupPlan: Decodable, Sendable {
    public var history: [BackupHistory]?
    public var folders: [BackupFolder]?
    public var imageFavorites: [BackupPicture]?
    public var searchHistory: [String]?
    public var sources: [BackupSource]?
    /// Rows Core could not attribute to a source the client knows. They are
    /// not lost: install the matching source and import again.
    public var pending: BackupPending?
    /// The old app's single-jar cookies, present only when the import asked for
    /// them. `cookieTargets` says which partitions they belong in.
    public var cookies: [BackupCookie]?
    public var cookieTargets: [String]?

    public init() {}
}

public struct BackupPending: Decodable, Sendable {
    public var history: [BackupHistory]?
    /// Folder name → the comics in it that need a missing source.
    public var favorites: [String: [BackupFavorite]]?

    public var rowCount: Int {
        (history?.count ?? 0) + (favorites ?? [:]).values.reduce(0) { $0 + $1.count }
    }
}

/// One reading position. Times are milliseconds since the epoch, as the
/// official client stores them; `ep` is the chapter index.
public struct BackupHistory: Decodable, Sendable {
    public var sourceKey: String?
    public var id: String
    public var title: String
    public var subtitle: String?
    public var cover: String?
    public var time: Int64
    public var ep: Int64
    public var page: Int64
}

/// A favourite folder and the comics in it.
public struct BackupFolder: Decodable, Sendable {
    public var name: String
    public var items: [BackupFavorite]
}

public struct BackupFavorite: Decodable, Sendable {
    public var sourceKey: String?
    public var id: String
    public var name: String
    public var author: String?
    public var cover: String?
}

/// A kept picture. Core passes the official app's own JSON through, so the
/// pages are nested: `episodes[].imageFavorites[].{page,imageKey,eid,ep}`.
/// There is no top-level `url` or `page`.
public struct BackupPicture: Decodable, Sendable {
    public var sourceKey: String?
    public var id: String
    public var title: String
    public var subTitle: String?
    public var author: String?
    public var tags: String?
    public var time: Int64?
    public var maxPage: Int64?
    public var episodes: JSONValue?
    public var other: JSONValue?

    /// How many pages this picture keeps, for the import report.
    public var keptPages: Int {
        guard let episodes = episodes?.array else { return 0 }
        return episodes.reduce(0) { total, episode in
            total + (episode["imageFavorites"]?.array?.count ?? 0)
        }
    }
}

/// A source to reinstall through the normal install flow.
public struct BackupSource: Decodable, Sendable {
    public var key: String
    public var script: String?
    /// The source's own data, kept as JSON so numbers and key order survive.
    public var data: JSONValue?
}

/// One cookie from the official app's global jar.
///
/// `domain` is a host, not a URL: rows carrying `https://` are junk and Core
/// drops them before the plan is returned.
public struct BackupCookie: Decodable, Sendable, Hashable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String?
    /// Unix milliseconds, absent when the cookie had no expiry.
    public var expires: Int64?
    public var secure: Bool
    public var httpOnly: Bool

    public init(name: String, value: String, domain: String, path: String? = nil,
                expires: Int64? = nil, secure: Bool = false, httpOnly: Bool = false) {
        self.name = name; self.value = value; self.domain = domain; self.path = path
        self.expires = expires; self.secure = secure; self.httpOnly = httpOnly
    }
}
