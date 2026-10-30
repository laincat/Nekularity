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

    public init() {}
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

/// A kept page. Core reads these, but this client has no picture shelf yet.
public struct BackupPicture: Decodable, Sendable {
    public var sourceKey: String?
    public var id: String
    public var url: String?
    public var page: Int64?
}

/// A source to reinstall through the normal install flow.
public struct BackupSource: Decodable, Sendable {
    public var key: String
    public var script: String?
    /// The source's own data, kept as JSON so numbers and key order survive.
    public var data: JSONValue?
}
