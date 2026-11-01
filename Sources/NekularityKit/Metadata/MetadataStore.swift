import Foundation
import Observation

/// Where the metadata key is kept.
///
/// The key is a credential: it identifies the user's TMDB account and can be
/// revoked there. It goes to the Keychain like every other secret in this app, and
/// the cache file holds only public facts about shows.
public protocol MetadataKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

public final class MemoryMetadataKeyStore: MetadataKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    public init(key: String? = nil) { self.key = key }
    public func load() throws -> String? { lock.withLock { key } }
    public func save(_ key: String) throws { lock.withLock { self.key = key } }
    public func remove() throws { lock.withLock { self.key = nil } }
}

public final class KeychainMetadataKeyStore: MetadataKeyStore, @unchecked Sendable {
    private let service: String
    private let account = "tmdb"

    public init(service: String = "com.laincat.nekularity.tmdb") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
                throw MetadataError("保存的 key 不是文本")
            }
            return text
        case errSecItemNotFound:
            return nil
        case let status:
            throw MetadataError("钥匙串拒绝了读取(\(status))")
        }
    }

    public func save(_ key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
        var add = query
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MetadataError("钥匙串拒绝了保存(\(status))")
        }
    }

    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MetadataError("钥匙串拒绝了删除(\(status))")
        }
    }
}

/// Show metadata this device has already looked up.
///
/// A cache rather than a copy of TMDB: entries expire, so a show that gains a new
/// episode is not stuck on the answer from six months ago. Seven days is long
/// enough to keep the request count small and short enough that an air date is
/// never stale by more than a week.
@MainActor
@Observable
public final class MetadataStore {
    public static let ttl: TimeInterval = 7 * 24 * 60 * 60

    /// Everything looked up, keyed by `source/id`.
    public private(set) var series: [String: SeriesInfo] = [:]
    public private(set) var failure: String?
    /// True when a key is stored, so the interface can say "connected" without
    /// reading the Keychain on every redraw.
    public private(set) var hasKey = false

    private let directory: URL
    private let file: URL
    private let keys: any MetadataKeyStore

    public init(directory: URL, keys: any MetadataKeyStore = KeychainMetadataKeyStore()) {
        self.directory = directory
        file = directory.appending(path: "metadata.json")
        self.keys = keys
        load()
        hasKey = (try? keys.load())?.isEmpty == false
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        guard let decoded = try? JSONDecoder().decode([String: SeriesInfo].self, from: data) else {
            // Left on disk unchanged: a cache that will not decode is worth less
            // than the file that might after a version that can read it.
            _ = StoreRescue.keepCopy(of: file)
            failure = "元数据缓存读不出来,旧数据已另存一份"
            return
        }
        series = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(series)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            failure = "元数据缓存写不进去(\(error.localizedDescription))"
        }
    }

    public func apiKey() -> String? {
        (try? keys.load()) ?? nil
    }

    public func setKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keys.remove()
            hasKey = false
        } else {
            try keys.save(trimmed)
            hasKey = true
        }
    }

    /// A cached answer that is still fresh.
    public func cached(_ key: String) -> SeriesInfo? {
        guard let info = series[key], Date().timeIntervalSince(info.fetchedAt) < Self.ttl else { return nil }
        return info
    }

    /// Looks one show up, using the cache when it is fresh.
    @discardableResult
    public func lookup(id: Int, client: TMDBClient) async throws -> SeriesInfo {
        let key = "tmdb/\(id)"
        if let hit = cached(key) { return hit }
        let info = try await client.series(id: id)
        series[key] = info
        save()
        return info
    }

    /// Which show a title probably is. One result is the common case; zero is an
    /// answer too, and a title that matches several shows stays unresolved rather
    /// than being guessed at.
    public func identify(title: String, client: TMDBClient) async throws -> SeriesInfo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matches = try await client.search(query: trimmed)
        guard let best = matches.first else { return nil }
        let exact = matches.filter { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
        guard exact.count <= 1 else { return nil }
        return try await lookup(id: (exact.first ?? best).id, client: client)
    }

    /// Shows with a known upcoming episode, soonest first. This is what the
    /// calendar can honestly show as "upcoming", because the date came from a
    /// source that publishes it.
    public func upcoming(within days: Int = 14, from now: Date = Date()) -> [(info: SeriesInfo, airs: Date)] {
        let limit = now.addingTimeInterval(TimeInterval(days) * 86_400)
        return series.values.compactMap { info in
            guard let airs = info.nextAirDate, airs >= Calendar.current.startOfDay(for: now), airs <= limit else {
                return nil
            }
            return (info, airs)
        }
        .sorted { $0.airs < $1.airs }
    }

    public func forget() {
        series.removeAll()
        save()
    }
}
