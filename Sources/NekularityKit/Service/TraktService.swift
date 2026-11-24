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
    public enum Kind: String, Codable, Sendable { case movie, show, episode }

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
        try await route("account.me", as: TraktAccount.self) { try await $0.account() }
    }

    public func search(query: String) async throws -> [TraktItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return try await route("search", .serviceArguments(("query", .string(query))),
                               authenticated: false, as: [TraktItem].self) { try await $0.search(query: query) }
    }

    public func watchlist() async throws -> [TraktItem] {
        try await route("watchlist.list", as: [TraktItem].self) { try await $0.watchlist() }
    }

    public func setWatchlist(_ item: TraktItem, included: Bool) async throws {
        let payload = JSONValue.serviceArguments(("item", reference(item)), ("included", .bool(included)))
        try await write("watchlist.set", payload) { try await $0.setWatchlist(item, included: included) }
    }

    public func history() async throws -> [TraktHistoryEntry] {
        try await route("history.list", as: [TraktHistoryEntry].self) { try await $0.history() }
    }

    public func record(_ item: TraktItem, watchedAt: String) async throws {
        let payload = JSONValue.serviceArguments(("item", reference(item)), ("watchedAt", .string(watchedAt)))
        try await write("history.add", payload) { try await $0.record(item, watchedAt: watchedAt) }
    }

    public func scrobble(_ action: TraktScrobbleAction, item: TraktItem, progress: Double) async throws {
        guard progress.isFinite, (0...100).contains(progress), item.kind != .show else {
            throw ServiceBridgeError.invalidPayload(service: Self.id, method: "scrobble")
        }
        let payload = JSONValue.serviceArguments(("item", reference(item)), ("action", .string(action.rawValue)),
                                                 ("progress", .number(String(progress))))
        try await write("scrobble", payload) { try await $0.scrobble(action, item: item, progress: progress) }
    }

    private func reference(_ item: TraktItem) -> JSONValue {
        .serviceArguments(("kind", .string(item.kind.rawValue)), ("id", .integer(item.id)))
    }

    private func route<Response: Decodable & Sendable>(
        _ method: String, _ payload: JSONValue = .null, authenticated: Bool = true, as type: Response.Type,
        fallback call: (any TraktProvider) async throws -> Response
    ) async throws -> Response {
        if let result = try await bridge.invokeIfInstalled(Self.id, method: method, payload: payload,
                                                           secretKeys: authenticated ? [Self.clientKey, Self.authKey] : [Self.clientKey],
                                                           as: type) { return result }
        guard let fallback else { throw ServiceBridgeError.notInstalled(Self.id) }
        return try await call(fallback)
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
