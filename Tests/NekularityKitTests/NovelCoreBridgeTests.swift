import CryptoKit
import Foundation
import Testing
@testable import NekularityKit

/// Exercises the real gomobile `CoreClient` + `SourceLibrary` bridge for
/// `novel-js` plugins: the four novel entry points, persistence and restart
/// restore, error boundaries (uninstalled, disabled, cross-type), and
/// `veneracat-source/1-draft` collection capability matching and installation.
@MainActor
@Suite("Novel Core bridge", .serialized)
struct NovelCoreBridgeTests {
    private static let rawChapterHTML = #"<div class="content" data-chapter="ch1"><p>Line 1 &amp; <em>Line 2</em></p><script>evil()</script><p>Line 3</p></div>"#

    private static func novelScript(key: String = "mobile_novel", version: String = "1.0.0") -> String {
        """
        class MobileNovel extends NovelSource {
            name = "Mobile Novel"; key = "\(key)"; version = "\(version)"
            url = "https://novel.test"

            async popular(page) {
                return {
                    items: [{id: "n1", title: "Popular Page " + page, cover: "https://novel.test/c1.jpg", author: "Alice"}],
                    maxPage: 3
                }
            }

            async search(keyword, page) {
                return {
                    items: [{id: "s1", title: keyword + "#" + page, author: "Bob"}],
                    maxPage: 2
                }
            }

            async detail(id) {
                return {
                    id: id,
                    title: "Starlit Tower",
                    cover: "https://novel.test/cover.jpg",
                    author: "Alice",
                    summary: "A short probe summary.",
                    status: "ongoing",
                    tags: ["fantasy", "mystery"],
                    chapters: [
                        {id: "ch1", title: "Chapter 1", time: "2026-11-24"},
                        {id: "ch2", title: "Chapter 2"}
                    ]
                }
            }

            async chapter(novelId, chapterId) {
                return {html: \(jsonLiteral(rawChapterHTML))}
            }
        }
        """
    }

    private static let comicScript = """
    class ProbeComic extends ComicSource {
        name = "Probe Comic"; key = "probe_comic"; version = "1.0.0"
        search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) }
    }
    """

    private static let videoScript = """
    class ProbeVideo extends VideoSource {
        name = "Probe Video"; key = "probe_video"; version = "1.0.0"
        async search(keyword, cursor) { return { items: [] } }
        async loadInfo(id) { return new VideoDetails({ title: "Clip", lines: [] }) }
        async loadPlay(itemId, lineId, epId) { return new PlayInfo({ url: "https://video.test/a.m3u8" }) }
    }
    """

    private static func jsonLiteral(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "nk-novel-\(UUID().uuidString)")
    }

    private func makeLibrary(
        root: URL,
        fetch: @escaping @Sendable (URL) async throws -> Data = { _ in Data() }
    ) throws -> SourceLibrary {
        let jars = CookieJars(file: nil)
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-novel-test/1")
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(
            config: CoreConfig(appVersion: SourceAPI.level, locale: "zh_CN", defaultUserAgent: "nk-novel-test/1"),
            host: host
        )
        return SourceLibrary(core: core, fetch: fetch)
    }

    private func assertFourEntryPoints(_ core: CoreClient, key: String) async throws {
        let popular = try await core.novelPopular(key: key, page: 2)
        #expect(popular.maxPage == 3)
        #expect(popular.items.count == 1)
        #expect(popular.items[0].id == "n1")
        #expect(popular.items[0].title == "Popular Page 2")
        #expect(popular.items[0].author == "Alice")

        let found = try await core.novelSearch(key: key, keyword: "star light", page: 2)
        #expect(found.maxPage == 2)
        #expect(found.items.count == 1)
        #expect(found.items[0].id == "s1")
        #expect(found.items[0].title == "star light#2")

        let detail = try await core.novelDetail(key: key, id: "n1")
        #expect(detail.id == "n1")
        #expect(detail.title == "Starlit Tower")
        #expect(detail.author == "Alice")
        #expect(detail.status == "ongoing")
        #expect(detail.tags == ["fantasy", "mystery"])
        #expect(detail.chapters.count == 2)
        #expect(detail.chapters[0] == NovelChapter(id: "ch1", title: "Chapter 1", time: "2026-11-24"))

        let chapter = try await core.novelChapter(key: key, novelID: "n1", chapterID: "ch1")
        #expect(chapter.html == Self.rawChapterHTML)
        let doc = chapter.extractedDocument()
        #expect(doc.paragraphs == ["Line 1 & Line 2", "Line 3"])
    }

    @Test func novelInstallFourEntryPointsToggleAndRestoreAcrossRestart() async throws {
        let root = tempDir()
        let lib = try makeLibrary(root: root)

        let record = try await lib.installNovel(script: Self.novelScript(), origin: "test")
        #expect(record.type == PluginRecord.novelJSType)
        #expect(record.key == "mobile_novel")
        #expect(record.isNovel)
        #expect(lib.novelSources.map(\.key) == ["mobile_novel"])
        #expect(lib.comicSources.isEmpty)

        try await assertFourEntryPoints(lib.core, key: "mobile_novel")

        // Restart with enabled novel source -> restores cleanly and answers all 4 calls.
        let reopened = try makeLibrary(root: root)
        await reopened.restore()
        #expect(reopened.restoreFailures.isEmpty)
        #expect(reopened.novelSources.map(\.key) == ["mobile_novel"])
        #expect(reopened.novelSources.first?.enabled == true)
        try await assertFourEntryPoints(reopened.core, key: "mobile_novel")

        // Disable, persist, and restart -> must stay disabled and refuse calls.
        try await reopened.setEnabled("mobile_novel", false)
        #expect(reopened.novelSources.first?.enabled == false)

        let afterDisable = try makeLibrary(root: root)
        await afterDisable.restore()
        #expect(afterDisable.restoreFailures.isEmpty)
        #expect(afterDisable.novelSources.first?.enabled == false)

        do {
            _ = try await afterDisable.core.novelPopular(key: "mobile_novel", page: 1)
            Issue.record("expected disabled novel source to fail")
        } catch let error as CoreError {
            #expect(error.isDisabled)
        }

        // Re-enable -> answers again.
        try await afterDisable.setEnabled("mobile_novel", true)
        try await assertFourEntryPoints(afterDisable.core, key: "mobile_novel")
    }

    @Test func novelErrorBoundariesUninstalledDisabledAndCrossType() async throws {
        let lib = try makeLibrary(root: tempDir())
        let core = lib.core

        // 1. Uninstalled source -> ErrNotFound on all four entry points.
        for call in novelEntryPointCalls(core: core, key: "missing_novel") {
            do {
                try await call()
                Issue.record("expected not installed error")
            } catch let error as CoreError {
                #expect(error.isNotInstalled, "unexpected error: \(error.message)")
            }
        }

        // Install novel, comic and video sources.
        _ = try await lib.installNovel(script: Self.novelScript(), origin: "fixture")
        _ = try await lib.install(script: Self.comicScript, origin: "fixture")
        _ = try await lib.install(type: PluginRecord.videoJSType, script: Self.videoScript, origin: "fixture")

        // 2. Disabled novel source -> ErrDisabled on all four entry points.
        try await lib.setEnabled("mobile_novel", false)
        for call in novelEntryPointCalls(core: core, key: "mobile_novel") {
            do {
                try await call()
                Issue.record("expected disabled error")
            } catch let error as CoreError {
                #expect(error.isDisabled, "unexpected error: \(error.message)")
            }
        }
        try await lib.setEnabled("mobile_novel", true)

        // 3. Cross-type: novel entry points on comic and video sources -> ErrWrongUse.
        for wrongKey in ["probe_comic", "probe_video"] {
            for call in novelEntryPointCalls(core: core, key: wrongKey) {
                do {
                    try await call()
                    Issue.record("expected wrong plugin type error for \(wrongKey)")
                } catch let error as CoreError {
                    #expect(error.isWrongPluginType, "unexpected error for \(wrongKey): \(error.message)")
                }
            }
        }

        // 4. Cross-type reverse: comic & video calls on novel source -> ErrWrongUse.
        do {
            _ = try await core.videoSearch(key: "mobile_novel", keyword: "q")
            Issue.record("expected videoSearch on novel source to fail")
        } catch let error as CoreError {
            #expect(error.isWrongPluginType, "unexpected error: \(error.message)")
        }

        do {
            _ = try await core.search(key: "mobile_novel", keyword: "q", page: 1, options: [])
            Issue.record("expected comic search on novel source to fail")
        } catch let error as CoreError {
            #expect(error.isWrongPluginType, "unexpected error: \(error.message)")
        }
    }

    @Test func collectionParsesMatchesNovelJSCapabilityAndInstallsVerifiedArtifact() async throws {
        let body = Self.novelScript(key: "collection_novel", version: "1.2.0")
        let bodyData = Data(body.utf8)
        let digest = Self.sha256Hex(bodyData)

        let collectionJSON = """
        {
          "$schema": "veneracat-source/1-draft",
          "id": "publisher.novel",
          "name": "Novel Publisher",
          "version": "1",
          "entries": [
            {
              "id": "novel-entry",
              "kind": "novel-source",
              "name": "Collection Novel",
              "version": "1.2.0",
              "status": "experimental",
              "key": "collection_novel",
              "supports": {
                "platforms": ["ios", "windows"],
                "requiresCapabilities": ["novel-source.js"]
              },
              "artifact": {
                "url": "packages/novel.js",
                "sha256": "\(digest)",
                "bytes": \(bodyData.count)
              }
            },
            {
              "id": "planned-entry",
              "kind": "service",
              "name": "Future Service",
              "version": "0.1.0",
              "status": "planned",
              "supports": {
                "platforms": ["ios"],
                "requiresCapabilities": ["service.v1"]
              }
            }
          ]
        }
        """

        let sourceURL = URL(string: "https://collection.test/dir/source.json")!
        let lib = try makeLibrary(root: tempDir()) { url in
            if url.absoluteString == "https://collection.test/dir/packages/novel.js" {
                return bodyData
            }
            throw CoreError("unexpected URL \(url.absoluteString)")
        }

        // With default iOS capabilities (including novel-source.js): novel entry is compatible.
        let check = try await lib.parseCollection(collectionJSON, sourceURL: sourceURL)
        #expect(check.isCompatible("novel-entry"))
        #expect(!check.isCompatible("planned-entry"))
        #expect(check.compatibility(for: "planned-entry")?.missing == ["service.v1"])

        let entry = try #require(check.collection.entries.first { $0.id == "novel-entry" })
        #expect(entry.artifact?.url == "https://collection.test/dir/packages/novel.js")
        #expect(entry.pluginType == PluginRecord.novelJSType)

        // Without novel-source.js capability: Core reports it as missing.
        let restricted = try await lib.parseCollection(
            collectionJSON,
            sourceURL: sourceURL,
            capabilities: [SourceCollection.capabilityComicJS]
        )
        #expect(!restricted.isCompatible("novel-entry"))
        #expect(restricted.compatibility(for: "novel-entry")?.missing == ["novel-source.js"])

        // Installing the verified novel entry succeeds and answers novel calls.
        let installed = try await lib.install(collectionEntry: entry, from: sourceURL)
        #expect(installed.key == "collection_novel")
        #expect(installed.type == PluginRecord.novelJSType)
        #expect(installed.version == "1.2.0")
        #expect(lib.novelSources.map(\.key) == ["collection_novel"])
        let popular = try await lib.core.novelPopular(key: "collection_novel", page: 1)
        #expect(popular.items.first?.title == "Popular Page 1")
    }

    @Test func collectionRejectsTamperedArtifactAndMismatchedKey() async throws {
        let body = Self.novelScript(key: "actual_novel", version: "1.0.0")
        let bodyData = Data(body.utf8)
        let digest = Self.sha256Hex(bodyData)
        let sourceURL = URL(string: "https://collection.test/source.json")!

        // 1. Tampered artifact bytes fail Core's SHA-256 verification.
        let tamperedEntry = SourceCollection.Entry(
            id: "tampered",
            kind: "novel-source",
            name: "Tampered",
            version: "1.0.0",
            status: "experimental",
            key: "actual_novel",
            supports: .init(platforms: ["ios"], requiresCapabilities: [SourceCollection.capabilityNovelJS]),
            artifact: .init(url: "https://collection.test/novel.js", sha256: digest, bytes: Int64(bodyData.count))
        )
        let tamperedLib = try makeLibrary(root: tempDir()) { _ in
            Data(body.replacingOccurrences(of: "1.0.0", with: "9.9.9").utf8)
        }
        await #expect(throws: (any Error).self) {
            _ = try await tamperedLib.install(collectionEntry: tamperedEntry, from: sourceURL)
        }
        #expect(tamperedLib.sources.isEmpty)

        // 2. Valid digest but declared key differs from expected entry key -> rolled back.
        let wrongKeyEntry = SourceCollection.Entry(
            id: "wrong-key",
            kind: "novel-source",
            name: "Wrong Key",
            version: "1.0.0",
            status: "experimental",
            key: "expected_novel",
            supports: .init(platforms: ["ios"], requiresCapabilities: [SourceCollection.capabilityNovelJS]),
            artifact: .init(url: "https://collection.test/novel.js", sha256: digest, bytes: Int64(bodyData.count))
        )
        let keyLib = try makeLibrary(root: tempDir()) { _ in bodyData }
        await #expect(throws: (any Error).self) {
            _ = try await keyLib.install(collectionEntry: wrongKeyEntry, from: sourceURL)
        }
        #expect(keyLib.sources.isEmpty)
    }

    @Test func updateAllPreservesNovelJSType() async throws {
        let v1 = Data(Self.novelScript(key: "url_novel", version: "1.0.0").utf8)
        let v2 = Data(Self.novelScript(key: "url_novel", version: "2.0.0").utf8)
        let replies = NovelScriptQueue([v1, v2])
        let lib = try makeLibrary(root: tempDir()) { _ in try replies.next() }
        let url = URL(string: "https://novel.test/url_novel.js")!

        let first = try await lib.installNovel(from: url)
        #expect(first.type == PluginRecord.novelJSType)
        #expect(first.version == "1.0.0")

        let updates = await lib.updateAll()
        #expect(updates.count == 1)
        #expect(updates.first?.error == nil)
        #expect(updates.first?.from == "1.0.0")
        #expect(updates.first?.to == "2.0.0")
        #expect(lib.novelSources.first?.type == PluginRecord.novelJSType)
        #expect(lib.novelSources.first?.version == "2.0.0")
    }

    private func novelEntryPointCalls(core: CoreClient, key: String) -> [@Sendable () async throws -> Void] {
        [
            { _ = try await core.novelPopular(key: key, page: 1) },
            { _ = try await core.novelSearch(key: key, keyword: "star", page: 1) },
            { _ = try await core.novelDetail(key: key, id: "n1") },
            { _ = try await core.novelChapter(key: key, novelID: "n1", chapterID: "ch1") },
        ]
    }
}

private final class NovelScriptQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data]

    init(_ items: [Data]) { self.items = items }

    func next() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !items.isEmpty else { throw CoreError("queue empty") }
        return items.removeFirst()
    }
}
