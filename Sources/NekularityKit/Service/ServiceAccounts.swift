import Foundation
import Security

/// The account values one service may read.
///
/// A service that asks for the `secrets` permission reads values the person
/// entered for it. They are kept per environment and per service, and they are
/// only ever handed to Core for the duration of one call: Core has no store of
/// its own, so a value the client does not pass cannot be reached.
public protocol ServiceAccounts: Sendable {
    func values(service: String) throws -> [String: String]
    func set(service: String, key: String, value: String) throws
    func remove(service: String, key: String) throws
    /// Forgets every value of one service: a removed package must not leave
    /// working credentials behind in the Keychain.
    func removeAll(service: String) throws
}

public extension ServiceAccounts {
    func keys(service: String) -> [String] {
        ((try? values(service: service)) ?? [:]).keys.sorted()
    }
}

/// In memory: for tests and previews, never for a real account.
public final class MemoryServiceAccounts: ServiceAccounts, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [String: String]] = [:]

    public init() {}

    public func values(service: String) throws -> [String: String] {
        lock.withLock { storage[service] ?? [:] }
    }

    public func set(service: String, key: String, value: String) throws {
        lock.withLock { storage[service, default: [:]][key] = value }
    }

    public func remove(service: String, key: String) throws {
        lock.withLock { storage[service]?[key] = nil }
    }

    public func removeAll(service: String) throws {
        lock.withLock { storage[service] = nil }
    }
}

/// The Keychain, one item per service holding a JSON object of key to value.
///
/// ThisDeviceOnly and AfterFirstUnlock for the same reasons as a vendor
/// sign-in: a credential restored onto another device is a working credential
/// in someone else's hands, and a service run in the background after a reboot
/// should still find it.
public final class KeychainServiceAccounts: ServiceAccounts, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.laincat.nekularity.services") {
        self.service = service
    }

    private func query(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    public func values(service id: String) throws -> [String: String] {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return [:] }
            guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                throw ServiceAccountError("the stored account values for \(id) are not readable")
            }
            return decoded
        case errSecItemNotFound:
            return [:]
        default:
            throw ServiceAccountError("the Keychain refused to read the account values for \(id) (\(status))")
        }
    }

    public func set(service id: String, key: String, value: String) throws {
        var all = try values(service: id)
        all[key] = value
        try write(id, all)
    }

    public func remove(service id: String, key: String) throws {
        var all = try values(service: id)
        all[key] = nil
        try write(id, all)
    }

    public func removeAll(service id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ServiceAccountError("the Keychain refused to delete the account values for \(id) (\(status))")
        }
    }

    private func write(_ id: String, _ all: [String: String]) throws {
        guard let data = try? JSONEncoder().encode(all) else {
            throw ServiceAccountError("the account values for \(id) could not be encoded")
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw ServiceAccountError("the Keychain refused to update the account values for \(id) (\(update))")
        }
        var add = query(id)
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ServiceAccountError("the Keychain refused to store the account values for \(id) (\(status))")
        }
    }
}

public struct ServiceAccountError: Error, LocalizedError, Equatable {
    private let message: String
    init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
