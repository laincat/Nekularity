import SwiftUI
import NekularityKit

/// Reading history and favourites, the reader's own list.
struct ShelfView: View {
    @Environment(ShelfStore.self) private var shelf
    @State private var newFolder = ""
    /// The folder being renamed, and the name typed for it.
    @State private var renaming: ShelfFolder?
    @State private var renameTo = ""

    var body: some View {
        NavigationStack {
            List {
                if shelf.recentHistory().isEmpty && shelf.folders.isEmpty {
                    ContentUnavailableView {
                        Label("书架还是空的", systemImage: "books.vertical")
                    } description: {
                        Text("打开的章节会记在这里,详情页可以收藏漫画。")
                    }
                }
                if !shelf.recentHistory().isEmpty {
                    Section("继续阅读") {
                        ForEach(shelf.recentHistory()) { entry in
                            NavigationLink(value: ComicRoute(source: entry.source,
                                                             comic: entry.comic.asComic)) {
                                HistoryRow(entry: entry)
                            }
                            .swipeActions {
                                Button("移除", role: .destructive) {
                                    shelf.forgetHistory(source: entry.source, id: entry.id)
                                }
                            }
                        }
                    }
                }
                ForEach(shelf.folders) { folder in
                    Section {
                        if folder.items.isEmpty {
                            Text("（空）").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(folder.items) { comic in
                            NavigationLink(value: ComicRoute(source: comic.source, comic: comic.asComic)) {
                                ComicRow(comic: comic)
                            }
                            .swipeActions {
                                Button("取消收藏", role: .destructive) {
                                    shelf.remove(comic, from: folder.name)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(folder.name) · \(folder.items.count) 部")
                            Spacer()
                            Menu {
                                Button("重命名") {
                                    renameTo = folder.name
                                    renaming = folder
                                }
                                Button("删除收藏夹", role: .destructive) {
                                    shelf.deleteFolder(folder.name)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("新收藏夹的名字", text: $newFolder)
                        Button("新建") {
                            shelf.createFolder(newFolder)
                            newFolder = ""
                        }
                        .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("书架")
            .alert("重命名收藏夹", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("名字", text: $renameTo)
                Button("确定") {
                    if let folder = renaming {
                        shelf.renameFolder(folder.name, to: renameTo)
                    }
                    renaming = nil
                }
                Button("取消", role: .cancel) { renaming = nil }
            }
            .navigationDestination(for: ComicRoute.self) { route in
                ComicDetailView(route: route)
            }
            .toolbar {
                if let error = shelf.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: ShelfHistory

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: entry.cover, source: entry.source, id: entry.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let chapter = entry.chapter, !chapter.isEmpty {
            parts.append(chapter)
        } else {
            parts.append("第 \(entry.chapterIndex + 1) 话")
        }
        if let percent = entry.percent, percent > 0 {
            parts.append("\(percent)%")
        }
        parts.append(Self.when(entry.time))
        return parts.joined(separator: " · ")
    }

    static func when(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ComicRow: View {
    let comic: ShelfComic

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: comic.cover, source: comic.source, id: comic.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title).lineLimit(1)
                if let author = comic.author, !author.isEmpty {
                    Text(author).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

private struct Cover: View {
    let url: String?
    let source: String
    let id: String

    var body: some View {
        SourceImage(key: ImageLoader.Key(source: source, url: url ?? "", comicID: id, isThumbnail: true), maxPixel: 180)
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private extension ShelfComic {
    /// The shelf keeps the fields it needs; the screens take the full comic.
    var asComic: Comic {
        Comic(id: id, title: title, subtitle: author, cover: cover)
    }
}
