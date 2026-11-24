import Foundation
import Observation

/// Installed comic sources and the indexes they come from.
///
/// Every change to the installed set runs through a serialized commit path that
/// writes `plugins.json` before cleaning up side state and rolls Core back if
/// persistence fails, so memory and disk never diverge into a half-updated state.
@MainActor @Observable
public final class SourceLibrary {
    public private(set) var sources: [PluginRecord] = []
    /// Restore failures from the last launch: key → error.
    public private(set) var restoreFailures: [String: String] = [:]

    @ObservationIgnored public let core: CoreClient
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var mutating = false
    @ObservationIgnored private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    /// Optional persistence override for tests simulating disk write failures.
    @ObservationIgnored var recordsWriter: (@Sendable (String) throws -> Void)?

    /// `fetch` downloads index and script files. It is separate from the
    /// source transport: these requests carry no source cookies.
    /// The jars sources' cookies live in. Optional so a test can build a library
    /// without storage; a backup restore is the only thing that writes to them
    /// from here, and it does nothing when they are absent.
    public let cookieJars: CookieJars?

    public init(core: CoreClient, fetch: @escaping @Sendable (URL) async throws -> Data = SourceLibrary.plainFetch,
                cookieJars: CookieJars? = nil) {
        self.core = core
        self.fetch = fetch
        self.cookieJars = cookieJars
    }

    public var comicSources: [PluginRecord] { sources.filter(\.isComic) }
    public var novelSources: [PluginRecord] { sources.filter(\.isNovel) }
    public var videoSources: [PluginRecord] { sources.filter(\.isVideo) }

    /// Restores persisted sources. Call once at launch.
    public func restore() async {
        _ = try? await withMutation {
            if let json = core.host.store.loadRecordsJSON() {
                restoreFailures = (try? await core.restore(recordsJSON: json)) ?? [:]
            }
            await refresh()
        }
    }

    public func refresh() async {
        sources = (try? await core.plugins()) ?? []
    }

    /// Installs a script given as text (paste or file import).
    @discardableResult
    public func install(script: String, origin: String) async throws -> PluginRecord {
        try await install(type: PluginRecord.comicType, script: script, origin: origin)
    }

    /// Installs a script of an explicit Core plugin type (`comic`, `novel-js`,
    /// `video-js`, `kazumi-rule`).
    @discardableResult
    public func install(type: String, script: String, origin: String, sha256: String = "") async throws -> PluginRecord {
        try await commitInstall(mode: .script(type: type, sha256: sha256), body: script, origin: origin, indexURL: "")
    }

    /// Installs a `novel-js` script given as text.
    @discardableResult
    public func installNovel(script: String, origin: String, sha256: String = "") async throws -> PluginRecord {
        try await install(type: PluginRecord.novelJSType, script: script, origin: origin, sha256: sha256)
    }

    /// Downloads and installs a comic script from url, updating the source when
    /// its key is already installed.
    @discardableResult
    public func install(from url: URL, indexURL: URL? = nil) async throws -> PluginRecord {
        try await install(type: PluginRecord.comicType, from: url, indexURL: indexURL)
    }

    /// Downloads and installs a plugin of an explicit Core type from url,
    /// updating the source when its key is already installed.
    @discardableResult
    public func install(type: String, from url: URL, indexURL: URL? = nil, sha256: String = "") async throws -> PluginRecord {
        let body = try await text(url)
        return try await commitInstall(mode: .url(type: type, sha256: sha256), body: body, origin: url.absoluteString,
                                       indexURL: indexURL?.absoluteString ?? "")
    }

    /// Downloads and installs a `novel-js` script from url, updating an
    /// already-installed source with the same key.
    @discardableResult
    public func installNovel(from url: URL, indexURL: URL? = nil, sha256: String = "") async throws -> PluginRecord {
        try await install(type: PluginRecord.novelJSType, from: url, indexURL: indexURL, sha256: sha256)
    }

    /// Installs or updates the entry of an index.
    @discardableResult
    public func install(entry: IndexEntry, indexURL: URL) async throws -> PluginRecord {
        guard let url = URL(string: entry.url) else { throw CoreError("invalid script URL \(entry.url)") }
        let body = try await text(url)
        return try await commitInstall(mode: .indexEntry(entry, indexURL), body: body,
                                       origin: url.absoluteString, indexURL: indexURL.absoluteString)
    }

    /// Parses a shared source collection JSON document through Core using the
    /// client's declared capabilities (including `novel-source.js`).
    public func parseCollection(
        _ data: String,
        sourceURL: URL,
        platform: String = "ios",
        capabilities: [String] = SourceCollection.defaultCapabilities
    ) async throws -> SourceCollectionCheck {
        try await core.parseSourceCollection(
            data,
            sourceURL: sourceURL.absoluteString,
            platform: platform,
            capabilities: capabilities
        )
    }

    /// Downloads and parses a shared source collection from `url`.
    public func loadCollection(
        _ url: URL,
        platform: String = "ios",
        capabilities: [String] = SourceCollection.defaultCapabilities
    ) async throws -> SourceCollectionCheck {
        try await parseCollection(try await text(url), sourceURL: url, platform: platform, capabilities: capabilities)
    }

    /// Downloads, verifies and installs one compatible entry from a shared
    /// source collection (including `novel-source.js` entries).
    @discardableResult
    public func install(
        collectionEntry entry: SourceCollection.Entry,
        from collectionURL: URL,
        platform: String = "ios",
        capabilities: [String] = SourceCollection.defaultCapabilities
    ) async throws -> PluginRecord {
        let compat = entry.compatibility(platform: platform, capabilities: capabilities)
        guard compat.compatible else {
            throw CoreError("collection entry \(entry.id) is incompatible: missing \(compat.missing.joined(separator: ", "))")
        }
        guard entry.status != "planned", let artifact = entry.artifact else {
            throw CoreError("collection entry \(entry.id) has no installable artifact")
        }
        guard let pluginType = entry.pluginType else {
            throw CoreError("collection entry \(entry.id) uses unsupported kind \(entry.kind)")
        }
        guard let artifactURL = URL(string: artifact.url) else {
            throw CoreError("invalid artifact URL \(artifact.url)")
        }
        let data = try await fetch(artifactURL)
        try await core.verifySourceArtifact(artifact, data: data)
        guard let body = String(data: data, encoding: .utf8) else {
            throw CoreError("\(artifactURL.lastPathComponent) is not UTF-8 text")
        }
        return try await commitInstall(
            mode: .collectionEntry(type: pluginType, expectedKey: entry.key, sha256: artifact.sha256),
            body: body,
            origin: artifactURL.absoluteString,
            indexURL: collectionURL.absoluteString
        )
    }

    private enum InstallMode {
        case script(type: String, sha256: String)
        case url(type: String, sha256: String)
        case indexEntry(IndexEntry, URL)
        case collectionEntry(type: String, expectedKey: String?, sha256: String)
    }

    /// Single serialized commit path for all install and update variants.
    private func commitInstall(mode: InstallMode, body: String, origin: String, indexURL: String) async throws -> PluginRecord {
        try await withMutation {
            let existingKeys = Set((try await core.plugins()).map(\.key))
            let previousRecordsJSON = try await core.recordsJSON()
            let rec: PluginRecord
            switch mode {
            case .script(let type, let sha256):
                rec = try await core.installPlugin(type: type, body: body, origin: origin, indexURL: indexURL, sha256: sha256)
            case .url(let type, let sha256):
                do {
                    rec = try await core.installPlugin(type: type, body: body, origin: origin, indexURL: indexURL, sha256: sha256)
                } catch let error as CoreError {
                    guard let key = Self.existingKey(in: error.message),
                          existingKeys.contains(key) else { throw error }
                    rec = try await core.replace(key: key, type: type, body: body, origin: origin, indexURL: indexURL, sha256: sha256)
                }
            case .indexEntry(let entry, let index):
                if existingKeys.contains(entry.key) {
                    rec = try await core.replace(key: entry.key, type: PluginRecord.comicType, body: body, origin: origin,
                                                 indexURL: index.absoluteString)
                } else {
                    // Core validates the script's executed identity against the index key.
                    rec = try await core.installComicEntry(entry, body: body, indexURL: index)
                }
            case .collectionEntry(let type, let expectedKey, let sha256):
                if let expectedKey, !expectedKey.isEmpty {
                    if existingKeys.contains(expectedKey) {
                        rec = try await core.replace(key: expectedKey, type: type, body: body, origin: origin,
                                                     indexURL: indexURL, sha256: sha256)
                    } else {
                        let installed = try await core.installPlugin(type: type, body: body, origin: origin,
                                                                     indexURL: indexURL, sha256: sha256)
                        if installed.key != expectedKey {
                            await rollbackInstall(key: installed.key, existedBefore: false,
                                                  previousRecordsJSON: previousRecordsJSON)
                            await refresh()
                            throw CoreError("plugin: the script declares a different key (\(installed.key), expected \(expectedKey))")
                        }
                        rec = installed
                    }
                } else {
                    do {
                        rec = try await core.installPlugin(type: type, body: body, origin: origin,
                                                           indexURL: indexURL, sha256: sha256)
                    } catch let error as CoreError {
                        guard let key = Self.existingKey(in: error.message),
                              existingKeys.contains(key) else { throw error }
                        rec = try await core.replace(key: key, type: type, body: body, origin: origin,
                                                     indexURL: indexURL, sha256: sha256)
                    }
                }
            }
            do {
                try await persistRecords()
            } catch {
                await rollbackInstall(key: rec.key, existedBefore: existingKeys.contains(rec.key),
                                      previousRecordsJSON: previousRecordsJSON)
                await refresh()
                throw error
            }
            await refresh()
            return rec
        }
    }

    /// The key Core names when it refuses to install a source it already has.
    nonisolated static func existingKey(in message: String) -> String? {
        if let start = message.range(of: "key(") {
            let rest = message[start.upperBound...]
            if let close = rest.firstIndex(of: ")") {
                let key = String(rest[rest.startIndex..<close]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { return key }
            }
        }
        if let start = message.range(of: "already installed: ") {
            let key = message[start.upperBound...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { return key }
        }
        return nil
    }

    /// What one source's update attempt did.
    ///
    /// A batch update has three outcomes worth telling apart: the version moved,
    /// it did not, or the attempt failed. Folding "unchanged" into "failed" is how
    /// a working batch looks broken.
    public struct SourceUpdate: Sendable, Identifiable {
        public var key: String
        public var name: String
        public var from: String
        public var to: String
        public var error: String?

        public var id: String { key }
        public var changed: Bool { error == nil && !to.isEmpty && to != from }

        /// One sentence for the alert, because a batch result that needs scrolling
        /// to be understood is a batch result nobody reads.
        public static func summary(_ results: [SourceUpdate]) -> String {
            let updated = results.filter(\.changed)
            let failed = results.filter { $0.error != nil }
            if results.isEmpty { return "没有可从网址更新的源。" }
            var lines: [String] = []
            if !updated.isEmpty {
                lines.append("已更新 \(updated.count) 个:" + updated.map { "\($0.name) \($0.from) → \($0.to)" }.joined(separator: "、"))
            }
            let same = results.count - updated.count - failed.count
            if same > 0 { lines.append("\(same) 个已是最新。") }
            if !failed.isEmpty {
                lines.append("失败 \(failed.count) 个:" + failed.map { "\($0.name):\($0.error ?? "")" }.joined(separator: ";"))
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Updates every source that came from a URL, and reports each outcome.
    ///
    /// Sources installed from pasted text have nowhere to update *from*, so they
    /// are skipped rather than reported as failures — that would be the app
    /// blaming a source for a fact about how it was installed.
    public func updateAll() async -> [SourceUpdate] {
        var results: [SourceUpdate] = []
        let snapshot = (try? await core.plugins()) ?? sources
        for source in snapshot {
            guard let origin = source.origin, let url = URL(string: origin),
                  url.scheme?.hasPrefix("http") == true else { continue }
            let before = source.version
            do {
                let rec = try await install(type: source.type, from: url, indexURL: source.indexUrl.flatMap(URL.init(string:)))
                results.append(SourceUpdate(key: rec.key, name: rec.name, from: before, to: rec.version))
            } catch {
                results.append(SourceUpdate(key: source.key, name: source.name, from: before, to: before,
                                            error: CoreError.readable(error.localizedDescription)))
            }
        }
        await refresh()
        return results
    }

    public func remove(_ key: String) async throws {
        try await withMutation {
            let previousRecordsJSON = try await core.recordsJSON()
            let removed = (try? await core.plugins())?.first(where: { $0.key == key })
            try await core.remove(key: key)
            do {
                try await persistRecords()
            } catch {
                if let single = Self.recordJSON(for: key, in: previousRecordsJSON) {
                    _ = try? await core.restore(recordsJSON: single)
                }
                await refresh()
                throw error
            }
            try core.host.store.removeSource(key: key)
            core.host.cookies.clear(partition: CookiePartition.comic(key))
            if removed?.isVideo == true {
                core.host.cookies.clear(partition: CookiePartition.video(key))
            }
            await refresh()
        }
    }

    public func setEnabled(_ key: String, _ on: Bool) async throws {
        try await withMutation {
            let previousEnabled = (try? await core.plugins())?.first(where: { $0.key == key })?.enabled
            try await core.setEnabled(key: key, on)
            do {
                try await persistRecords()
            } catch {
                if let previousEnabled {
                    try? await core.setEnabled(key: key, previousEnabled)
                }
                await refresh()
                throw error
            }
            await refresh()
        }
    }

    /// Downloads an index.json and compares it with the installed sources.
    public func loadIndex(_ url: URL) async throws -> ComicIndex {
        try await core.compareComicIndex(try await text(url), indexURL: url.absoluteString)
    }

    // MARK: Helpers

    private func withMutation<T>(_ body: @MainActor () async throws -> T) async throws -> T {
        if mutating {
            await withCheckedContinuation { continuation in
                mutationWaiters.append(continuation)
            }
        }
        mutating = true
        defer {
            if mutationWaiters.isEmpty {
                mutating = false
            } else {
                let next = mutationWaiters.removeFirst()
                next.resume()
            }
        }
        return try await body()
    }

    private func persistRecords() async throws {
        let json = try await core.recordsJSON()
        if let recordsWriter {
            try recordsWriter(json)
        } else {
            try core.host.store.saveRecordsJSON(json)
        }
    }

    private func rollbackInstall(key: String, existedBefore: Bool, previousRecordsJSON: String) async {
        try? await core.remove(key: key)
        if existedBefore, let single = Self.recordJSON(for: key, in: previousRecordsJSON) {
            _ = try? await core.restore(recordsJSON: single)
        }
    }

    nonisolated static func recordJSON(for key: String, in recordsJSON: String) -> String? {
        guard let parsed = try? JSONValue.parse(recordsJSON),
              let items = parsed.array,
              let matched = items.first(where: { $0["key"]?.stringValue == key }) else {
            return nil
        }
        return JSONValue.array([matched]).jsonText
    }

    private func text(_ url: URL) async throws -> String {
        let data = try await fetch(url)
        guard let s = String(data: data, encoding: .utf8) else { throw CoreError("\(url.lastPathComponent) is not UTF-8 text") }
        return s
    }

    /// GET over a session with no cookies: 4 MiB limit, http(s) only.
    ///
    /// The limit is enforced while the body arrives, through the same transport
    /// the sources use: a `Data` that is only measured after it has been buffered
    /// has already spent the memory the limit exists to protect.
    public nonisolated static let plainFetch: @Sendable (URL) async throws -> Data = { url in
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw CoreError("only http and https URLs") }
        let transport = URLSessionTransport(cookies: CookieJars(file: nil), defaultUserAgent: plainUserAgent,
                                            timeout: 30)
        transport.maxBodyBytes = 4 << 20
        let response = try await transport.send(.init(id: 0, method: "GET", url: url, headers: [:],
                                                      body: nil, useCookies: false, partition: "index"))
        guard (200..<300).contains(response.status) else {
            throw CoreError("download failed: HTTP \(response.status)")
        }
        return response.body
    }

    private nonisolated static let plainUserAgent = "Nekularity/1.0"
}
