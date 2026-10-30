import Foundation

/// The switches a provider plugin declares, and the values the user chose.
///
/// Kept per provider, like the sign-in: one plugin's "free models only" must not
/// answer for another's. The file is small and human-readable so a bad value can
/// be seen rather than guessed at.
public final class MagpieOptionStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.url = directory.appendingPathComponent("magpie-options.json")
    }

    /// Every switch for one provider, keyed by the plugin's own option key.
    public func values(provider: String) throws -> [String: Bool] {
        let all = try read()
        var out: [String: Bool] = [:]
        for (key, value) in all where key.hasPrefix(provider + "|") {
            out[String(key.dropFirst(provider.count + 1))] = value
        }
        return out
    }

    public func set(provider: String, key: String, value: Bool) throws {
        var all = try read()
        all[provider + "|" + key] = value
        try write(all)
    }

    /// The values in the shape Core reads: `provider|option` to the choice.
    public func optionsJSON(provider: String) throws -> [String: Bool] {
        var all = try read()
        let prefix = provider + "|"
        all = all.filter { $0.key.hasPrefix(prefix) }
        return all
    }

    /// A declaration the plugin made, with the value the user chose. A switch
    /// nobody touched keeps the plugin's own default, which is what it expects.
    public struct Resolved: Sendable, Hashable {
        public var key: String
        public var label: String
        public var description: String
        public var confirm: String
        public var value: Bool
    }

    public func resolve(_ declared: [MagpieAuthSpec.Option], provider: String) throws -> [Resolved] {
        var chosen = try read()
        return declared.map { option in
            let key = provider + "|" + option.key
            return Resolved(
                key: option.key,
                label: option.label.isEmpty ? option.key : option.label,
                description: option.description,
                confirm: option.confirm,
                value: chosen[key] ?? option.default
            )
        }
    }

    private func read() throws -> [String: Bool] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Bool]) ?? [:]
    }

    private func write(_ values: [String: Bool]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: url, options: .atomic)
    }
}
