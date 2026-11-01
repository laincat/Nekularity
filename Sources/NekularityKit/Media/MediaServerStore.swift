import Foundation
import Observation

/// Where a server's token is kept.
///
/// Separate from the server record on purpose: the record is a name and an
/// address that can live in a text file, and the token is a credential that must
/// not. `MemoryMediaTokenStore` exists for tests and previews; the app uses the
/// Keychain, and a backup of the servers file then carries no access.
public protocol MediaTokenStore: Sendable {
    func load(id: String) throws -> String?
    func save(id: String, token: String) throws
    func remove(id: String) throws
}

public final class MemoryMediaTokenStore: MediaTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    public init() {}
    public func load(id: String) throws -> String? { lock.withLock { items[id] } }
    public func save(id: String, token: String) throws { lock.withLock { items[id] = token } }
    public func remove(id: String) throws { lock.withLock { items[id] = nil } }
}

/// Keychain-backed, one generic password per server.
public final class KeychainMediaTokenStore: MediaTokenStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.laincat.nekularity.media") {
        self.service = service
    }

    private func query(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    public func load(id: String) throws -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(q as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw MediaServerError("保存的令牌不是文本,请重新登录")
            }
            return text
        case errSecItemNotFound:
            return nil
        case let status:
            throw MediaServerError("钥匙串拒绝了读取(\(status))")
        }
    }

    public func save(id: String, token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            // ThisDeviceOnly: a server token restored onto another phone from a
            // backup is a working key to someone's library.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
        var add = query(id)
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MediaServerError("钥匙串拒绝了保存(\(status))")
        }
    }

    public func remove(id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MediaServerError("钥匙串拒绝了删除(\(status))")
        }
    }
}

/// The servers this environment knows, and their tokens.
///
/// One store per environment, like every other store: two accounts are two sets
/// of libraries, and sharing them would show one person's films to the other.
@MainActor
@Observable
public final class MediaServerStore {
    public private(set) var servers: [MediaServer] = []
    public private(set) var failure: String?
    /// What the last connection test said, per server id.
    public private(set) var status: [String: String] = [:]

    private let directory: URL
    private let file: URL
    private let tokens: any MediaTokenStore

    public init(directory: URL, tokens: any MediaTokenStore = KeychainMediaTokenStore()) {
        self.directory = directory
        file = directory.appending(path: "media-servers.json")
        self.tokens = tokens
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            servers = try JSONDecoder().decode([MediaServer].self, from: data)
        } catch {
            // A file that will not decode is left alone rather than overwritten:
            // the addresses in it are still the user's, and clobbering them loses
            // the only record of what to reconnect to.
            _ = StoreRescue.keepCopy(of: file)
            failure = "媒体服务器列表读不出来(\(error.localizedDescription)),旧数据已另存一份"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(servers)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            failure = "无法保存媒体服务器列表(\(error.localizedDescription))"
        }
    }

    public func token(for server: MediaServer) -> String? {
        try? tokens.load(id: server.id)
    }

    /// Signs in, keeps the token, and stores the server only if the sign-in worked.
    ///
    /// Adding first and authenticating later would leave a row that never works
    /// and no hint about which of the two facts is wrong.
    @discardableResult
    public func add(client: MediaServerClient, server: MediaServer,
                    username: String, password: String) async throws -> MediaServer {
        var stored = server
        let answer = try await client.signIn(server: server, username: username, password: password)
        var signedIn = server
        signedIn.userID = answer.userID
        guard let libraries = try? await client.libraries(server: signedIn, token: answer.token) else {
            throw MediaServerError("登录成功,但读不到媒体库")
        }
        stored.userID = answer.userID
        if stored.name.isEmpty { stored.name = server.kind.title }
        try tokens.save(id: stored.id, token: answer.token)
        servers.append(stored)
        save()
        status[stored.id] = "已连接 · \(libraries.count) 个媒体库"
        return stored
    }

    /// Checks a server still answers, and says what it found.
    public func test(client: MediaServerClient, server: MediaServer) async {
        guard let token = token(for: server) else {
            status[server.id] = "没有保存的登录,请重新添加"
            return
        }
        do {
            let libraries = try await client.libraries(server: server, token: token)
            status[server.id] = "已连接 · \(libraries.count) 个媒体库"
        } catch {
            status[server.id] = error.localizedDescription
        }
    }

    public func remove(_ server: MediaServer) {
        servers.removeAll { $0.id == server.id }
        status[server.id] = nil
        // The token goes too: a server the user removed must not leave a working
        // credential on the device.
        try? tokens.remove(id: server.id)
        save()
    }

    public func rename(_ server: MediaServer, to name: String) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].name = name
        save()
    }
}
