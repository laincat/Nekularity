import Foundation
import Security

/// Where a standard protocol's own API key lives.
///
/// It is a separate Keychain account from any Magpie sign-in: an OpenAI key and
/// a provider package's refresh token are different secrets with different
/// lifetimes, and mixing them would make a leak hard to reason about.
///
/// The account is the vendor ("openai", "anthropic"), so switching protocol
/// inside one vendor keeps the same key, which is what a user expects.
public final class StandardAIKeyStore: @unchecked Sendable {
    private let service: String

    public init(service: String = "com.laincat.nekularity.standardai") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The stored key for a vendor, or nil.
    public func load(vendor: String) throws -> String? {
        var q = query(vendor.lowercased())
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(q as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw StandardAIError("这个账号存的密钥不是文本")
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw StandardAIError("钥匙串拒绝读取密钥")
        }
    }

    public func save(vendor: String, key: String) throws {
        let account = vendor.lowercased()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StandardAIError("密钥是空的") }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            // ThisDeviceOnly: a vendor key restored onto another device from a
            // backup is a working credential in someone else's hands.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw StandardAIError("钥匙串拒绝更新密钥") }
        var add = query(account)
        add.merge(attributes) { _, new in new }
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw StandardAIError("钥匙串拒绝保存密钥")
        }
    }

    public func remove(vendor: String) throws {
        let status = SecItemDelete(query(vendor.lowercased()) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StandardAIError("钥匙串拒绝删除密钥")
        }
    }
}

/// Where the non-secret part of the configuration is kept: protocol, address,
/// model and token limit. A key never goes here.
public struct StandardAISettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "standardAI") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> StandardAIConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(StandardAIConfig.self, from: data) else {
            return StandardAIConfig()
        }
        return config
    }

    public func save(_ config: StandardAIConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
