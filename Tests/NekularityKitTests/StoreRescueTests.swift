import Foundation
import Testing

@testable import NekularityKit

@Suite("A store that cannot read its file")
@MainActor
struct StoreRescueTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "rescue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("the unreadable file is copied aside before anything saves over it")
    func keepsACopy() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shelf = dir.appending(path: "shelf.json")
        try Data("this is not the shelf you are looking for".utf8).write(to: shelf)

        let store = ShelfStore(directory: dir)
        #expect(store.lastError != nil)
        let copies = StoreRescue.copies(of: shelf)
        #expect(copies.count == 1)
        // The original stays where it was: a later version may read it, and a
        // hand repair is easier when the file is where it belongs.
        #expect(FileManager.default.fileExists(atPath: shelf.path))

        // The save that used to destroy the data now only destroys its own view of
        // it; the copy still holds the old bytes.
        store.record(ShelfHistory(comic: ShelfComic(source: "s", id: "1", title: "一")))
        let kept = try String(contentsOf: copies[0], encoding: .utf8)
        #expect(kept.contains("not the shelf"))
    }

    @Test("a comic list that will not decode does not become an empty list")
    func localComics() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "local-comics.json")
        try Data("{ broken".utf8).write(to: file)
        let store = LocalComicStore(directory: dir)
        #expect(store.comics.isEmpty)
        #expect(store.failure != nil)
        #expect(StoreRescue.copies(of: file).count == 1)
    }

    @Test("a download manifest that will not decode is kept, since its files still exist")
    func downloads() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = dir.appending(path: "manifest.json")
        try Data("[] garbage".utf8).write(to: manifest)
        let store = DownloadStore(root: dir)
        #expect(store.failure != nil)
        #expect(StoreRescue.copies(of: manifest).count == 1)
    }

    @Test("a missing file is not a failure and makes no copies")
    func absenceIsNotCorruption() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ShelfStore(directory: dir)
        #expect(store.lastError == nil)
        #expect(StoreRescue.copies(of: dir.appending(path: "shelf.json")).isEmpty)
    }
}
