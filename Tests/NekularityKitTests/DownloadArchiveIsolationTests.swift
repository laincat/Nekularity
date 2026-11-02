import Foundation
import Testing
@testable import NekularityKit

@MainActor
@Suite("Offline pages retain their comic identity")
struct DownloadArchiveIsolationTests {
    private let page = "https://fixture.invalid/shared-page.jpg"

    private func archive() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "download-isolation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var chapters: [DownloadStore.Chapter] = []
        for comic in ["comic-a", "comic-b"] {
            var chapter = DownloadStore.Chapter(sourceKey: "probe", comicID: comic,
                comicTitle: comic, chapterID: "chapter-1", chapterTitle: "Chapter 1",
                pages: [page], files: [])
            let relative = "\(chapter.folder)/0.img"
            let folder = root.appending(path: chapter.folder, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(comic.utf8).write(to: root.appending(path: relative))
            chapter.files = [relative]
            chapters.append(chapter)
        }
        try JSONEncoder().encode(chapters).write(to: root.appending(path: "manifest.json"))
        return root
    }

    private func key(_ comic: String, source: String = "probe", chapter: String = "chapter-1") -> ImageLoader.Key {
        .init(source: source, url: page, comicID: comic, chapterID: chapter, isThumbnail: false)
    }

    @Test func sharedAddressDoesNotCrossComicOrSourceBoundaries() throws {
        let root = try archive()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(root: root)
        #expect(store.bytes(for: key("comic-a")) == Data("comic-a".utf8))
        #expect(store.bytes(for: key("comic-b")) == Data("comic-b".utf8))
        #expect(store.bytes(for: key("missing")) == nil)
        #expect(store.bytes(for: key("comic-a", source: "another-source")) == nil)
        #expect(store.bytes(for: key("comic-a", chapter: "another-chapter")) == nil)
        #expect(store.bytes(for: .init(source: "probe", url: page, chapterID: "chapter-1", isThumbnail: false)) == nil)
        #expect(store.bytes(for: .init(source: "probe", url: page, comicID: "comic-a", chapterID: "chapter-1", isThumbnail: true)) == nil)
    }

    @Test func deletingOneComicDoesNotRemoveTheOtherIndexEntry() throws {
        let root = try archive()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(root: root)
        store.remove(sourceKey: "probe", comicID: "comic-a", chapterID: "chapter-1")
        #expect(store.bytes(for: key("comic-a")) == nil)
        #expect(store.bytes(for: key("comic-b")) == Data("comic-b".utf8))
        #expect(!store.isDownloaded(sourceKey: "probe", comicID: "comic-a", chapterID: "chapter-1"))
        #expect(store.isDownloaded(sourceKey: "probe", comicID: "comic-b", chapterID: "chapter-1"))

        let reopened = DownloadStore(root: root)
        #expect(reopened.bytes(for: key("comic-a")) == nil)
        #expect(reopened.bytes(for: key("comic-b")) == Data("comic-b".utf8))
        #expect(reopened.chapters.count == 1)
    }
}
