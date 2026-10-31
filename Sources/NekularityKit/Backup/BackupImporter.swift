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
        /// Cookie rows written into source partitions. Zero unless the import
        /// asked for cookies; the old app had one jar and this client has none.
        public var cookiesAdded = 0
    }

    public init() {}

    public func apply(
        _ plan: BackupPlan,
        library: SourceLibrary,
        shelf: ShelfStore,
        searches: SearchHistoryStore,
        jars: CookieJars? = nil
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
        let mapped = BackupImporter.keptPages(from: plan)
        out.picturesSkipped = mapped.picturesSkipped
        out.pagesSkipped = mapped.pagesSkipped
        for entry in mapped.pages {
            if shelf.merge(entry) {
                out.pagesAdded += 1
            } else {
                // Already on the shelf, with a local copy at least as new.
                out.pagesAlreadyKept += 1
            }
        }
        // Cookies go last: their partitions are the sources this plan installs,
        // so a source whose script failed has no partition to write into — the
        // cookie would be stored where nothing can ever send it.
        if let jars {
            let present = Set(library.sources.map(\.key))
            var scoped = plan
            scoped.cookieTargets = plan.cookieTargets?.filter { present.contains($0) }
            out.cookiesAdded = BackupImporter.restoreCookies(scoped, jars: jars)
        }
        out.pendingRows = plan.pending?.rowCount ?? 0
        return out
    }

    /// Writes the plan's cookies into the partitions Core named.
    ///
    /// Every cookie goes to every target; a jar only sends one to a matching
    /// domain, so a copy in a partition that never visits the host does nothing.
    /// Without targets nothing is written: a restore must not invent a shared jar.
    public nonisolated static func restoreCookies(_ plan: BackupPlan, jars: CookieJars) -> Int {
        guard let cookies = plan.cookies, !cookies.isEmpty else { return 0 }
        guard let targets = plan.cookieTargets, !targets.isEmpty else { return 0 }
        let wire = cookies.map {
            WireCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                       expires: $0.expires, secure: $0.secure, httpOnly: $0.httpOnly)
        }
        var written = 0
        for target in targets {
            // The plan names sources; the jar is keyed by partition. Writing to
            // the bare key would store cookies no request ever reads.
            written += jars.restore(partition: CookiePartition.comic(target), cookies: wire)
        }
        return written
    }

    /// The kept pages a backup carries, in the official shape:
    /// `episodes[].imageFavorites[].{page,imageKey,eid,ep}`.
    ///
    /// Split out from `apply` so the mapping itself can be tested: it is the
    /// part where a wrong key would silently restore nothing.
    /// `nonisolated` because it reads the plan and returns values: a test can
    /// call it without hopping to the main actor, and so can a background
    /// import.
    public nonisolated static func keptPages(from plan: BackupPlan) -> (pages: [KeptPage], picturesSkipped: Int, pagesSkipped: Int) {
        var pages: [KeptPage] = []
        var picturesSkipped = 0
        var pagesSkipped = 0
        for picture in plan.imageFavorites ?? [] {
            // A picture whose source Core could not resolve is not lost; it
            // stays in the backup and can be restored once the source exists.
            guard let key = picture.sourceKey, !key.isEmpty, !picture.id.isEmpty else {
                picturesSkipped += 1
                pagesSkipped += picture.keptPages
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
                        pagesSkipped += 1
                        continue
                    }
                    pages.append(KeptPage(source: key, comicID: picture.id, comicTitle: picture.title,
                                          chapterID: chapterID, chapterIndex: chapterIndex,
                                          chapterName: chapterName, page: page, url: url,
                                          time: Int((picture.time ?? 0) / 1000)))
                }
            }
            if seen == 0 { picturesSkipped += 1 }
        }
        return (pages, picturesSkipped, pagesSkipped)
    }
}
