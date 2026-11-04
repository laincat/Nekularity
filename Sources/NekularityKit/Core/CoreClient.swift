import Foundation
import VeneraCatCore

/// Errors from Core calls.
public struct CoreError: Error, LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public init(_ error: NSError) { message = error.localizedDescription }
    public var errorDescription: String? { CoreError.readable(message) }

    /// The call was cancelled (task cancellation or Core.Cancel).
    ///
    /// Go, Foundation and Core each word this differently — "context canceled",
    /// "operation canceled", "cancelled" — and matching only Go's phrasing meant a
    /// cancellation could surface as an error the interface showed.
    public var isCancelled: Bool {
        let lower = message.lowercased()
        return lower.contains("canceled") || lower.contains("cancelled") || lower.contains("已取消")
    }

    /// The source declared no such image callback; the caller should carry on
    /// with what it already has rather than treat this as a failure.
    public var isCallbackAbsent: Bool { message.contains("no such callback") }

    /// The login handle belonged to a runtime that no longer answers, because the
    /// source was updated or removed while the login page was open. Waiting
    /// longer cannot succeed, so the login has to say so.
    public var isWebviewHandleGone: Bool {
        message.lowercased().contains("webview login handle is no longer valid")
    }

    /// Core speaks English and its text is what a developer needs; the
    /// interface is Chinese. Well-known failures get a Chinese sentence, and
    /// anything else keeps Core's own words after a Chinese prefix, so a
    /// report never shows a bare English sentence but still carries the
    /// original for a bug report.
    public static func readable(_ message: String) -> String {
        let lower = message.lowercased()
        func has(_ needle: String) -> Bool { lower.contains(needle) }
        if has("canceled") || has("cancelled") || has("已取消") {
            return "操作已取消"
        }
        if has("no such source") || has("source not found") || has("unknown source") {
            return "找不到这个漫画源,可能已被删除"
        }
        if has("webview login handle is no longer valid") {
            return "漫画源在登录过程中被更新或删除,这次登录已经失效"
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
        // Foundation's own network errors arrive as English sentences when a
        // fetch fails before Core answers. Falling through would blame the source
        // for the phone being offline, and leave the sentence in English.
        if has("offline") || has("not connected to the internet") || has("network connection was lost") {
            return "设备当前离线,请检查网络"
        }
        if has("timed out") || has("cannot connect to host") || has("could not connect")
            || has("hostname could not be found") || has("network is unreachable") {
            return "连不上服务器,请检查网络或稍后重试"
        }
        if message.isEmpty {
            return "操作失败,源没有给出原因"
        }
        // Already through here once: an error that travelled from one screen to
        // another, or a failure read back from disk, arrives with the prefix and
        // wrapping it again reads like a rendering bug.
        let prefix = "源返回错误:"
        if message.hasPrefix(prefix) { return message }
        return prefix + message
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

    /// Installs a new comic index entry after Core checks its executed identity.
    public func installComicEntry(_ entry: IndexEntry, body: String, indexURL: URL) async throws -> PluginRecord {
        let entryJSON = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        let out = try await run { core, id in
            try Self.call { core.installComicEntry(id, entryJSON: entryJSON, body: body, indexURL: indexURL.absoluteString, error: $0) }
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

    /// Searches whichever way the source declares.
    ///
    /// A source offers `search.load(keyword, options, page)` or
    /// `search.loadNext(keyword, options, next)`, and ehentai offers only the
    /// second. Deciding that here means a screen cannot forget it — the browse
    /// tab and the category random search each forgot it once, in different
    /// places.
    public func searchPage(key: String, keyword: String, page: Int, options: [String]) async throws -> ComicPage {
        if await hasComic(key: key, path: "search.load") {
            return try await search(key: key, keyword: keyword, page: page, options: options)
        }
        guard page <= 1 else {
            // The caller has to keep the cursor: only it knows which page it is
            // on, and the source only hands out the next one.
            throw CoreError("这个源用游标翻页,请用 searchNext 继续")
        }
        return try await searchNext(key: key, keyword: keyword, cursor: nil, options: options)
    }

    /// The source's category page; nil when it declares none.
    public func categoryPage(key: String) async throws -> CategoryPage? {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.category(key, error: $0) } }
        if out.isEmpty || out == "{}" { return nil }
        do {
            return try Self.decode(CategoryPage.self, out)
        } catch {
            // A page with a title but no parts behaves as none.
            if out.contains("\"parts\":[]") { return nil }
            throw error
        }
    }

    /// Loads one page of a category. `category` is the chosen value itself;
    /// `param` is what that value maps to.
    public func categoryComics(key: String, category: String, param: String,
                               options: [String], page: Int) async throws -> ComicPage {
        let optionsJSON = JSONValue.array(options.map(JSONValue.string)).jsonText
        let out = try await run { core, id in
            try Self.call {
                core.categoryComics(id, key: key, category: category, param: param,
                                    optionsJSON: optionsJSON, page: max(1, page), error: $0)
            }
        }
        return try Self.decode(ComicPage.self, out)
    }

    /// Builds a .venera archive from the installed sources and the given search
    /// history, and returns its bytes for the user to save.
    ///
    /// The client cannot assemble the archive itself — the scripts live in
    /// Core's registry — and cookies are never part of it: they are per-source
    /// credentials and an export is a file people mail to themselves.
    public func exportBackup(searchHistory: some Sequence<String>, sourceKeys: some Sequence<String> = []) async throws -> Data {
        let historyJSON = JSONValue.array(searchHistory.map(JSONValue.string)).jsonText
        // Core cannot enumerate the host's store, so each source's stored data is
        // collected from the keys the caller names: a restore that brings back
        // code without it leaves the source logged out and pointed at no domain.
        var perSource: [(String, JSONValue)] = []
        for key in sourceKeys {
            perSource.append((key, try JSONValue.parse(host.store.allValues(key: key))))
        }
        let dataJSON = JSONValue.object(OrderedObject(perSource)).jsonText
        // Core answers with base64: every method here crosses the bridge as a
        // string, and a []byte return would be a binding shape nothing on this
        // machine can confirm.
        let encoded = try await run(cancellable: false) { core, _ in
            try Self.call { core.exportBackup(historyJSON, sourceDataJSON: dataJSON, error: $0) }
        }
        guard let data = Data(base64Encoded: encoded, options: []) else {
            throw CoreError("备份内容不是有效的 base64")
        }
        return data
    }

    /// The hosts a source claims for its own links, e.g. ["nhentai.net"].
    public func linkDomains(key: String) async throws -> [String] {
        let json = try await run(cancellable: false) { core, _ in
            try Self.call { core.linkDomains(key, error: $0) }
        }
        return try Self.decode([String].self, json)
    }

    /// Asks every installed source that claims the address's host whether it is
    /// one of its own comics. An empty target means none did, and the caller
    /// should search for the text as a keyword instead.
    ///
    /// Pasting a link is what a reader does when an address arrives in a chat,
    /// and searching for the URL itself finds nothing.
    public func openLink(_ raw: String) async throws -> LinkTarget {
        let json = try await run { core, id in
            try Self.call { core.openLink(id, raw: raw, error: $0) }
        }
        return try Self.decode(LinkTarget.self, json)
    }

    /// What the source means by tapping one of its tags. A source without
    /// `onClickTag` answers an empty action rather than an error: having no
    /// opinion is not a failure.
    public func clickTag(key: String, namespace: String, tag: String) async throws -> TagAction {
        let json = try await run { core, id in
            try Self.call { core.clickTag(id, key: key, namespace: namespace, tag: tag, error: $0) }
        }
        return try Self.decode(TagAction.self, json)
    }

    /// Runs a setting the source declares as `type: "callback"`.
    ///
    /// The callback is a function inside the source, so it cannot be carried
    /// across: the client names the setting and reports what the source
    /// answered, which is what such a button exists for.
    public func callSettingCallback(key: String, setting: String) async throws -> String {
        let json = try await run { core, id in
            try Self.call { core.callSettingCallback(id, key: key, settingKey: setting, error: $0) }
        }
        return Self.plainText(json)
    }

    /// The login a source declares on its own page, or an empty one when it
    /// logs in another way.
    ///
    /// The two callbacks cannot cross the language boundary, so `handle` names
    /// them inside the source's runtime and is passed back to the two calls
    /// below. `{}` from Core means this source has no browser login, which is
    /// how a client tells the three styles apart.
    public func webviewLogin(key: String) async throws -> WebviewLogin {
        let json = try await run(cancellable: false) { core, _ in
            try Self.call { core.accountWebviewLogin(key, error: $0) }
        }
        return try Self.decode(WebviewLogin.self, json)
    }

    /// Asks the source whether the page the browser is showing means "logged
    /// in". Only the source knows: five of them test the title, and a client
    /// that guessed would store a half-finished login.
    public func webviewStatus(key: String, handle: String,
                              pageURL: String, title: String) async throws -> Bool {
        let json = try await run { core, id in
            try Self.call {
                core.webviewStatus(id, key: key, handle: handle,
                                   pageURL: pageURL, title: title, error: $0)
            }
        }
        struct Status: Decodable { var done: Bool }
        return try Self.decode(Status.self, json).done
    }

    /// Runs the source's onLoginSuccess once the browser's cookies are stored.
    /// A source without that callback finishes normally: the cookies are what
    /// matters, the callback only refreshes something else.
    public func webviewLoginDone(key: String, handle: String) async throws {
        try await run { core, id in
            _ = try core.webviewLoginDone(id, key: key, handle: handle)
            return ""
        }
    }

    /// Which comment functions the source declares.
    public func commentSupport(key: String) async throws -> CommentSupport {
        let json = try await run(cancellable: false) { core, _ in
            try Self.call { core.commentSupport(key, error: $0) }
        }
        return try Self.decode(CommentSupport.self, json)
    }

    /// One page of a comic's comment thread. `replyTo` reads the replies to one
    /// comment; empty reads the thread itself.
    public func comments(key: String, comicID: String, subID: String,
                         page: Int = 1, replyTo: String = "") async throws -> CommentPage {
        let json = try await run { core, id in
            try Self.call {
                core.comicComments(id, key: key, comicID: comicID, subID: subID,
                                   page: max(1, page), replyTo: replyTo, error: $0)
            }
        }
        let page = try Self.decode(CommentPage.self, json)
        // A source may return comments without ids; give each one a stable
        // identity so a list can draw it.
        var fixed = page
        fixed.comments = page.comments.enumerated().map { index, one in
            var copy = one
            copy.fallbackID = "\(index)-\(one.userName)-\(one.time)"
            return copy
        }
        return fixed
    }

    /// Posts a comment. Any answer from the source counts as success.
    ///
    /// Core returns a BOOL with an error, and Swift turns that into a throwing
    /// call: there is no error pointer to pass, and the failure is the throw.
    public func sendComment(key: String, comicID: String, subID: String,
                            content: String, replyTo: String = "") async throws {
        try await run { core, id in
            _ = try core.sendComicComment(id, key: key, comicID: comicID, subID: subID,
                                          content: content, replyTo: replyTo)
            return ""
        }
    }

    /// Votes on a comment. `isLike` false takes the vote back: it is the same
    /// call with the other flag, not a separate function.
    public func likeComment(key: String, comicID: String, subID: String,
                            commentID: String, isLike: Bool) async throws {
        try await run { core, id in
            _ = try core.likeComicComment(id, key: key, comicID: comicID, subID: subID,
                                          commentID: commentID, isLike: isLike)
            return ""
        }
    }

    /// What the sources have printed, oldest first, and the line buffer's size.
    ///
    /// Core keeps the last 400 lines tagged with their source; a client that
    /// shows them can answer "why did this source fail" without a console.
    public func logLines() async throws -> [SourceLogEntry] {
        let json = try await run(cancellable: false) { core, _ in
            try Self.call { core.logLines($0) }
        }
        return try CoreClient.decode([SourceLogEntry].self, json)
    }

    /// Empties the buffer. The lines that already went to the host's log stay
    /// there: this only forgets what the panel would show.
    public func clearLogLines() async {
        _ = try? await run(cancellable: false) { core, _ in core.clearLogLines() }
    }

    /// How a source keeps favorites. The pieces come from the paths it declares
    /// and from `favorites.multiFolder`, which is data.
    public func favoritesSupport(key: String) async -> FavoritesSupport {
        func has(_ path: String) async -> Bool {
            await hasComic(key: key, path: path)
        }
        let canLoad = await has("favorites.loadComics")
        let toggle = await has("favorites.addOrDelFavorite")
        let folders = await has("favorites.loadFolders")
        guard canLoad || toggle else {
            return FavoritesSupport(supported: false, multiFolder: false, folders: false, canLoad: false)
        }
        var multi = false
        if let value = try? await comicValue(key: key, path: "favorites.multiFolder"),
           case .bool(let flag) = value {
            multi = flag
        }
        return FavoritesSupport(supported: true, multiFolder: multi,
                                folders: folders && multi, canLoad: canLoad)
    }

    /// The folders a source keeps, and which of them hold a comic when one is
    /// named.
    public func favoriteFolders(key: String, comicID: String?) async throws -> (folders: [String: String], favorited: [String]) {
        let arg: JSONValue = comicID.map { .string($0) } ?? .null
        let out = try await callComic(key: key, path: "favorites.loadFolders", args: [arg])
        guard case .object(let o) = try JSONValue.parse(out) else { return ([:], []) }
        var folders: [String: String] = [:]
        if case .object(let items)? = o["folders"] {
            for (id, name) in items.entries {
                folders[id] = name.stringValue ?? id
            }
        }
        var favorited: [String] = []
        if case .array(let ids)? = o["favorited"] {
            favorited = ids.compactMap { $0.stringValue }
        }
        return (folders, favorited)
    }

    /// Loads one page of a folder. A single-folder source takes no folder id, so
    /// pass nil for it.
    public func favoriteComics(key: String, folder: String?, page: Int) async throws -> ComicPage {
        let folderArg: JSONValue = folder.map { .string($0) } ?? .null
        let out = try await callComic(key: key, path: "favorites.loadComics",
                                      args: [.number(String(max(1, page))), folderArg])
        return try Self.decode(ComicPage.self, out)
    }

    /// Adds a comic to the source's favorites, or removes it.
    ///
    /// A single-folder source takes no folder id, so pass nil for it. The fourth
    /// argument is the source's own handle on the entry: wnacg builds its delete
    /// URL from it, so a removal without one asks for "del-id-undefined" and
    /// quietly does nothing. Sources that do not use it ignore the null.
    public func setFavorite(key: String, comicID: String, folder: String?,
                            favoriteID: String? = nil, adding: Bool) async throws {
        let folderArg: JSONValue = folder.map { .string($0) } ?? .null
        let handle: JSONValue = (favoriteID?.isEmpty == false) ? .string(favoriteID!) : .null
        _ = try await callComic(key: key, path: "favorites.addOrDelFavorite",
                                args: [.string(comicID), folderArg, .bool(adding), handle])
    }

    /// Reads a declaration that is data rather than a function.
    ///
    /// `favorites.multiFolder` decides whether a folder id is expected at all,
    /// and `callComic` invokes functions, so it cannot reach a value.
    public func comicValue(key: String, path: String) async throws -> JSONValue {
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.comicValue(key, path: path, error: $0) }
        }
        return (try? JSONValue.parse(out)) ?? .null
    }

    /// The UI strings a source declares for this device's locale.    /// The UI strings a source declares for this device's locale.
    ///
    /// A source writes `title: "domain"` in its settings and supplies the
    /// readable text in a translation table; without this the settings screen
    /// shows the raw key.
    public func translations(key: String) async throws -> [String: String] {
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.translations(key, error: $0) }
        }
        if out.isEmpty || out == "{}" { return [:] }
        return (try? Self.decode([String: String].self, out)) ?? [:]
    }

    /// Which login styles a source declares.    /// Which login styles a source declares. A source that needs no account
    /// reports none.
    public func accountStyles(key: String) async -> AccountStyles {
        func has(_ path: String) async -> Bool {
            await hasComic(key: key, path: path)
        }
        let password = await has("account.login")
        let webview = await has("account.loginWithWebview")
        let cookies = await has("account.loginWithCookies.validate")
        let logout = await has("account.logout")
        return AccountStyles(password: password, webview: webview, cookies: cookies, logout: logout)
    }

    /// The cookie names a source wants for its cookie login; empty otherwise.
    public func accountCookieFields(key: String) async throws -> [String] {
        let out = try await run(cancellable: false) { core, _ in
            try Self.call { core.accountCookieFields(key, error: $0) }
        }
        if out.isEmpty { return [] }
        return (try? Self.decode([String].self, out)) ?? []
    }

    /// Runs the source's own login. What the source answers is passed on; what
    /// it throws is kept as its own text, because the reason usually names the
    /// field it did not like.
    @discardableResult
    public func loginAccount(key: String, account: String, password: String) async throws -> String {
        let out = try await callComic(key: key, path: "account.login",
                                      args: [.string(account), .string(password)])
        return Self.plainText(out)
    }

    /// Hands pasted cookies to the source's own validate, which sets them and
    /// answers whether they work. A false answer is not an error: the source
    /// looked and found them unusable.
    public func loginWithCookies(key: String, values: [String]) async throws -> Bool {
        let out = try await callComic(key: key, path: "account.loginWithCookies.validate",
                                      args: [.array(values.map(JSONValue.string))])
        return Self.plainText(out) == "true"
    }

    public func logoutAccount(key: String) async throws {
        _ = try await callComic(key: key, path: "account.logout")
    }

    /// A source answers "ok" or a short phrase; anything else is passed on as
    /// JSON text rather than dropped.
    ///
    /// `null` means the source answered nothing, which is what a callback written
    /// without a return value does. Passing the literal through would put the word
    /// `null` on screen as if the source had said it, so it becomes an empty
    /// answer — the same rule the desktop client applies.
    static func plainText(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "null" { return "" }
        if case .string(let text)? = try? JSONValue.parse(trimmed) { return text }
        return trimmed
    }

    /// Loads one page of a source's ranking page. The option comes from
    /// `CategoryPage.ranking`.
    public func rankingComics(key: String, option: String, page: Int) async throws -> ComicPage {
        let out = try await callComic(key: key, path: "categoryComics.ranking.load",
                                      args: [.string(option), .number(String(max(1, page)))])
        return try Self.decode(ComicPage.self, out)
    }

    /// The browses a source offers (its `explore` list); empty when it has
    /// none.
    public func explorePages(key: String) async throws -> [ExplorePage] {
        let out = try await run(cancellable: false) { core, _ in try Self.call { core.explorePages(key, error: $0) } }
        return try Self.decode([ExplorePage].self, out)
    }

    /// Loads one browse page.
    ///
    /// A source pages a browse by number (`load(page)`) or by cursor
    /// (`loadNext(next)`); Core handles both and this passes the cursor back on
    /// the next call. Asking a cursor browse for `load` was the reason a source
    /// like ehentai reported "source does not define this function" here while
    /// the desktop worked.
    public func explore(key: String, index: Int, page: Int = 1, cursor: String = "") async throws -> ExploreResult {
        let out = try await run { core, id in
            try Self.call {
                core.comicExplore(id, key: key, index: index, page: max(1, page),
                                  cursor: cursor, error: $0)
            }
        }
        let wire = try Self.decode(ExplorePageWire.self, out)
        var sections: [ExploreSection] = []
        for section in wire.sections {
            let comics = section.comics.compactMap { try? Comic(json: $0) }
            if !comics.isEmpty {
                sections.append(ExploreSection(title: section.title, comics: comics))
            }
        }
        return ExploreResult(sections: sections, maxPage: wire.maxPage, next: wire.next)
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
            for (k, v) in h.entries {
                if let s = v.stringValue {
                    headers[k] = s
                } else if case .array(let list) = v, let first = list.first?.stringValue {
                    // Core hands a source's headers through as it found them, and
                    // `{"Referer": ["…"]}` is a legal way to write one. Reading
                    // only strings dropped those silently, which for a source that
                    // checks Referer means images that never load.
                    headers[k] = first
                }
            }
        }
        if let d = o["data"]?.stringValue { body = d }
        if let h = o["handle"]?.stringValue { handle = h }
        if case .array(let list)? = o["callbacks"] { callbacks = list.compactMap(\.stringValue) }
        if let script = o["modifyImage"]?.stringValue { modifyImage = script }
    }
}

// MARK: - Video providers

/// Video providers answer with results, details and a play address. Core holds
/// the plugins and rules; the client holds the player, so nothing here decodes
/// video — these calls only ever return JSON a screen can draw.
extension CoreClient {
    public func videoSearch(key: String, keyword: String, cursor: String = "") async throws -> VideoPage {
        let json = try await run { core, id in
            try Self.call {
                core.videoSearch(id, key: key, keyword: keyword, cursor: cursor, error: $0)
            }
        }
        return try Self.decode(VideoPage.self, json)
    }

    public func videoDetails(key: String, id videoID: String) async throws -> VideoDetails {
        let json = try await run { core, callID in
            try Self.call {
                core.videoDetails(callID, key: key, id_: videoID, error: $0)
            }
        }
        return try Self.decode(VideoDetails.self, json)
    }

    /// Asks the provider where one episode plays.
    ///
    /// The answer is an address plus the headers that must ride with it. A
    /// provider that instead needs a page sniffed says so, and that is the
    /// caller's problem to solve, not this method's.
    public func videoPlay(key: String, itemID: String, lineID: String,
                          episodeID: String) async throws -> VideoPlay {
        let json = try await run { core, callID in
            try Self.call {
                core.videoPlay(callID, key: key, itemID: itemID, lineID: lineID,
                               episodeID: episodeID, error: $0)
            }
        }
        return try Self.decode(VideoPlay.self, json)
    }
}
