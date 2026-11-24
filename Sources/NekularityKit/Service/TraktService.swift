import Foundation

public struct TraktAccount: Decodable, Hashable, Sendable {
    public let username: String
    public let name: String?

    public init(username: String, name: String? = nil) {
        self.username = username
        self.name = name
    }
}

public struct TraktItem: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case movie, show, season, episode }

    public let kind: Kind
    public let id: Int
    public let title: String
    public let year: Int?

    public init(kind: Kind, id: Int, title: String, year: Int? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.year = year
    }
}

public struct TraktHistoryEntry: Decodable, Hashable, Sendable {
    public let item: TraktItem
    public let watchedAt: String

    public init(item: TraktItem, watchedAt: String) {
        self.item = item
        self.watchedAt = watchedAt
    }
}

public enum TraktScrobbleAction: String, Sendable { case start, pause, stop }

public protocol TraktProvider: Sendable {
    func account() async throws -> TraktAccount
    func search(query: String) async throws -> [TraktItem]
    func watchlist() async throws -> [TraktItem]
    func setWatchlist(_ item: TraktItem, included: Bool) async throws
    func history() async throws -> [TraktHistoryEntry]
    func record(_ item: TraktItem, watchedAt: String) async throws
    func scrobble(_ action: TraktScrobbleAction, item: TraktItem, progress: Double) async throws
}

public struct TraktService: TraktProvider {
    private let bridge: ServicePackageBridge
    private let fallback: (any TraktProvider)?
    private static let id = KnownServiceID.trakt
    private static let authKey = "access_token"
    private static let clientKey = "client_id"

    public init(bridge: ServicePackageBridge, fallback: (any TraktProvider)? = nil) {
        self.bridge = bridge
        self.fallback = fallback
    }

    public func account() async throws -> TraktAccount {
        if let account = try await read("account.me", as: TraktAccount.self) { return account }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        return try await fallback.account()
    }

    public func search(query: String) async throws -> [TraktItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let payload = JSONValue.serviceArguments(("query", .string(query)), ("type", .string("movie,show,episode")))
        if let found = try await bridge.invokeIfInstalled(Self.id, method: "metadata.search", payload: payload,
                                                          secretKeys: [Self.clientKey], as: ServiceItems<WireItem>.self) {
            return found.items.compactMap(\.model)
        }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        return try await fallback.search(query: query)
    }

    public func watchlist() async throws -> [TraktItem] {
        if let found = try await read("watchlist.list", as: ServiceItems<WireItem>.self) {
            return found.items.compactMap(\.model)
        }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        return try await fallback.watchlist()
    }

    public func setWatchlist(_ item: TraktItem, included: Bool) async throws {
        let payload = JSONValue.serviceArguments(("item", reference(item)), ("included", .bool(included)))
        try await write("watchlist.set", payload) { try await $0.setWatchlist(item, included: included) }
    }

    public func history() async throws -> [TraktHistoryEntry] {
        if let found = try await read("history.list", as: ServiceItems<WireItem>.self) {
            return found.items.compactMap { row in
                guard let item = row.model, let watchedAt = row.watchedAt else { return nil }
                return TraktHistoryEntry(item: item, watchedAt: watchedAt)
            }
        }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        return try await fallback.history()
    }

    public func record(_ item: TraktItem, watchedAt: String) async throws {
        let payload = JSONValue.serviceArguments(("item", reference(item)), ("watchedAt", .string(watchedAt)))
        try await write("history.add", payload) { try await $0.record(item, watchedAt: watchedAt) }
    }

    public func scrobble(_ action: TraktScrobbleAction, item: TraktItem, progress: Double) async throws {
        let method = "scrobble.\(action.rawValue)"
        guard progress.isFinite, (0...100).contains(progress), item.kind == .movie || item.kind == .episode else {
            throw ServiceBridgeError.invalidPayload(service: Self.id, method: method)
        }
        let media = JSONValue.serviceArguments(("ids", .serviceArguments(("trakt", .integer(item.id)))))
        let payload = JSONValue.serviceArguments((item.kind.rawValue, media), ("progress", .number(String(progress))))
        try await write(method, payload) { try await $0.scrobble(action, item: item, progress: progress) }
    }

    private func reference(_ item: TraktItem) -> JSONValue {
        .serviceArguments(("kind", .string(item.kind.rawValue)), ("id", .integer(item.id)))
    }

    private struct WireItem: Decodable, Sendable {
        struct IDs: Decodable, Sendable { let trakt: Int? }
        let type: String
        let title: String
        let year: Int?
        let ids: IDs?
        let watchedAt: String?

        var model: TraktItem? {
            guard let kind = TraktItem.Kind(rawValue: type), let id = ids?.trakt else { return nil }
            return TraktItem(kind: kind, id: id, title: title, year: year)
        }
    }

    private func read<Response: Decodable & Sendable>(_ method: String, as type: Response.Type) async throws -> Response? {
        try await bridge.invokeIfInstalled(Self.id, method: method, secretKeys: [Self.clientKey, Self.authKey], as: type)
    }

    private func write(_ method: String, _ payload: JSONValue,
                       fallback call: (any TraktProvider) async throws -> Void) async throws {
        if try await bridge.invokeIfInstalled(Self.id, method: method, payload: payload,
                                              secretKeys: [Self.clientKey, Self.authKey],
                                              as: ServiceAcknowledgement.self) != nil { return }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        try await call(fallback)
    }
}
