import Foundation
import Testing
@testable import NekularityKit

@Suite("Novel models and collection capabilities")
struct NovelModelsTests {
    @Test func novelPageDecodesFullAndLenientShapes() throws {
        let json = """
        {
          "items": [
            {"id": "n1", "title": "Starlit Tower", "cover": "https://novel.test/c1.jpg", "author": "Alice"},
            {"id": 42, "title": "Numeric ID"}
          ],
          "maxPage": 5
        }
        """
        let page = try OrderedJSONDecoder.decode(NovelPage.self, from: json)
        #expect(page.maxPage == 5)
        #expect(page.items.count == 2)
        #expect(page.items[0] == NovelItem(id: "n1", title: "Starlit Tower", cover: "https://novel.test/c1.jpg", author: "Alice"))
        #expect(page.items[1].id == "42")
        #expect(page.items[1].cover == nil)
        #expect(page.items[1].author == nil)
    }

    @Test func novelPageHandlesNullItemsAndMissingMaxPage() throws {
        let page = try OrderedJSONDecoder.decode(NovelPage.self, from: #"{"items":null}"#)
        #expect(page.items.isEmpty)
        #expect(page.maxPage == 0)
    }

    @Test func novelDetailDecodesMetadataTagsAndChapters() throws {
        let json = """
        {
          "id": "n1",
          "title": "Starlit Tower",
          "cover": "https://novel.test/cover.jpg",
          "author": "Alice",
          "summary": "A short probe summary.",
          "status": "ongoing",
          "tags": ["fantasy", "mystery"],
          "chapters": [
            {"id": "ch1", "title": "Chapter 1", "time": "2026-11-24"},
            {"id": 2, "title": "Chapter 2"}
          ]
        }
        """
        let detail = try OrderedJSONDecoder.decode(NovelDetail.self, from: json)
        #expect(detail.id == "n1")
        #expect(detail.title == "Starlit Tower")
        #expect(detail.author == "Alice")
        #expect(detail.status == "ongoing")
        #expect(detail.tags == ["fantasy", "mystery"])
        #expect(detail.chapters.count == 2)
        #expect(detail.chapters[0] == NovelChapter(id: "ch1", title: "Chapter 1", time: "2026-11-24"))
        #expect(detail.chapters[1] == NovelChapter(id: "2", title: "Chapter 2", time: nil))
    }

    @Test func novelDetailHandlesMinimalPayload() throws {
        let detail = try OrderedJSONDecoder.decode(NovelDetail.self, from: #"{"id":"n2","title":"Minimal"}"#)
        #expect(detail.id == "n2")
        #expect(detail.tags.isEmpty)
        #expect(detail.chapters.isEmpty)
    }

    @Test func novelChapterContentPreservesRawHTMLVerbatim() throws {
        let raw = #"<div class="content" data-chapter="ch1"><p>Line 1 &amp; <em>Line 2</em></p><img src="https://novel.test/p1.png" /></div>"#
        let payload = String(decoding: try JSONEncoder().encode(["html": raw]), as: UTF8.self)
        let content = try OrderedJSONDecoder.decode(NovelChapterContent.self, from: payload)
        #expect(content.html == raw)
    }

    @Test func pluginRecordIdentifiesNovelJS() throws {
        let json = #"{"type":"novel-js","key":"demo_novel","name":"Demo","version":"1.0.0","enabled":true}"#
        let record = try OrderedJSONDecoder.decode(PluginRecord.self, from: json)
        #expect(record.isNovel)
        #expect(!record.isComic)
        #expect(!record.isVideo)
    }

    @Test func coreErrorMapsPluginAndNovelErrorBoundaries() {
        let notInstalled = CoreError("plugin: not installed")
        #expect(notInstalled.isNotInstalled)
        #expect(CoreError.readable(notInstalled.message) == "漫画源还未安装")

        let disabled = CoreError("plugin: disabled")
        #expect(disabled.isDisabled)
        #expect(CoreError.readable(disabled.message) == "该源已停用,请先在源管理中启用")

        let wrongUse = CoreError("plugin: not this kind of plugin")
        #expect(wrongUse.isWrongPluginType)
        #expect(CoreError.readable(wrongUse.message) == "该源类型不匹配,无法执行此操作")

        let novelMissing = CoreError("novel: not found")
        #expect(novelMissing.isNovelNotFound)
        #expect(CoreError.readable(novelMissing.message) == "源里找不到这部小说或章节")
    }

    @Test func sourceCollectionDeclaresAndMatchesNovelJSCapability() {
        #expect(SourceCollection.capabilityNovelJS == "novel-source.js")
        #expect(SourceCollection.defaultCapabilities.contains("novel-source.js"))

        let artifact = SourceCollection.Artifact(
            url: "https://example.test/novel.js",
            sha256: String(repeating: "a", count: 64),
            bytes: 128
        )
        let novelEntry = SourceCollection.Entry(
            id: "novel-demo",
            kind: "novel-source",
            name: "Demo Novel",
            version: "1.0.0",
            status: "experimental",
            key: "demo_novel",
            supports: .init(platforms: ["ios", "windows"], requiresCapabilities: [SourceCollection.capabilityNovelJS]),
            artifact: artifact
        )
        #expect(novelEntry.pluginType == PluginRecord.novelJSType)
        #expect(novelEntry.isInstallable)

        let iosMatch = novelEntry.compatibility(platform: "ios", capabilities: SourceCollection.defaultCapabilities)
        #expect(iosMatch.compatible)
        #expect(iosMatch.missing.isEmpty)

        let withoutNovel = novelEntry.compatibility(platform: "ios", capabilities: [SourceCollection.capabilityComicJS])
        #expect(!withoutNovel.compatible)
        #expect(withoutNovel.missing == ["novel-source.js"])

        let wrongPlatform = novelEntry.compatibility(platform: "macos", capabilities: SourceCollection.defaultCapabilities)
        #expect(!wrongPlatform.compatible)
        #expect(wrongPlatform.missing == ["platform:macos"])

        let planned = SourceCollection.Entry(
            id: "planned-novel",
            kind: "novel-source",
            name: "Planned",
            version: "0.1.0",
            status: "planned",
            supports: .init(platforms: ["ios"], requiresCapabilities: [SourceCollection.capabilityNovelJS]),
            artifact: nil
        )
        #expect(!planned.isInstallable)
    }
}
