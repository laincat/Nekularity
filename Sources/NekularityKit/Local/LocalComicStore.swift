import Foundation
import Observation

/// A comic that lives on this device: a folder of images or a `.cbz`.
public struct LocalComic: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// File names inside the comic's own directory, already in reading order.
    public var pages: [String]
    public var importedAt: Date
    /// The page last shown, so reopening continues instead of starting over.
    public var lastPage: Int = 0

    public init(id: String = UUID().uuidString, title: String, pages: [String], importedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.pages = pages
        self.importedAt = importedAt
    }

    public var pageCount: Int { pages.count }
}

/// Comics imported from this device, kept next to the sources rather than in them.
///
/// A local comic is not a source: there is no script, no network and no id space to
/// agree on. It gets its own directory, its own list, and a reader that opens a
/// file path instead of a chapter URL.
@MainActor
@Observable
public final class LocalComicStore {
    public private(set) var comics: [LocalComic] = []
    public private(set) var failure: String?

    private let directory: URL
    private let file: URL

    public init(directory: URL) {
        self.directory = directory.appending(path: "Comics", directoryHint: .isDirectory)
        file = directory.appending(path: "local-comics.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([LocalComic].self, from: data) {
            comics = decoded
        } else {
            _ = StoreRescue.keepCopy(of: file)
            failure = "本地漫画列表读不出来,旧数据已另存一份"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(comics)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            failure = "无法保存本地漫画列表(\(error.localizedDescription))"
        }
    }

    public func pageURL(_ comic: LocalComic, index: Int) -> URL {
        directory.appending(path: comic.id, directoryHint: .isDirectory)
            .appending(path: comic.pages[index])
    }

    /// Imports a folder of images, or an archive of them.
    ///
    /// The reading and writing happen off the main actor: a comic archive is
    /// hundreds of megabytes, and unpacking one on the main actor freezes the
    /// interface for as long as it takes — which a user reads as a crash.
    @discardableResult
    public func importComic(at url: URL) async throws -> LocalComic {
        let directory = self.directory
        let id = UUID().uuidString
        let names = try await Task.detached(priority: .userInitiated) {
            try Self.unpack(from: url, id: id, into: directory)
        }.value

        let title = url.deletingPathExtension().lastPathComponent
        let comic = LocalComic(id: id, title: title.isEmpty ? "未命名" : title, pages: names)
        comics.append(comic)
        save()
        return comic
    }

    /// The part that touches the file system, kept off the main actor.
    private nonisolated static func unpack(from url: URL, id: String, into directory: URL) throws -> [String] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = directory.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var names: [String] = []
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let contents = try FileManager.default.contentsOfDirectory(at: url,
                                                                      includingPropertiesForKeys: nil)
            for source in contents where isPageName(source.lastPathComponent) {
                let name = source.lastPathComponent
                try FileManager.default.copyItem(at: source, to: destination.appending(path: name))
                names.append(name)
            }
        } else {
            let data = try Data(contentsOf: url)
            let entries = try ZipReader.entries(data).filter(\.isPageCandidate)
            guard !entries.isEmpty else {
                try? FileManager.default.removeItem(at: destination)
                throw ZipReader.Failure.unsupported("里面没有图片")
            }
            var taken = Set<String>()
            for entry in entries {
                let bytes = try ZipReader.contents(of: entry, in: data)
                // Only the last path component is kept: an archive may nest pages
                // two directories deep and the reader wants a flat list. Two
                // folders can hold the same file name, though — flattening them
                // onto one another silently drops a page, so a clash keeps its
                // parent as a prefix.
                let flat = entry.name.split(separator: "/").last.map(String.init) ?? entry.name
                let name = taken.contains(flat) ? Self.prefixed(entry.name, fallback: flat) : flat
                if taken.contains(name) {
                    throw ZipReader.Failure.unsupported("压缩包里有重名图片:\(entry.name)")
                }
                taken.insert(name)
                try bytes.write(to: destination.appending(path: name), options: [.atomic])
                names.append(name)
            }
        }

        let ordered = ordered(names)
        guard !ordered.isEmpty else {
            try? FileManager.default.removeItem(at: destination)
            throw ZipReader.Failure.unsupported("这个位置没有图片")
        }
        return ordered
    }

    /// Remembers where the reader stopped.
    public func mark(_ comic: LocalComic, page: Int) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[index].lastPage = max(0, min(page, max(0, comics[index].pages.count - 1)))
        save()
    }

    public func remove(_ comic: LocalComic) {
        comics.removeAll { $0.id == comic.id }
        try? FileManager.default.removeItem(at: directory.appending(path: comic.id, directoryHint: .isDirectory))
        save()
    }

    /// `chapter2/01.png` → `chapter2-01.png`, which keeps reading order intact
    /// because the sort is natural and the prefix comes first.
    private nonisolated static func prefixed(_ path: String, fallback: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return fallback }
        return parts.suffix(2).joined(separator: "-")
    }

    private nonisolated static func isPageName(_ name: String) -> Bool {
        ZipReader.Entry.pageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Page order as a reader expects it: `2.png` before `10.png`.
    ///
    /// Plain string sorting puts ten before two, which is the single most common
    /// way an imported comic reads out of order.
    public nonisolated static func ordered(_ names: [String]) -> [String] {
        names.sorted { left, right in
            left.compare(right, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }
}
