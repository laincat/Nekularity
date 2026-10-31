import Foundation
import VeneraCatCore

/// Errors from Core calls.
public struct CoreError: Error, LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public init(_ error: NSError) { message = error.localizedDescription }
    public var errorDescription: String? { CoreError.readable(message) }

    /// The call was cancelled (task cancellation or Core.Cancel).
    public var isCancelled: Bool { message.contains("context canceled") }

    /// The source declared no such image callback; the caller should carry on
    /// with what it already has rather than treat this as a failure.
    public var isCallbackAbsent: Bool { message.contains("no such callback") }

    /// Core speaks English and its text is what a developer needs; the
    /// interface is Chinese. Well-known failures get a Chinese sentence, and
    /// anything else keeps Core's own words after a Chinese prefix, so a
    /// report never shows a bare English sentence but still carries the
    /// original for a bug report.
    public static func readable(_ message: String) -> String {
        let lower = message.lowercased()
        func has(_ needle: String) -> Bool { lower.contains(needle) }
        if has("context canceled") || has("cancelled") {
            return "操作已取消"
        }
        if has("no such source") || has("source not found") || has("unknown source") {
            return "找不到这个漫画源,可能已被删除"
        }
        if has("not installed") {
            return "漫画源还未安装"
        }
        if has("timeout") || has("deadline exceeded") {
            return "网络超时,请稍后重试"
        }
        if has("no such comic") || has("comic not found") {
            return "源里找不到这部漫画"
        }
        if has("challenge") || has("cloudflare") || has("forbidden") || has("403") {
            return "源要求人机验证或拒绝了请求"
        }
        // ATS refuses plain http before the request leaves the app. Saying "network
        // error" would send the user to check their connection for a policy refusal.
        if has("-1022") || has("app transport security") || has("secure connection") {
            return "这次连接被 iOS 的传输安全策略(ATS)拒绝了。应用的配置允许 http,所以看到这句通常意味着 ATS 配置没有生效,请连同源的名字一起反馈。"
        }
        if has("permission") || has("not allowed") {
            return "没有权限执行这个操作"
        }
        if message.isEmpty {
            return "操作失败,源没有给出原因"
        }
        return "源返回错误:" + message
    }
}

/// Async wrapper around the gomobile `MobileCore`.
///
/// gomobile methods block until Core is done, so every call runs on a
/// dedicated background queue and is cancelled through Core's call IDs when
/// the Swift task is cancelled. Screens use this type only; they never touch
/// the generated `Mobile*` types.
/// `@unchecked Sendable`: the only stored state is the immutable Core
/// handle, and Go synchronises calls into it.
public final class CoreClient: @unchecked Sendable {
    private let core: MobileCore
    public let host: CoreHost

    /// Concurrent: Core serialises work per source itself, and different
    /// sources may run in parallel.
    private let queue = DispatchQueue(label: "nekularity.core", qos: .userInitiated, attributes: .concurrent)

    public init(config: CoreConfig, host: CoreHost) throws {
        var err: NSError?
        let json = try String(decoding: JSONEncoder().encode(config), as: UTF8.self)
        guard let core = MobileNew(json, host, &err) else {
            throw err.map(CoreError.init) ?? CoreError("Core did not start")
        }
        self.core = core
        self.host = host
        host.attach(core)
    }

    deinit { try? core.close() }

    // MARK: Plumbing

    /// Runs a blocking Core call off the caller's thread. `body` receives a
    /// call ID that cancels the call when the task is cancelled.
    private func run<T: Sendable>(cancellable: Bool = true, _ body: @escaping @Sendable (MobileCore, Int64) throws -> T) async throws -> T {
        // MobileCore is an Objective-C class without a Sendable annotation;
        // Core is safe to call from any thread.
        nonisolated(unsafe) let core = self.core
        let id = cancellable ? core.newCall() : 0
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (k: CheckedContinuation<T, Error>) in
                queue.async {
                    do { k.resume(returning: try body(core, id)) } catch let e as NSError {
                        k.resume(throwing: CoreError(e))
                    }
                }
            }
        } onCancel: {
            if id != 0 { core.cancel(id) }
        }
    }

    /// Converts gomobile's `(result, NSErrorPointer)` shape into `throws`.
    private static func call(_ body: (NSErrorPointer) -> String) throws -> String {
        var err: NSError?
        let out = body(&err)
        if let err { throw err }
        return out
    }

    /// Every Core result is decoded with key order and exact numbers kept.
    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try OrderedJSONDecoder.decode(type, from: json)
    }

    // MARK: Plugins

    /// Installs a comic source script. `origin` and `indexURL` record where
    /// it came from; `sha256` is checked when given.
    public func installComicSource(_ body: String, origin: String, indexURL: String = "", sha256: String = "") async throws -> PluginRecord {
        let out = try await run { core, id in
            try Self.call { core.install(id, typ: "comic", body: body, origin: origin, indexURL: indexURL, sha256: sha256, error: $0) }
        }
        return try Self.decode(PluginRecord.self, out)
    }

    /// Replaces an installed plugin; the old version stays on failure.
    public func replace(key: String, type: String, body: String, origin: String, indexURL: String = "", sha256: String = "") async throws -> PluginRecord {
        let out = try await run { core, id in
            try Self.call { core.replace(id, key: key, typ: type, body: body, origin: origin, indexURL: indexURL, sha256: sha256, error: $0) }
        }
        return try Self.decode(PluginRecord.self, out)
    }

    /// Re-activates persisted records. Returns key → error for failures.
    public func restore(recordsJSON: String) async throws -> [String: String] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.restore(recordsJSON, error: $0) } }
        return try Self.decode([String: String].self, out)
    }

    public func remove(key: String) async throws {
        try await run(cancellable: false) { core, _ in try core.remove(key) }
    }

    public func setEnabled(key: String, _ on: Bool) async throws {
        try await run(cancellable: false) { core, _ in try core.setEnabled(key, on: on) }
    }

    /// Installed plugins without script bodies.
    public func plugins() async throws -> [PluginRecord] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.plugins($0) } }
        return try Self.decode([PluginRecord].self, out)
    }

    /// Installed plugins with bodies, as JSON, for persistence.
    public func recordsJSON() async throws -> String {
        try await run(cancellable: false) { core, _ in try Self.call { core.records($0) } }
    }

    /// Parses an index.json and compares it with the installed sources.
    public func compareComicIndex(_ data: String, indexURL: String) async throws -> ComicIndex {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.compareComicIndex(data, indexURL: indexURL, error: $0) } }
        return try Self.decode(ComicIndex.self, out)
    }

    // MARK: Standard AI

    /// Builds a request for one of Core's built-in standard protocols without
    /// sending it. The wire form is returned so a caller can send it on its own
    /// connection, which is where streaming will go.
    public func buildAIRequest(configJSON: String, bodyJSON: String) async throws -> StandardAIWireRequest {
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.buildAIRequest(configJSON, bodyJSON: bodyJSON, error: $0) }
        }
        return try JSONDecoder().decode(StandardAIWireRequest.self, from: Data(out.utf8))
    }

    /// The model-list request for the same root and credentials: a GET with no
    /// body. Core builds it; the caller sends it.
    public func buildAIModelsRequest(configJSON: String) async throws -> StandardAIWireRequest {
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.buildAIModelsRequest(configJSON, error: $0) }
        }
        return try JSONDecoder().decode(StandardAIWireRequest.self, from: Data(out.utf8))
    }

    /// Builds and performs a standard request through this client's own
    /// transport. The answer carries `streamed` so a caller can tell the truth
    /// about a reply that arrived whole.
    public func sendAIRequest(configJSON: String, bodyJSON: String) async throws -> StandardAIAnswer {
        let out = try await run { core, id in
            try Self.call { core.sendAIRequest(id, configJSON: configJSON, bodyJSON: bodyJSON, error: $0) }
        }
        return try JSONDecoder().decode(StandardAIAnswer.self, from: Data(out.utf8))
    }

    // MARK: Backups

    /// Reads a `.venera` file and returns what it holds. Core unwinds the
    /// archive and its sqlite tables; `knownKeys` helps resolve type hashes.
    public func readBackup(path: String, tempDir: String, knownKeys: [String]) async throws -> BackupPlan {
        let keys = try Self.encodeKnownKeys(knownKeys)
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.readBackup(path, tempDir: tempDir, knownKeysJSON: keys, error: $0) }
        }
        return try Self.decode(BackupPlan.self, out)
    }

    /// Builds the plan a restore would write. Every part is selected here:
    /// settings and cookies are deliberately left out, because a backup's
    /// device settings should not overwrite this device's.
    public func planBackup(path: String, tempDir: String, knownKeys: [String],
                           includeCookies: Bool = false) async throws -> BackupPlan {
        let keys = try Self.encodeKnownKeys(knownKeys)
        let cookies = includeCookies ? "true" : "false"
        let selection = """
        {"history":true,"favorites":true,"imageFavorites":true,"settings":false,        "searchHistory":true,"sources":true,"sourceData":true,"cookies":\(cookies)}
        """
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.planBackup(path, tempDir: tempDir, knownKeysJSON: keys, selectionJSON: selection, error: $0) }
        }
        return try Self.decode(BackupPlan.self, out)
    }

    private static func encodeKnownKeys(_ keys: [String]) throws -> String {
        let data = try JSONEncoder().encode(keys)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Comic sources

    /// Calls `ComicSource.<path>(args...)` and returns the raw JSON result.
    public func callComic(key: String, path: String, args: [JSONValue] = []) async throws -> String {
        let argsJSON = JSONValue.array(args).jsonText
        return try await run { core, id in
            try Self.call { core.callComic(id, key: key, path: path, argsJSON: argsJSON, error: $0) }
        }
    }

    public func hasComic(key: String, path: String) async -> Bool {
        (try? await run(cancellable: false) { core, _ in core.hasComic(key, path: path) }) ?? false
    }

    /// The source's search filters. search.load takes one value per group,
    /// so a search needs these defaults even when no filter is shown.
    public func searchOptions(key: String) async throws -> [SearchOptionGroup] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.searchOptions(key, error: $0) } }
        return try Self.decode([SearchOptionGroup].self, out)
    }

    /// The settings a source declares; empty when it declares none. Values are
    /// kept as JSON, because a source may declare numbers or booleans.
    public func settings(key: String) async throws -> [SourceSetting] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.settings(key, error: $0) } }
        return try Self.decode([SourceSetting].self, out)
    }

    /// `search.load(keyword, options, page)`; options holds one value per
    /// group of `searchOptions`.
    public func search(key: String, keyword: String, page: Int, options: [String]) async throws -> ComicPage {
        let out = try await callComic(key: key, path: "search.load",
                                      args: [.string(keyword), .array(options.map(JSONValue.string)), .number(String(page))])
        return try Self.decode(ComicPage.self, out)
    }

    /// Cursor-based comic sources accept null for the first page.
    public func searchNext(key: String, keyword: String, cursor: String?, options: [String]) async throws -> ComicPage {
        let out = try await callComic(key: key, path: "search.loadNext",
                                      args: [.string(keyword), .array(options.map(JSONValue.string)), cursor.map(JSONValue.string) ?? .null])
        return try Self.decode(ComicPage.self, out)
    }

    /// The browses a source offers (its `explore` list); empty when it has
    /// none.
    public func explorePages(key: String) async throws -> [ExplorePage] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.explorePages(key, error: $0) } }
        return try Self.decode([ExplorePage].self, out)
    }

    /// Loads one browse. `page` is the page number for
    /// "multiPageComicList" browses and the index for "mixed" ones; the
    /// other kinds ignore it.
    public func explore(key: String, index: Int, page: Int = 1) async throws -> ExploreResult {
        let pages = (try? await explorePages(key: key)) ?? []
        let type = pages.indices.contains(index) ? pages[index].type : ""
        let out = try await callComic(key: key, path: "explore[\(index)].load",
                                      args: [.number(String(max(1, page)))])
        return try Self.decodeExplore(type: type, out)
    }

    /// The shapes differ by browse type, so the decoding does too.
    private static func decodeExplore(type: String, _ json: String) throws -> ExploreResult {
        switch type {
        case "multiPageComicList":
            let page = try Self.decode(ComicPage.self, json)
            return ExploreResult(sections: [ExploreSection(title: "", comics: page.comics)], maxPage: page.maxPage ?? 0)
        case "mixed":
            // {data: [Comic[] | {title, comics}], maxPage}
            guard case .object(let o) = try JSONValue.parse(json) else { return ExploreResult(sections: [], maxPage: 0) }
            var sections: [ExploreSection] = []
            if case .array(let items)? = o["data"] {
                sections = try exploreSections(items)
            }
            var maxPage = 0
            if let n = o["maxPage"]?.stringValue, let v = Int(n) { maxPage = v }
            return ExploreResult(sections: sections, maxPage: maxPage)
        case "multiPartPage":
            let parts = try JSONValue.parse(json).array ?? []
            return ExploreResult(sections: try exploreSections(parts), maxPage: 0)
        default:
            // singlePageWithMultiPart: {partTitle: [comic, ...]}, in order.
            guard case .object(let o) = try JSONValue.parse(json) else { return ExploreResult(sections: [], maxPage: 0) }
            var sections: [ExploreSection] = []
            for (title, value) in o.entries {
                guard case .array(let items) = value else { continue }
                let comics = items.compactMap { try? Comic(json: $0) }
                if !comics.isEmpty { sections.append(ExploreSection(title: title, comics: comics)) }
            }
            return ExploreResult(sections: sections, maxPage: 0)
        }
    }

    private static func exploreSections(_ items: [JSONValue]) throws -> [ExploreSection] {
        var out: [ExploreSection] = []
        for item in items {
            switch item {
            case .array(let comics):
                let list = comics.compactMap { try? Comic(json: $0) }
                if !list.isEmpty { out.append(ExploreSection(title: "", comics: list)) }
            case .object(let o):
                guard case .array(let comics)? = o["comics"] else { continue }
                let list = comics.compactMap { try? Comic(json: $0) }
                if !list.isEmpty { out.append(ExploreSection(title: o["title"]?.stringValue ?? "", comics: list)) }
            default:
                continue
            }
        }
        return out
    }

    /// `comic.loadInfo(id)`. Decoded with key order kept, because chapter
    /// order is reading order.
    public func details(key: String, comicID: String) async throws -> ComicDetails {
        let out = try await callComic(key: key, path: "comic.loadInfo", args: [.string(comicID)])
        return try Self.decode(ComicDetails.self, out)
    }

    /// `comic.loadEp(comicId, epId)`.
    public func chapterImages(key: String, comicID: String, chapterID: String?) async throws -> [String] {
        let out = try await callComic(key: key, path: "comic.loadEp",
                                      args: [.string(comicID), chapterID.map(JSONValue.string) ?? .null])
        return try Self.decode(ChapterImages.self, out).images
    }

    /// `comic.onImageLoad(url, comicId, epId)`: request options for one
    /// image, plus a handle for the callbacks the source declared.
    public func imageRequest(key: String, url: String, comicID: String, chapterID: String?) async throws -> ImageRequest {
        guard await hasComic(key: key, path: "comic.onImageLoad") else { return ImageRequest(url: url) }
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.imageConfig(key, url: url, comic: comicID, chapter: chapterID ?? "", thumbnail: false, error: $0) }
        }
        return try ImageRequest(json: out, fallbackURL: url)
    }

    /// `comic.onThumbnailLoad(url)` for covers.
    public func thumbnailRequest(key: String, url: String) async throws -> ImageRequest {
        guard await hasComic(key: key, path: "comic.onThumbnailLoad") else { return ImageRequest(url: url) }
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.imageConfig(key, url: url, comic: "", chapter: "", thumbnail: true, error: $0) }
        }
        var request = try ImageRequest(json: out, fallbackURL: url)
        // The official client documents modifyImage and onLoadFailed as ignored
        // for thumbnails: a cover is small and a pixel pass would cost more than
        // it gains.
        request.modifyImage = ""
        // onResponse stays: a scrambled cover still has to be made readable.
        request.callbacks = request.callbacks.filter { $0 != "onLoadFailed" }
        return request
    }

    /// Runs the config's `onResponse` over a fetched body: a source may
    /// decrypt or rewrite what the server sent. Returns nil when the source
    /// declared no such callback.
    public func applyImageResponse(key: String, handle: String, body: Data) async throws -> Data? {
        let out = try await run(cancellable: true) { core, _ in
            try Self.call { core.applyImageResponse(key, handle: handle, bodyB64: body.base64EncodedString(), error: $0) }
        }
        guard !out.isEmpty, let data = Data(base64Encoded: out) else { return nil }
        return data
    }

    /// The next mirror a config offers, when the first address did not work.
    /// nil when the source declared no fallback.
    public func imageFallback(key: String, handle: String) async throws -> ImageRequest? {
        let out: String
        do {
            out = try await run(cancellable: true) { core, _ in
                try Self.call { core.imageFallback(key, handle: handle, error: $0) }
            }
        } catch let error as CoreError where error.isCallbackAbsent {
            return nil
        }
        let request = try ImageRequest(json: out, fallbackURL: "")
        return request.url.isEmpty ? nil : request
    }

    /// Runs a source's `modifyImage` script over one decoded image: iOS has no
    /// JavaScript of its own, so Core runs the script and the pixels make the
    /// trip as base64 RGBA. Throws when the script produced no image, which the
    /// loader treats like a failed load.
    public func modifyImage(key: String, script: String, width: Int, height: Int, rgba: Data) async throws -> (width: Int, height: Int, rgba: Data) {
        let out = try await run(cancellable: true) { core, _ in
            try Self.call {
                core.modifyImage(key, script: script, width: width, height: height,
                                 rgbaB64: rgba.base64EncodedString(), error: $0)
            }
        }
        let value = try JSONValue.parse(out)
        guard case .object(let o) = value,
              let w = o["width"]?.stringValue.flatMap(Int.init),
              let h = o["height"]?.stringValue.flatMap(Int.init),
              let text = o["rgba"]?.stringValue, let pixels = Data(base64Encoded: text) else {
            throw CoreError("modifyImage returned nothing usable")
        }
        return (w, h, pixels)
    }

    /// Fills in the scheme of a scheme-relative URL, such as
    /// "//images.example.com/1.jpg". Core owns the rule so both clients apply
    /// the same one.
    public func normalizeURL(_ raw: String, base: String = "") -> String {
        core.normalizeURL(raw, base: base)
    }
}

/// Configuration passed to `MobileNew`.
public struct CoreConfig: Codable, Sendable {
    public var appVersion: String
    public var locale: String
    public var platform: String
    public var defaultUserAgent: String
    public var memoryLimitBytes: Int64

    public init(appVersion: String, locale: String, platform: String = "ios", defaultUserAgent: String, memoryLimitBytes: Int64 = 0) {
        self.appVersion = appVersion; self.locale = locale; self.platform = platform
        self.defaultUserAgent = defaultUserAgent; self.memoryLimitBytes = memoryLimitBytes
    }
}

/// How to fetch one image, from a source's onImageLoad/onThumbnailLoad.
public struct ImageRequest: Sendable, Hashable {
    public var url: String
    public var method: String = "GET"
    public var headers: [String: String] = [:]
    public var body: String?
    /// Names the config's callbacks inside the source's runtime; empty when
    /// the source declared none, in which case the body is used as it is.
    public var handle: String = ""
    /// Which of onResponse/onLoadFailed the handle carries.
    public var callbacks: [String] = []
    /// The source's pixel-buffer script, when it supplied one. It is
    /// JavaScript text, run by Core because iOS has no engine of its own.
    public var modifyImage: String = ""

    public init(url: String) { self.url = url }

    public func has(_ callback: String) -> Bool { callbacks.contains(callback) }

    init(json: String, fallbackURL: String) throws {
        url = fallbackURL
        let v = try JSONValue.parse(json)
        guard case .object(let o) = v else { return }
        if let u = o["url"]?.stringValue, !u.isEmpty { url = u }
        if let m = o["method"]?.stringValue, !m.isEmpty { method = m.uppercased() }
        if case .object(let h)? = o["headers"] {
            for (k, v) in h.entries { if let s = v.stringValue { headers[k] = s } }
        }
        if let d = o["data"]?.stringValue { body = d }
        if let h = o["handle"]?.stringValue { handle = h }
        if case .array(let list)? = o["callbacks"] { callbacks = list.compactMap(\.stringValue) }
        if let script = o["modifyImage"]?.stringValue { modifyImage = script }
    }
}
