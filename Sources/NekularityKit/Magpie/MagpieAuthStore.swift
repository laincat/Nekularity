import Foundation

/// Where a provider package's sign-in is kept.
///
/// The sign-in belongs to one provider id and never to a comic source: an AI
/// account and a manga source's cookies are different secrets with different
/// lifetimes, and mixing them makes a leak hard to reason about.
/// JSON text, not a parsed value: the package wrote it, the package reads it
/// back, and re-encoding could reorder keys or round a number it relies on.
public protocol MagpieAuthStore: Sendable {
    func loadAuthJSON(provider: String) throws -> String?
    func saveAuthJSON(provider: String, json: String) throws
    func remove(provider: String) throws
}

/// An account a Magpie provider package signs in to.
public struct MagpieAccount: Codable, Hashable, Sendable {
    public var provider: String
    /// What the package last saved, as JSON text, exactly as it wrote it.
    public var authJSON: String

    public init(provider: String, authJSON: String) {
        self.provider = provider
        self.authJSON = authJSON
    }
}

/// Keeps sign-ins in memory. Tests and previews use it; the app uses the
/// Keychain, because an access token in a plist is readable by anyone who can
/// read the container.
public final class MemoryMagpieAuthStore: MagpieAuthStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    public init() {}

    public func loadAuthJSON(provider: String) throws -> String? {
        lock.withLock { items[provider] }
    }

    public func saveAuthJSON(provider: String, json: String) throws {
        lock.withLock { items[provider] = json }
    }

    public func remove(provider: String) throws {
        lock.withLock { items[provider] = nil }
    }
}

/// Keychain-backed storage, one generic password per provider.
///
/// `kSecAttrAccessibleAfterFirstUnlock` rather than `...WhenUnlocked`: a refresh
/// may run while the phone is locked and the screen is off, and a sign-in that
/// cannot be read then is a package that silently stops working.
public final class KeychainMagpieAuthStore: MagpieAuthStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.laincat.nekularity.magpie") {
        self.service = service
    }

    private func query(_ provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
    }

    public func loadAuthJSON(provider: String) throws -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw MagpieError("the stored sign-in for \(provider) is not text")
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw MagpieError("the Keychain refused to read \(provider) (\(status))")
        }
    }

    public func saveAuthJSON(provider: String, json: String) throws {
        let data = Data(json.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // ThisDeviceOnly: a vendor refresh token restored onto another
            // device from a backup is a working credential in someone else's
            // hands, so it must not travel. AfterFirstUnlock (not
            // WhenUnlocked) keeps a background sign-in refresh working after a
            // reboot before the user unlocks.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(query(provider) as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw MagpieError("the Keychain refused to update \(provider) (\(update))")
        }
        var add = query(provider)
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MagpieError("the Keychain refused to store \(provider) (\(status))")
        }
    }

    public func remove(provider: String) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MagpieError("the Keychain refused to delete \(provider) (\(status))")
        }
    }
}

public struct MagpieError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
