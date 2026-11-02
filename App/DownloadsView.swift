import NekularityKit
import SwiftUI

/// Chapters kept on this device.
///
/// This is a place to spend disk on purpose and to get it back: which chapters
/// are here, how big they are, and a delete that actually deletes. Downloads are
/// not a cache the system may evict, so they need a screen that says what they
/// cost.
struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloads

    private var groups: [(comic: String, chapters: [DownloadStore.Chapter])] {
        Dictionary(grouping: downloads.chapters.values, by: { "\($0.sourceKey)|\($0.comicID)" })
            .map { _, chapters in
                (comic: chapters.first?.comicTitle ?? "", chapters: chapters.sorted { $0.chapterTitle < $1.chapterTitle })
            }
            .sorted { $0.comic < $1.comic }
    }

    var body: some View {
        Group {
            if downloads.chapters.isEmpty && downloads.failures.isEmpty {
                ContentUnavailableView("还没有下载", systemImage: "arrow.down.circle",
                                       description: Text("在漫画详情页长按章节即可下载，下载后没有网络也能看。"))
            } else {
                List {
                    if !downloads.failures.isEmpty {
                        // A failed attempt is the one state that used to be invisible:
                        // no chapter record means no row anywhere, so the chapter the
                        // user asked for simply never arrived.
                        Section("没有下载完成") {
                            ForEach(failed) { failure in
                                failedRow(failure)
                                    .swipeActions(edge: .trailing) {
                                        Button("删除", role: .destructive) {
                                            downloads.discardFailure(failure.id)
                                        }
                                    }
                            }
                        }
                    }
                    Section {
                        ForEach(groups, id: \.comic) { group in
                            ForEach(group.chapters) { chapter in
                                // A downloaded chapter is readable with no network,
                                // but until now the only way in was back through a
                                // source that needs one. The row is the entry.
                                NavigationLink {
                                    ReaderRouteView(chapter: chapter)
                                } label: {
                                    row(chapter)
                                }
                            }
                        }
                    } footer: {
                        Text("共 \(downloads.chapters.count) 话，占用 \(Self.size(downloads.totalBytes))")
                    }
                }
            }
        }
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Failures are part of what this screen holds now, so a screen with
            // only failures still needs a way to clear them; removeAll covers both.
            if !downloads.chapters.isEmpty || !downloads.failures.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("全部删除", role: .destructive) { downloads.removeAll() }
                }
            }
        }
    }

    /// Failures in a stable order, so a list that changes does not require a tap.
    private var failed: [DownloadStore.Failure] {
        downloads.failures.values.sorted { $0.id < $1.id }
    }

    private func failedRow(_ failure: DownloadStore.Failure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.request.comicTitle).font(.headline)
            HStack {
                Text(failure.request.chapterTitle)
                Spacer()
                Button("重试") { downloads.retry(failure.id) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("download.retry")
            }
            Text(failure.message).font(.caption).foregroundStyle(.red)
        }
    }

    private func row(_ chapter: DownloadStore.Chapter) -> some View {
        let id = chapter.id
        let progress = downloads.progress[id]
        return VStack(alignment: .leading, spacing: 4) {
            Text(chapter.comicTitle).font(.headline)
            HStack {
                Text(chapter.chapterTitle)
                Spacer()
                if let progress {
                    if let failure = progress.failure {
                        Text(failure).font(.caption).foregroundStyle(.red)
                    } else {
                        Text("\(progress.done)/\(progress.total)").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(chapter.files.count) 页").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button("删除", role: .destructive) {
                downloads.remove(sourceKey: chapter.sourceKey, comicID: chapter.comicID,
                                 chapterID: chapter.chapterID)
            }
        }
    }

    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// A downloaded chapter opened on its own.
///
/// The route carries one chapter, so the reader's "next chapter" has nothing to
/// go to — which is honest: the others are not on this device.
private struct ReaderRouteView: View {
    let chapter: DownloadStore.Chapter

    var body: some View {
        ReaderView(route: ReaderRoute(source: chapter.sourceKey,
                                     comicID: chapter.comicID,
                                     comicTitle: chapter.comicTitle,
                                     chapters: [ComicDetails.Chapter(id: chapter.chapterID,
                                                                     title: chapter.chapterTitle,
                                                                     group: nil)],
                                     index: 0))
    }
}
