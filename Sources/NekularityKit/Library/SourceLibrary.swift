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
        return try await installOrReplace(body: body, origin: url.absoluteString, indexURL: indexURL.absoluteString)
    }

    /// Core is the only one that knows a script's key, so try to install
    /// and fall back to replacing when the key is taken.
    private func installOrReplace(body: String, origin: String, indexURL: String) async throws -> PluginRecord {
        let rec: PluginRecord
        do {
            rec = try await core.installComicSource(body, origin: origin, indexURL: indexURL)
        } catch let e as CoreError where e.message.contains("already installed") {
            guard let key = e.message.components(separatedBy: "already installed: ").last?.trimmingCharacters(in: .whitespaces),
                  sources.contains(where: { $0.key == key }) else { throw e }
            rec = try await core.replace(key: key, type: "comic", body: body, origin: origin, indexURL: indexURL)
        }
        try await persist()
        return rec
    }

    public func remove(_ key: String) async throws {
        try await core.remove(key: key)
        try core.host.store.removeSource(key: key)
        core.host.cookies.clear(partition: "comic:\(key)")
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

    /// GET over an ephemeral session: no cookies, 4 MiB limit, http(s) only.
    public nonisolated static let plainFetch: @Sendable (URL) async throws -> Data = { url in
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw CoreError("only http and https URLs") }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        let (data, response) = try await URLSession(configuration: config).data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CoreError("download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard data.count <= 4 << 20 else { throw CoreError("file larger than 4 MiB") }
        return data
    }
}
