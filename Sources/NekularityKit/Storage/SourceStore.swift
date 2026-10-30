import Foundation

/// File-backed storage for source data, settings and plugin records.
///
/// Layout under `root`:
///
///     plugins.json            Core records (with script bodies)
///     sources/<key>.json      {"data": {...}, "settings": {...}}
///
/// Values are kept as the exact JSON text Core passed in, so large integers
/// and key order survive. Writes are atomic. All methods are thread-safe;
/// Core calls them from its own threads.
public final class SourceStore: @unchecked Sendable {
    public let root: URL
    private let lock = NSLock()
    /// key → (data, settings), loaded lazily.
    private var cache: [String: Entry] = [:]

    struct Entry {
        var data = OrderedObject()
        var settings = OrderedObject()
    }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appending(path: "sources"), withIntermediateDirectories: true)
    }

    // MARK: Plugin records

    public func loadRecordsJSON() -> String? {
        lock.lock(); defer { lock.unlock() }
        return try? String(contentsOf: root.appending(path: "plugins.json"), encoding: .utf8)
    }

    public func saveRecordsJSON(_ json: String) throws {
        lock.lock(); defer { lock.unlock() }
        try Data(json.utf8).write(to: root.appending(path: "plugins.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Source data

    /// The JSON text for dataKey, or nil.
    public func loadData(key: String, dataKey: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try entry(key).data[dataKey].map(\.jsonText)
    }

    public func saveData(key: String, dataKey: String, json: String) throws {
        let value = try JSONValue.parse(json)
        lock.lock(); defer { lock.unlock() }
        var e = try entry(key)
        e.data.set(dataKey, value)
        try write(key, e)
    }

    public func deleteData(key: String, dataKey: String) throws {
        lock.lock(); defer { lock.unlock() }
        var e = try entry(key)
        guard e.data.remove(dataKey) else { return }
        try write(key, e)
    }

    public func loadSetting(key: String, settingKey: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try entry(key).settings[settingKey].map(\.jsonText)
    }

    public func saveSetting(key: String, settingKey: String, json: String) throws {
        let value = try JSONValue.parse(json)
        lock.lock(); defer { lock.unlock() }
        var e = try entry(key)
        e.settings.set(settingKey, value)
        try write(key, e)
    }

    /// Logged in means the source stored an "account" value, as in the
    /// official app.
    public func isLogged(key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let v = (try? entry(key))?.data["account"] else { return false }
        if case .null = v { return false }
        return true
    }

    /// Removes everything stored for a source (on uninstall).
    public func removeSource(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        cache[key] = nil
        let url = try file(key)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    // MARK: Files; callers hold the lock.

    private func file(_ key: String) throws -> URL {
        // Keys are validated by Core, but never trust them as path parts.
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }) else {
            throw CoreError("invalid source key \(key)")
        }
        return root.appending(path: "sources/\(key).json")
    }

    private func entry(_ key: String) throws -> Entry {
        if let e = cache[key] { return e }
        var e = Entry()
        let url = try file(key)
        if let text = try? String(contentsOf: url, encoding: .utf8), case .object(let o) = try JSONValue.parse(text) {
            if case .object(let d)? = o["data"] { e.data = d }
            if case .object(let s)? = o["settings"] { e.settings = s }
        }
        cache[key] = e
        return e
    }

    private func write(_ key: String, _ e: Entry) throws {
        let doc = JSONValue.object(OrderedObject([("data", .object(e.data)), ("settings", .object(e.settings))]))
        try Data(doc.jsonText.utf8).write(to: try file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cache[key] = e
    }
}

extension OrderedObject {
    /// Replaces the value of key in place, or appends it.
    mutating func set(_ key: String, _ value: JSONValue) {
        if let i = entries.firstIndex(where: { $0.0 == key }) { entries[i].1 = value } else { entries.append((key, value)) }
    }

    /// Removes key; returns whether it was present.
    @discardableResult
    mutating func remove(_ key: String) -> Bool {
        guard let i = entries.firstIndex(where: { $0.0 == key }) else { return false }
        entries.remove(at: i)
        return true
    }
}
