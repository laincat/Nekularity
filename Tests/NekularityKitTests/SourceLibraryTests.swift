import Foundation
import Testing
@testable import NekularityKit

/// Installing a source and then listing it is the first thing the app does, and it
/// crosses three layers: the library, Core's runtime and the store. The fake
/// network is only used for downloads, so this runs without a server.
// The library is @MainActor: its initialiser and its properties are isolated.
@MainActor
@Suite("SourceLibrary")
struct SourceLibraryTests {
    private let script = """
    class Mini extends ComicSource {
        name = "Mini"; key = "mini"; version = "1.0.0"
        search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) }
    }
    """

    private func library(_ root: URL, fetch: @escaping @Sendable (URL) async throws -> Data = { _ in Data() }) throws -> SourceLibrary {
        let jars = CookieJars(file: nil)
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1")
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "nk-test/1"), host: host)
        return SourceLibrary(core: core, fetch: fetch)
    }

    @Test func installingAScriptListsItAsAComicSource() async throws {
        let lib = try library(URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
        let record = try await lib.install(script: script, origin: "test")
        #expect(record.key == "mini")

        await lib.refresh()
        #expect(lib.sources.map(\.key) == ["mini"])
        #expect(lib.comicSources.map(\.key) == ["mini"])
    }

    /// Removing a source leaves the list empty rather than a record Core no longer
    /// knows: the app renders this list directly.
    @Test func removingASourceEmptiesTheList() async throws {
        let lib = try library(URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
        _ = try await lib.install(script: script, origin: "test")
        try await lib.remove("mini")
        await lib.refresh()
        #expect(lib.sources.isEmpty)
    }

    /// Downloading a script installs it with the URL as its origin, which is what a
    /// subscription index records.
    @Test func installingFromAURLUsesTheFetchedBody() async throws {
        let body = script
        let lib = try library(URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)) { url in
            #expect(url.absoluteString == "https://index.test/mini.js")
            return Data(body.utf8)
        }
        let record = try await lib.install(from: URL(string: "https://index.test/mini.js")!)
        #expect(record.key == "mini")
        #expect(record.origin == "https://index.test/mini.js")
    }

    /// A script that is not a comic source is refused, and nothing is left behind.
    @Test func aBrokenScriptIsRefusedAndNothingIsStored() async throws {
        let lib = try library(URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
        await #expect(throws: (any Error).self) {
            _ = try await lib.install(script: "class Nope {", origin: "test")
        }
        await lib.refresh()
        #expect(lib.sources.isEmpty)
    }
}

@Suite("Batch source update")
struct SourceUpdateSummaryTests {
    private typealias Update = SourceLibrary.SourceUpdate

    @Test("an updated source says which version moved to which")
    func reportsVersions() {
        let text = Update.summary([Update(key: "a", name: "甲", from: "1.0", to: "1.1")])
        #expect(text.contains("已更新 1 个"))
        #expect(text.contains("甲 1.0 → 1.1"))
    }

    @Test("unchanged is not failure, and the two are counted apart")
    func separatesUnchangedFromFailed() {
        let text = Update.summary([
            Update(key: "a", name: "甲", from: "1.0", to: "1.0"),
            Update(key: "b", name: "乙", from: "1.0", to: "1.0", error: "网络不通"),
        ])
        #expect(text.contains("1 个已是最新"))
        #expect(text.contains("失败 1 个:乙:网络不通"))
        #expect(!text.contains("已更新"))
    }

    @Test("nothing to update is said plainly rather than shown as an empty alert")
    func emptyIsSaid() {
        #expect(Update.summary([]) == "没有可从网址更新的源。")
    }
}
