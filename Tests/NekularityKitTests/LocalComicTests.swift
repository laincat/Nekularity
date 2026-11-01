import Compression
import Foundation
import Testing

@testable import NekularityKit

/// Builds a zip in memory, so the reader is tested against the format rather than
/// against one produced by a tool this machine happens to have.
private enum ZipBuilder {
    static func make(_ files: [(name: String, data: Data, deflate: Bool)],
                     crcOverride: [String: UInt32] = [:]) -> Data {
        var out = Data()
        var directory = Data()
        for file in files {
            let payload: Data
            let method: UInt16
            if file.deflate, let squeezed = deflate(file.data), squeezed.count < file.data.count {
                payload = squeezed
                method = 8
            } else {
                payload = file.data
                method = 0
            }
            let offset = out.count
            let crc = crcOverride[file.name] ?? ZipReader.crc32(file.data)
            out.append(localHeader(name: file.name, method: method,
                                   compressed: payload.count, uncompressed: file.data.count, crc: crc))
            out.append(Data(file.name.utf8))
            out.append(payload)

            directory.append(centralHeader(name: file.name, method: method,
                                           compressed: payload.count, uncompressed: file.data.count,
                                           offset: offset, crc: crc))
            directory.append(Data(file.name.utf8))
        }
        let directoryOffset = out.count
        out.append(directory)
        out.append(endRecord(count: files.count, directorySize: directory.count, offset: directoryOffset))
        return out
    }

    private static func deflate(_ data: Data) -> Data? {
        let capacity = max(data.count * 2, 64)
        var output = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let d = destination.bindMemory(to: UInt8.self).baseAddress,
                      let s = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(d, capacity, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    private static func u16(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func u32(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static func localHeader(name: String, method: UInt16, compressed: Int, uncompressed: Int,
                                    crc: UInt32) -> Data {
        var data = u32(0x0403_4b50)
        data.append(u16(20)) // version
        data.append(u16(0)) // flags
        data.append(u16(Int(method)))
        data.append(u16(0)) // time
        data.append(u16(0)) // date
        data.append(u32(Int(crc)))
        data.append(u32(compressed))
        data.append(u32(uncompressed))
        data.append(u16(name.utf8.count))
        data.append(u16(0)) // extra
        return data
    }

    private static func centralHeader(name: String, method: UInt16, compressed: Int,
                                      uncompressed: Int, offset: Int, crc: UInt32) -> Data {
        var data = u32(0x0201_4b50)
        data.append(u16(20)) // version made by
        data.append(u16(20)) // version needed
        data.append(u16(0)) // flags
        data.append(u16(Int(method)))
        data.append(u16(0))
        data.append(u16(0))
        data.append(u32(Int(crc)))
        data.append(u32(compressed))
        data.append(u32(uncompressed))
        data.append(u16(name.utf8.count))
        data.append(u16(0)) // extra
        data.append(u16(0)) // comment
        data.append(u16(0)) // disk
        data.append(u16(0)) // internal attrs
        data.append(u32(0)) // external attrs
        data.append(u32(offset))
        return data
    }

    private static func endRecord(count: Int, directorySize: Int, offset: Int) -> Data {
        var data = u32(0x0605_4b50)
        data.append(u16(0))
        data.append(u16(0))
        data.append(u16(count))
        data.append(u16(count))
        data.append(u32(directorySize))
        data.append(u32(offset))
        data.append(u16(0))
        return data
    }
}

@Suite("Zip reader")
struct ZipReaderTests {
    @Test("both storage methods come back as the original bytes")
    func readsBothMethods() throws {
        let text = Data("stored page".utf8)
        let squeezed = Data(String(repeating: "compress me please ", count: 40).utf8)
        let zip = ZipBuilder.make([
            (name: "01.png", data: text, deflate: false),
            (name: "02.png", data: squeezed, deflate: true),
        ])
        let entries = try ZipReader.entries(zip)
        #expect(entries.map(\.name) == ["01.png", "02.png"])
        #expect(try ZipReader.contents(of: entries[0], in: zip) == text)
        #expect(try ZipReader.contents(of: entries[1], in: zip) == squeezed)
    }

    @Test("a mac archive's junk is not a page")
    func filtersJunk() throws {
        let zip = ZipBuilder.make([
            (name: "__MACOSX/01.png", data: Data([1]), deflate: false),
            (name: ".hidden.png", data: Data([1]), deflate: false),
            (name: "folder/", data: Data(), deflate: false),
            (name: "folder/notes.txt", data: Data([1]), deflate: false),
            (name: "folder/03.png", data: Data([1]), deflate: false),
        ])
        let pages = try ZipReader.entries(zip).filter(\.isPageCandidate)
        #expect(pages.map(\.name) == ["folder/03.png"])
    }

    @Test("the checksum is the one zip has always used")
    func crcVector() {
        // The canonical test vector: a wrong table or a wrong final XOR both fail
        // here rather than silently accepting every archive.
        #expect(ZipReader.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZipReader.crc32(Data()) == 0)
    }

    @Test("a damaged page is refused instead of decoded into garbage")
    func detectsCorruption() throws {
        var zip = ZipBuilder.make([
            (name: "01.png", data: Data("real page bytes".utf8), deflate: false),
        ], crcOverride: ["01.png": 0xDEAD_BEEF])
        let entries = try ZipReader.entries(zip)
        #expect(throws: ZipReader.Failure.self) {
            _ = try ZipReader.contents(of: entries[0], in: zip)
        }
        // Corrupting the payload instead of the checksum must also be caught.
        zip = ZipBuilder.make([
            (name: "01.png", data: Data("real page bytes".utf8), deflate: false),
        ])
        let good = try ZipReader.entries(zip)
        var broken = zip
        if let index = broken.range(of: Data("real".utf8))?.lowerBound {
            broken[index] = 0x00
            #expect(throws: ZipReader.Failure.self) {
                _ = try ZipReader.contents(of: good[0], in: broken)
            }
        }
    }

    @Test("something that is not a zip says so instead of reading nonsense")
    func rejectsGarbage() {
        #expect(throws: ZipReader.Failure.self) {
            _ = try ZipReader.entries(Data("definitely not a zip".utf8))
        }
    }
}

@Suite("Local comics")
@MainActor
struct LocalComicStoreTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("pages are ordered the way a reader expects, not the way strings sort")
    func naturalOrder() {
        #expect(LocalComicStore.ordered(["10.png", "2.png", "1.png"]) == ["1.png", "2.png", "10.png"])
        #expect(LocalComicStore.ordered(["page9.jpg", "page10.jpg", "page1.jpg"])
                == ["page1.jpg", "page9.jpg", "page10.jpg"])
    }

    @Test("a folder import keeps its pages and survives a relaunch")
    func importsFolder() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["10.png", "2.png", "1.png", "notes.txt"] {
            try Data([0x89, 0x50]).write(to: source.appending(path: name))
        }
        let store = LocalComicStore(directory: root)
        let comic = try store.importComic(at: source)
        #expect(comic.title == "source")
        #expect(comic.pages == ["1.png", "2.png", "10.png"])
        #expect(FileManager.default.fileExists(atPath: store.pageURL(comic, index: 0).path))

        let again = LocalComicStore(directory: root)
        #expect(again.comics.first?.id == comic.id)
    }

    @Test("a cbz import reads the pages out of the archive")
    func importsArchive() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = ZipBuilder.make([
            (name: "pages/02.png", data: Data([0x89, 0x50, 2]), deflate: false),
            (name: "pages/01.png", data: Data([0x89, 0x50, 1]), deflate: true),
            (name: "__MACOSX/pages/01.png", data: Data([0]), deflate: false),
        ])
        let file = root.appending(path: "某漫画.cbz")
        try zip.write(to: file)
        let store = LocalComicStore(directory: root)
        let comic = try store.importComic(at: file)
        #expect(comic.title == "某漫画")
        // Nested paths are flattened, and the macOS sibling is not a page.
        #expect(comic.pages == ["01.png", "02.png"])
    }

    @Test("two folders holding the same file name keep both pages")
    func doesNotFlattenTwoPagesIntoOne() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = ZipBuilder.make([
            (name: "chapter1/01.png", data: Data([1]), deflate: false),
            (name: "chapter2/01.png", data: Data([2]), deflate: false),
        ])
        let file = root.appending(path: "两章.cbz")
        try zip.write(to: file)
        let store = LocalComicStore(directory: root)
        let comic = try store.importComic(at: file)
        // Flattening both to "01.png" would leave one page and lose the other.
        #expect(comic.pages.count == 2)
        #expect(Set(comic.pages).count == 2)
        #expect(comic.pages == ["chapter1-01.png", "chapter2-01.png"])
        #expect(try Data(contentsOf: store.pageURL(comic, index: 1)) == Data([2]))
    }

    @Test("removing a comic removes its files too")
    func removal() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1]).write(to: source.appending(path: "1.png"))
        let store = LocalComicStore(directory: root)
        let comic = try store.importComic(at: source)
        let page = store.pageURL(comic, index: 0)
        store.remove(comic)
        #expect(store.comics.isEmpty)
        // A removed comic that leaves its pages on disk is a leak with a title.
        #expect(!FileManager.default.fileExists(atPath: page.path))
    }
}
