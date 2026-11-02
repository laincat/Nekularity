import Foundation
import Observation

/// Chapters kept on disk, so a phone with no connection still has something to
/// read.
///
/// The files are the bytes the source would have served, saved under the source
/// and comic that produced them: a downloaded chapter is not a cache the system
/// may evict, it is a file the user asked for. `ImageLoader` asks this store
/// before the network, which is what makes the reader work offline without the
/// reader knowing anything about downloads.
@MainActor
@Observable
public final class DownloadStore {
    /// One chapter on disk. `pages` keeps the remote addresses so a downloaded
    /// chapter can be opened again by the reader, which thinks in addresses.
    public struct Chapter: Codable, Sendable, Identifiable, Hashable {
        public var sourceKey: String
        public var comicID: String
        public var comicTitle: String
        public var chapterID: String
        public var chapterTitle: String
        public var pages: [String]
        /// Paths **relative to the download root**. An absolute path contains the
        /// app's container UUID, which changes on reinstall and between devices,
        /// so a manifest written that way points at a file that no longer exists.
        public var files: [String]

        public var id: String { "\(sourceKey)|\(comicID)|\(chapterID)" }
        var folder: String { "\(sourceKey)/\(Self.digest(comicID))/\(Self.digest(chapterID))" }

        static func digest(_ text: String) -> String {
            // The ids a source issues are arbitrary — they can contain slashes,
            // spaces or a whole URL — so a path is built from a hash, never from
            // the id itself.
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            return String(hash, radix: 16)
        }
    }

    /// What to keep. `pages` are the addresses the reader would have loaded.
    public struct Request: Sendable {
        public var sourceKey: String
        public var comicID: String
        public var comicTitle: String
        public var chapterID: String
        public var chapterTitle: String
        public var pages: [String]

        /// The same identity the store keys chapters by: queued and finished
        /// chapters must not be able to disagree about which one they are.
        public var id: String { "\(sourceKey)|\(comicID)|\(chapterID)" }

        public init(sourceKey: String, comicID: String, comicTitle: String,
                    chapterID: String, chapterTitle: String, pages: [String]) {
            self.sourceKey = sourceKey
            self.comicID = comicID
            self.comicTitle = comicTitle
            self.chapterID = chapterID
            self.chapterTitle = chapterTitle
            self.pages = pages
        }
    }

    /// A chapter being written, and how far it got.
    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var failure: String?
    }

    public private(set) var chapters: [String: Chapter] = [:]
    /// Why the manifest could not be read, when it could not.
    public private(set) var failure: String?
    public private(set) var progress: [String: Progress] = [:]
    /// The chapters being written right now, so a screen — or a Live Activity — can say
    /// whose download this is. `progress` is keyed by an id that means nothing outside
    /// this file.
    public private(set) var active: [String: Request] = [:]

    /// One line per running chapter: `id|done|total|failure`. A view observes this to
    /// know something changed, without watching a dictionary of structs.
    public var activitySignature: [String] {
        active.keys.sorted().compactMap { id in
            guard let request = active[id], let progress = progress[id] else { return nil }
            return "\(id)|\(progress.done)|\(progress.total)|\(progress.failure ?? "")"
        }
    }

    /// Fetches one page with the reader's own request rules. The store takes a
    /// function rather than the loader so the write path can be driven without a
    /// Core connection in tests.
    public typealias Fetch = @Sendable (ImageLoader.Key) async throws -> Data

    private let root: URL
    private var queue: [(request: Request, fetch: Fetch, generation: Int)] = []
    /// Bumped whenever an attempt must stop counting: a removed chapter's write
    /// must not put itself back into the archive when it finishes later.
    private var generation: [String: Int] = [:]
    private var running = 0
    /// Two at a time: a phone on a slow connection gains nothing from more, and
    /// every extra fetch is another way for a site to start refusing.
    private let parallel = 2
    /// Addresses already on disk, so the loader answers without touching a file.
    private var index: [String: String] = [:]

    public init(root: URL) {
        self.root = root
        load()
        sweepPartials()
    }

    // MARK: - Reading

    public func isDownloaded(sourceKey: String, comicID: String, chapterID: String) -> Bool {
        chapters["\(sourceKey)|\(comicID)|\(chapterID)"] != nil
    }

    /// The downloaded copy of an image, or nil when it has never been kept.
    ///
    /// Read on every page of the reader, so the hot path is a dictionary lookup;
    /// only a hit touches the disk.
    public func bytes(for key: ImageLoader.Key) -> Data? {
        // Only reader pages are archived. A cover/thumbnail is a different
        // request (its own handler and transform) and must not be answered with
        // a page that happens to share its address.
        guard !key.isThumbnail,
              let comicID = key.comicID, let chapterID = key.chapterID,
              let relative = index[Self.indexKey(source: key.source, comicID: comicID,
                                                 chapterID: chapterID, url: key.url)]
        else { return nil }
        return try? Data(contentsOf: root.appending(path: relative))
    }

    /// The identity of one archived page. The comic is part of it: two comics
    /// in one source may reuse a chapter id and an image address, and an index
    /// keyed by chapter alone would answer with the other comic's bytes.
    private static func indexKey(source: String, comicID: String,
                                 chapterID: String, url: String) -> String {
        "\(source)\u{1F}\(comicID)\u{1F}\(chapterID)\u{1F}\(url)"
    }

    /// Chapters archived for one comic, in the order they were downloaded.
    public func chapters(sourceKey: String, comicID: String) -> [Chapter] {
        chapters.values
            .filter { $0.sourceKey == sourceKey && $0.comicID == comicID }
            .sorted { $0.chapterTitle < $1.chapterTitle }
    }

    public var totalBytes: Int64 {
        chapters.values.reduce(0) { sum, chapter in
            sum + chapter.files.reduce(0) { inner, file in
                inner + Int64((try? FileManager.default.attributesOfItem(
                    atPath: root.appending(path: file).path)[.size] as? Int) ?? 0)
            }
        }
    }

    // MARK: - Writing

    public func download(_ request: Request, fetch: @escaping Fetch) {
        let id = "\(request.sourceKey)|\(request.comicID)|\(request.chapterID)"
        // A chapter on disk is finished, whatever this session remembers: after a
        // restart `progress` is empty, and asking for it again would fetch every
        // page a second time. A failed attempt may be retried, or a chapter that
        // never downloaded could never be asked for again.
        if chapters[id] != nil { return }
        if let existing = progress[id], existing.failure == nil { return }
        progress[id] = Progress(done: 0, total: request.pages.count, failure: nil)
        let attempt = (generation[id] ?? 0) + 1
        generation[id] = attempt
        queue.append((request, fetch, attempt))
        pump()
    }

    public func remove(sourceKey: String, comicID: String, chapterID: String) {
        let id = "\(sourceKey)|\(comicID)|\(chapterID)"
        // Invalidate any attempt before looking for a record. A chapter that is
        // still downloading has none yet, and returning early here would let its
        // write put the chapter back after the user deleted it.
        generation[id, default: 0] += 1
        progress[id] = nil
        active[id] = nil
        queue.removeAll { item in
            "\(item.request.sourceKey)|\(item.request.comicID)|\(item.request.chapterID)" == id
        }
        guard let chapter = chapters[id] else { return }
        let folder = root.appending(path: chapter.folder, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        for page in chapter.pages {
            index[Self.indexKey(source: sourceKey, comicID: comicID,
                                chapterID: chapterID, url: page)] = nil
        }
        chapters[id] = nil
        save()
    }

    /// Drops the whole archive. Used by the storage screen, and the only way a
    /// user can get the space back.
    public func removeAll() {
        // Snapshot the keys: remove() mutates the dictionary.
        for id in Array(chapters.keys) {
            remove(sourceKey: chapters[id]!.sourceKey, comicID: chapters[id]!.comicID,
                   chapterID: chapters[id]!.chapterID)
        }
        // A chapter still downloading has no record to remove yet. Left alone it
        // would finish after the user cleared storage and put itself back, and a
        // queued one would start afterwards and do the same.
        var pending = Set(queue.map { $0.request.id })
        pending.formUnion(active.keys)
        for id in pending {
            generation[id, default: 0] += 1
            progress[id] = nil
            active[id] = nil
        }
        queue.removeAll()
    }

    private func pump() {
        while running < parallel, !queue.isEmpty {
            let (request, fetch, attempt) = queue.removeFirst()
            active["\(request.sourceKey)|\(request.comicID)|\(request.chapterID)"] = request
            running += 1
            Task {
                await write(request, fetch: fetch, attempt: attempt)
                running -= 1
                pump()
            }
        }
    }

    /// The attempt stopped being current: its chapter was removed while the
    /// fetch was in flight.
    private struct AttemptReplaced: Error {}

    private func write(_ request: Request, fetch: Fetch, attempt: Int) async {
        let id = request.id
        let folder = root.appending(path: "\(request.sourceKey)/\(Chapter.digest(request.comicID))/\(Chapter.digest(request.chapterID))",
                                    directoryHint: .isDirectory)
        var files: [String] = []
        var saved: [String] = []
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (number, page) in request.pages.enumerated() {
                let key = ImageLoader.Key(source: request.sourceKey, url: page,
                                          comicID: request.comicID, chapterID: request.chapterID,
                                          isThumbnail: false)
                if generation[id] != attempt { throw AttemptReplaced() }
                let body = try await fetch(key)
                if generation[id] != attempt { throw AttemptReplaced() }
                let file = folder.appending(path: "\(number).img")
                try body.write(to: file, options: .atomic)
                files.append(file.path.replacingOccurrences(of: root.path + "/", with: ""))
                saved.append(page)
                progress[id] = Progress(done: number + 1, total: request.pages.count, failure: nil)
            }
            if generation[id] != attempt { throw AttemptReplaced() }
            let chapter = Chapter(sourceKey: request.sourceKey, comicID: request.comicID,
                                  comicTitle: request.comicTitle, chapterID: request.chapterID,
                                  chapterTitle: request.chapterTitle, pages: saved, files: files)
            chapters[id] = chapter
            for (page, file) in zip(saved, files) {
                index[Self.indexKey(source: request.sourceKey, comicID: request.comicID,
                                    chapterID: request.chapterID, url: page)] = file
            }
            progress[id] = Progress(done: saved.count, total: request.pages.count, failure: nil)
            active[id] = nil
            save()
        } catch is AttemptReplaced {
            // The user removed the chapter while it was being written. Leave the
            // record as removed; do not report a failure the user did not cause.
            try? FileManager.default.removeItem(at: folder)
            active[id] = nil
        } catch {
            // A half-written chapter is not a chapter: keeping it would make the
            // reader show three pages of a twenty-page chapter and call it a
            // download.
            try? FileManager.default.removeItem(at: folder)
            progress[id] = Progress(done: 0, total: request.pages.count,
                                    failure: CoreError.readable(error.localizedDescription))
            active[id] = nil
        }
    }

    // MARK: - Persistence

    private func load() {
        let manifest = root.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifest) else { return }
        guard let list = try? JSONDecoder().decode([Chapter].self, from: data) else {
            // A manifest that will not decode means chapters that exist on disk but
            // are unreachable; saving an empty one next would delete the record of
            // files the user still has.
            _ = StoreRescue.keepCopy(of: manifest)
            failure = "下载清单读不出来,旧数据已另存一份"
            return
        }
        for chapter in list {
            // The manifest says "downloaded"; the disk decides. Files can be gone
            // — cleared by the system, restored from a backup that skipped them,
            // removed outside the app — and a record whose folder is missing would
            // mark the chapter downloaded while every page still came from the
            // network.
            let folder = root.appending(path: chapter.folder, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            chapters[chapter.id] = chapter
            for (page, file) in zip(chapter.pages, chapter.files) {
                index[Self.indexKey(source: chapter.sourceKey, comicID: chapter.comicID,
                                    chapterID: chapter.chapterID, url: page)] = file
            }
        }
    }

    /// Removes chapter folders no manifest record points at.
    ///
    /// A write that is interrupted — the app is killed, the phone runs out of
    /// power — leaves a folder and a few pages behind, and nothing will ever
    /// refer to them again: the manifest is only written once a chapter is
    /// complete. Left alone they are disk space the storage screen cannot even
    /// show, because it lists chapters.
    private func sweepPartials() {
        let manager = FileManager.default
        let kept = Set(chapters.values.map(\.folder))
        guard let sources = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        for source in sources where isDirectory(source) {
            let comics = (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for comic in comics where isDirectory(comic) {
                let parts = (try? manager.contentsOfDirectory(at: comic, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for part in parts where isDirectory(part) {
                    let relative = "\(source.lastPathComponent)/\(comic.lastPathComponent)/\(part.lastPathComponent)"
                    if !kept.contains(relative) {
                        try? manager.removeItem(at: part)
                    }
                }
                // A comic folder that held only a partial chapter is now empty.
                if ((try? manager.contentsOfDirectory(atPath: comic.path)) ?? []).isEmpty {
                    try? manager.removeItem(at: comic)
                }
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func save() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let list = chapters.values.sorted { $0.id < $1.id }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: root.appending(path: "manifest.json"), options: .atomic)
    }
}
