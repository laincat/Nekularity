import Foundation
import Observation

/// Installed comic sources and the indexes they come from.
///
/// Every change to the installed set is written back to `plugins.json`
/// through Core's records, so the next launch restores the same sources.
@MainActor @Observable
public final class SourceLibrary {
    public private(set) var sources: [PluginRecord] = []
    /// Restore failures from the last launch: key → error.
    public private(set) var restoreFailures: [String: String] = [:]

    @ObservationIgnored public let core: CoreClient
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data

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

    /// Restores persisted sources. Call once at launch.
    public func restore() async {
        if let json = core.host.store.loadRecordsJSON() {
            restoreFailures = (try? await core.restore(recordsJSON: json)) ?? [:]
        }
        await refresh()
    }

    public func refresh() async {
        sources = (try? await core.plugins()) ?? []
    }

    /// Installs a script given as text (paste or file import).
    @discardableResult
    public func install(script: String, origin: String) async throws -> PluginRecord {
        let rec = try await core.installComicSource(script, origin: origin)
        try await persist()
        return rec
    }

    /// Downloads and installs a script from url, updating the source when
    /// its key is already installed.
    @discardableResult
    public func install(from url: URL, indexURL: URL? = nil) async throws -> PluginRecord {
        try await installOrReplace(body: try await text(url), origin: url.absoluteString, indexURL: indexURL?.absoluteString ?? "")
    }

    /// Installs or updates the entry of an index.
    @discardableResult
    public func install(entry: IndexEntry, indexURL: URL) async throws -> PluginRecord {
        guard let url = URL(string: entry.url) else { throw CoreError("invalid script URL \(entry.url)") }
        let body = try await text(url)
        if sources.contains(where: { $0.key == entry.key }) {
            let rec = try await core.replace(key: entry.key, type: "comic", body: body, origin: url.absoluteString,
                                             indexURL: indexURL.absoluteString)
            try await persist()
            return rec
        }
        // Core validates the script's executed identity against the index key.
        // A generic duplicate-key fallback must not update another installed source.
        let rec = try await core.installComicEntry(entry, body: body, indexURL: indexURL)
        try await persist()
        return rec
    }

    /// Core is the only one that knows a script's key, so try to install
    /// and fall back to replacing when the key is taken.
    private func installOrReplace(body: String, origin: String, indexURL: String) async throws -> PluginRecord {
        let rec: PluginRecord
        do {
            rec = try await core.installComicSource(body, origin: origin, indexURL: indexURL)
        } catch let e as CoreError {
            // Core refuses a second install of a key it already holds, and it has
            // worded that two ways: "already installed: <key>" and
            // "key(<key>) already exists". Matching only the older wording meant
            // the replace below never ran, so every update of an installed source
            // failed with the very error that was supposed to trigger the update.
            guard let key = Self.existingKey(in: e.message),
                  sources.contains(where: { $0.key == key }) else { throw e }
            rec = try await core.replace(key: key, type: "comic", body: body, origin: origin, indexURL: indexURL)
        }
        try await persist()
        return rec
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
        for source in sources {
            guard let origin = source.origin, let url = URL(string: origin),
                  url.scheme?.hasPrefix("http") == true else { continue }
            let before = source.version
            do {
                let rec = try await install(from: url, indexURL: source.indexUrl.flatMap(URL.init(string:)))
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
        try await core.remove(key: key)
        try core.host.store.removeSource(key: key)
        core.host.cookies.clear(partition: CookiePartition.comic(key))
        try await persist()
    }

    public func setEnabled(_ key: String, _ on: Bool) async throws {
        try await core.setEnabled(key: key, on)
        try await persist()
    }

    /// Downloads an index.json and compares it with the installed sources.
    public func loadIndex(_ url: URL) async throws -> ComicIndex {
        try await core.compareComicIndex(try await text(url), indexURL: url.absoluteString)
    }

    // MARK: Helpers

    private func persist() async throws {
        try core.host.store.saveRecordsJSON(try await core.recordsJSON())
        await refresh()
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
