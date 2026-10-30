import Foundation

/// Writes a Core-made restore plan into this client's own stores.
///
/// Core does the reading: `ReadBackup`/`PlanBackup` unwind the archive, its
/// sqlite tables and the source type hashes, so nothing here parses a
/// `.venera` file. This step installs sources through the normal flow and
/// merges the rows, which leaves newer local positions alone.
@MainActor
public struct BackupImporter {
    public struct Result: Sendable {
        public var sourcesInstalled = 0
        /// "key: reason", so a partial import says what it skipped.
        public var sourcesFailed: [String] = []
        public var historyAdded = 0
        public var favouritesAdded = 0
        public var foldersCreated = 0
        public var searchesAdded = 0
        /// Kept pages restored onto the shelf, and kept pictures this client
        /// could not place (no source, or no page inside).
        public var pagesAdded = 0
        /// Pages already on the shelf, with a local copy at least as new.
        public var pagesAlreadyKept = 0
        /// Kept pictures this restore could not place, and pages it could not
        /// read at all.
        public var picturesSkipped = 0
        public var pagesSkipped = 0
        /// Rows that need a source the backup did not carry a script for.
        public var pendingRows = 0
    }

    public init() {}

    public func apply(
        _ plan: BackupPlan,
        library: SourceLibrary,
        shelf: ShelfStore,
        searches: SearchHistoryStore
    ) async -> Result {
        var out = Result()

        for entry in plan.sources ?? [] {
            guard let script = entry.script, !script.isEmpty else { continue }
            if library.sources.contains(where: { $0.key == entry.key }) { continue }
            do {
                _ = try await library.install(script: script, origin: "backup")
                out.sourcesInstalled += 1
            } catch {
                out.sourcesFailed.append("\(entry.key): \(error.localizedDescription)")
            }
        }

        for item in plan.history ?? [] {
            guard let key = item.sourceKey, !key.isEmpty, !item.id.isEmpty else { continue }
            let comic = ShelfComic(source: key, id: item.id, title: item.title,
                                   author: item.subtitle, cover: item.cover)
            let entry = ShelfHistory(comic: comic,
                                     chapter: nil,
                                     chapterIndex: Int(item.ep),
                                     page: item.page > 0 ? Int(item.page) : nil,
                                     percent: nil,
                                     time: Int(item.time / 1000))
            if shelf.merge(entry) { out.historyAdded += 1 }
        }

        for folder in plan.folders ?? [] {
            let known = shelf.folderNames().contains(folder.name)
            if !known, !folder.name.isEmpty {
                shelf.createFolder(folder.name)
                out.foldersCreated += 1
            }
            for item in folder.items {
                guard let key = item.sourceKey, !key.isEmpty, !item.id.isEmpty else { continue }
                let comic = ShelfComic(source: key, id: item.id, title: item.name,
                                       author: item.author, cover: item.cover)
                if shelf.add(comic, to: folder.name) { out.favouritesAdded += 1 }
            }
        }

        out.searchesAdded = searches.merge(plan.searchHistory ?? [])
        // Kept pages are references to the source's images, which this client
        // can store now, so a restore keeps them instead of counting them.
        for picture in plan.imageFavorites ?? [] {
            // A picture whose source Core could not resolve is not lost, it
            // stays in the backup; it just cannot land here yet.
            guard let key = picture.sourceKey, !key.isEmpty, !picture.id.isEmpty else {
                out.picturesSkipped += 1
                out.pagesSkipped += picture.keptPages
                continue
            }
            var seen = 0
            for episode in picture.episodes?.array ?? [] {
                let chapterID = episode["eid"]?.stringValue ?? ""
                let chapterIndex = Int(episode["ep"]?.stringValue ?? "") ?? 0
                let chapterName = episode["epName"]?.stringValue
                for mark in episode["imageFavorites"]?.array ?? [] {
                    seen += 1
                    guard let url = mark["imageKey"]?.stringValue, !url.isEmpty,
                          let page = Int(mark["page"]?.stringValue ?? "") else {
                        out.pagesSkipped += 1
                        continue
                    }
                    let entry = KeptPage(source: key, comicID: picture.id, comicTitle: picture.title,
                                         chapterID: chapterID, chapterIndex: chapterIndex,
                                         chapterName: chapterName, page: page, url: url,
                                         time: Int((picture.time ?? 0) / 1000))
                    if shelf.merge(entry) {
                        out.pagesAdded += 1
                    } else {
                        // Already on the shelf, and the local copy is newer.
                        out.pagesAlreadyKept += 1
                    }
                }
            }
            if seen == 0 { out.picturesSkipped += 1 }
        }
        out.pendingRows = plan.pending?.rowCount ?? 0
        return out
    }
}
