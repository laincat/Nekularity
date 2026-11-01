import Foundation
import Testing

@testable import NekularityKit

@Suite("VideoLibraryStore")
@MainActor
struct VideoLibraryStoreTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleFile(in dir: URL, name: String = "clip.mp4") throws -> URL {
        let url = dir.appending(path: name)
        try Data("not really a video, but bytes".utf8).write(to: url)
        return url
    }

    @Test("importing copies the file into the library and lists it")
    func importCopies() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try sampleFile(in: dir)
        let store = VideoLibraryStore(directory: dir.appending(path: "Library"))

        try store.importVideo(from: source)

        #expect(store.items.count == 1)
        let item = try #require(store.items.first)
        #expect(item.title == "clip")
        #expect(item.bytes > 0)
        // Copied, not linked: the plot is that deleting the original must not
        // empty the library.
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    @Test("a position is remembered, and only a partly watched item resumes")
    func resumeNeedsProgress() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try sampleFile(in: dir)
        let store = VideoLibraryStore(directory: dir.appending(path: "Library"))
        try store.importVideo(from: source)
        let item = try #require(store.items.first)

        #expect(store.resume == nil, "never played must not resume")

        store.update(item, position: 10, seconds: 600)
        #expect(store.resume == nil, "ten seconds in is not worth resuming")

        store.update(item, position: 120, seconds: 600)
        #expect(store.resume?.id == item.id)
        #expect(abs((store.items.first?.progress ?? 0) - 0.2) < 0.001)

        // Finished: no longer offered.
        store.update(item, position: 599, seconds: 600)
        #expect(store.resume == nil)
    }

    @Test("the list survives a relaunch, and a vanished file leaves it")
    func persistenceAndMissingFiles() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try sampleFile(in: dir)
        let library = dir.appending(path: "Library")
        let store = VideoLibraryStore(directory: library)
        try store.importVideo(from: source)
        let item = try #require(store.items.first)
        store.update(item, position: 60, seconds: 300)

        let again = VideoLibraryStore(directory: library)
        #expect(again.items.count == 1)
        #expect(again.items.first?.position == 60)

        try FileManager.default.removeItem(at: again.url(for: item))
        let after = VideoLibraryStore(directory: library)
        #expect(after.items.isEmpty, "a file deleted behind the app's back must not stay listed")
    }
}
