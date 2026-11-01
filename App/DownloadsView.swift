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
            if downloads.chapters.isEmpty {
                ContentUnavailableView("还没有下载", systemImage: "arrow.down.circle",
                                       description: Text("在漫画详情页长按章节即可下载，下载后没有网络也能看。"))
            } else {
                List {
                    Section {
                        ForEach(groups, id: \.comic) { group in
                            ForEach(group.chapters) { chapter in
                                row(chapter)
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
            if !downloads.chapters.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("全部删除", role: .destructive) { downloads.removeAll() }
                }
            }
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
