import Foundation

/// A source's declared settings together with their effective values
/// (stored profile values merged over declared defaults).
public struct SourceSettingsSnapshot: Sendable, Equatable {
    public var settings: [SourceSetting]
    public var values: [String: JSONValue]

    public init(settings: [SourceSetting], values: [String: JSONValue]) {
        self.settings = settings
        self.values = values
    }
}

extension SourceSetting {
    /// Whether `value` satisfies this setting's declared validator.
    public func accepts(_ value: JSONValue) -> Bool {
        guard kind == .text, let pattern = validator, !pattern.isEmpty else { return true }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        guard let text = value.stringValue else { return true }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }
}

extension SourceLibrary {
    /// Loads a source's declared settings from Core and merges stored values
    /// from this library's profile store over declared defaults.
    public func loadSettings(key: String) async throws -> SourceSettingsSnapshot {
        let declared = try await core.settings(key: key)
        let store = core.host.store
        var values: [String: JSONValue] = [:]
        for setting in declared {
            if let stored = try store.loadSetting(key: key, settingKey: setting.key),
               let value = try? JSONValue.parse(stored) {
                values[setting.key] = value
            } else if let fallback = setting.default {
                values[setting.key] = fallback
            }
        }
        return SourceSettingsSnapshot(settings: declared, values: values)
    }

    /// Validates and persists one source setting into this library's profile store,
    /// keeping exact `JSONValue` fidelity without converting through `Double`.
    /// Returns `false` without writing when the setting's validator rejects `value`.
    @discardableResult
    public func saveSetting(key: String, setting: SourceSetting, value: JSONValue) throws -> Bool {
        guard setting.accepts(value) else { return false }
        try core.host.store.saveSetting(key: key, settingKey: setting.key, json: value.jsonText)
        return true
    }

    /// Invokes a callback-type source setting through Core.
    public func runSettingCallback(key: String, setting: String) async throws -> String {
        try await core.callSettingCallback(key: key, setting: setting)
    }
}
