import Foundation
import Observation

/// Where a Bangumi token is kept.
///
/// Separate from everything else on purpose: a token is a credential and must not
/// end up in a JSON file that a backup or a shared profile folder would carry.
public protocol BangumiTokenStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func remove() throws
}

public final class MemoryBangumiTokenStore: BangumiTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func load() throws -> String? { lock.withLock { token } }
    public func save(_ token: String) throws { lock.withLock { self.token = token } }
    public func remove() throws { lock.withLock { token = nil } }
}

/// Keychain-backed, one generic password for the account.
public final class KeychainBangumiTokenStore: BangumiTokenStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.laincat.nekularity.bangumi") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "token",
        ]
    }

    public func load() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(q as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw BangumiError("保存的令牌不是文本,请重新连接")
            }
            return text
        case errSecItemNotFound:
            return nil
        case let status:
            throw BangumiError("钥匙串拒绝了读取(\(status))")
        }
    }

    public func save(_ token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            // ThisDeviceOnly: a Bangumi token restored onto another phone from a
            // backup is a working key to someone's collection.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
        var add = query
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BangumiError("钥匙串拒绝了保存(\(status))")
        }
    }

    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BangumiError("钥匙串拒绝了删除(\(status))")
        }
    }
}

/// The Bangumi account and what it has collected.
///
/// A store rather than a screen: the same collections feed the reminder planner, so
/// where they come from matters less than that they are decoded once and shared.
@MainActor
@Observable
public final class BangumiStore {
    /// How many watching subjects to look up for air dates in one pass. Each needs
    /// its own request, and Bangumi throttles; forty shows would be forty requests
    /// and a stalled settings screen.
    public static let airingLimit = 20

    public private(set) var user: BangumiUser?
    public private(set) var collections: [BangumiCollection] = []
    /// Bangumi's broadcast calendar: what airs on each weekday. Public data,
    /// so it is fetched whether or not an account is connected.
    public private(set) var calendar: [BangumiCalendarDay] = []
    public private(set) var failure: String?
    public private(set) var busy = false
    /// True when a token is stored, so a screen can say "connected" without
    /// reading the Keychain on every redraw.
    public private(set) var hasToken = false

    private let tokens: any BangumiTokenStore
    private let makeClient: @Sendable (String?) -> BangumiClient

    public init(tokens: any BangumiTokenStore = KeychainBangumiTokenStore(),
                makeClient: @escaping @Sendable (String?) -> BangumiClient = { BangumiClient.live(token: $0) }) {
        self.tokens = tokens
        self.makeClient = makeClient
        hasToken = ((try? tokens.load()) ?? nil)?.isEmpty == false
    }

    private var client: BangumiClient? {
        guard let token = (try? tokens.load()) ?? nil, !token.isEmpty else { return nil }
        return makeClient(token)
    }

    /// Checks the token against Bangumi before keeping it: a token that only fails
    /// later would look like a broken screen rather than a wrong token.
    public func signIn(token rawToken: String) async {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            failure = "先粘贴一个 Bangumi 令牌"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let me = try await makeClient(token).me()
            try tokens.save(token)
            hasToken = true
            user = me
            failure = nil
            await refresh()
        } catch {
            failure = BangumiErrorText.readable(error)
        }
    }

    public func signOut() {
        try? tokens.remove()
        hasToken = false
        user = nil
        collections = []
        failure = nil
    }

    /// Reloads the collections, optionally only one state.
    public func refresh(type: CollectionType? = nil) async {
        guard let client else { return }
        busy = true
        defer { busy = false }
        do {
            if user == nil { user = try await client.me() }
            collections = try await client.collections(type: type)
            failure = nil
        } catch {
            failure = BangumiErrorText.readable(error)
        }
    }

    /// The weekly broadcast calendar. Kept separate from `refresh()` because it
    /// needs no account and a signed-out screen still wants it.
    public func loadCalendar() async {
        do {
            calendar = try await makeClient(nil).calendar()
            failure = nil
        } catch {
            failure = BangumiErrorText.readable(error)
        }
    }

    public func search(_ keyword: String, type: Int = 2) async -> [BangumiSubject] {
        guard let client else { return [] }
        do {
            let found = try await client.search(keyword: keyword, type: type)
            failure = nil
            return found
        } catch {
            failure = BangumiErrorText.readable(error)
            return []
        }
    }

    /// A subject with its episodes and this account's state for it, for a detail
    /// screen.
    public func detail(subjectID: Int) async -> (subject: BangumiSubject, episodes: [BangumiEpisode],
                                                 collection: BangumiCollection?)? {
        guard let client else { return nil }
        do {
            let subject = try await client.subject(id: subjectID)
            let episodes = try await client.episodes(subjectID: subjectID)
            let collection = try await client.collection(subjectID: subjectID)
            failure = nil
            return (subject, episodes, collection)
        } catch {
            failure = BangumiErrorText.readable(error)
            return nil
        }
    }

    public func set(type: CollectionType, rate: Int? = nil, epStatus: Int? = nil,
                    for subjectID: Int) async {
        guard let client else { return }
        do {
            try await client.setCollection(subjectID: subjectID, type: type,
                                           rate: rate, epStatus: epStatus)
            await refresh()
        } catch {
            failure = BangumiErrorText.readable(error)
        }
    }

    /// Marks one episode watched and moves the local count with it, so the row can
    /// show the change before the next refresh lands.
    public func markWatched(subjectID: Int, episodeID: Int) async {
        guard let client else { return }
        do {
            try await client.markWatched(subjectID: subjectID, episodeID: episodeID)
            await refresh()
        } catch {
            failure = BangumiErrorText.readable(error)
        }
    }

    /// The watching collection as shows with air dates, for the reminder planner.
    ///
    /// This is the join that makes Bangumi worth having here: the reminder code
    /// already knows how to turn a `SeriesInfo` into a notification, so Bangumi
    /// only has to answer in that shape.
    public func airingShows(now: Date = Date()) async -> [SeriesInfo] {
        guard let client else { return [] }
        let watching = collections.filter { $0.type == .doing }
            .prefix(Self.airingLimit)
        var shows: [SeriesInfo] = []
        for entry in watching {
            guard let subject = entry.subject else { continue }
            // One subject that fails must not empty the list: a deleted entry or a
            // throttled request is not a reason to forget the other nineteen.
            let episodes = (try? await client.episodes(subjectID: subject.id)) ?? []
            shows.append(SeriesInfo(subject: subject, episodes: episodes, now: now))
        }
        return shows
    }
}

/// Bangumi's own wording where it helps, the message otherwise.
enum BangumiErrorText {
    static func readable(_ error: any Error) -> String {
        if let error = error as? BangumiError { return error.message }
        return error.localizedDescription
    }
}
