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
        List {
            if shelf.recentHistory().filter({ !$0.isVideo }).isEmpty && shelf.folders.isEmpty && shelf.pictures.isEmpty {
                ContentUnavailableView {
                    Label("书架还是空的", systemImage: "books.vertical")
                } description: {
                    Text("打开的章节会记在这里,详情页可以收藏漫画。")
                }
            }
            let reading = shelf.recentHistory().filter { !$0.isVideo }
            if !reading.isEmpty {
                Section("继续阅读") {
                    ForEach(reading, id: \.key) { entry in
                        historyRow(entry)
                    }
                }
            }
            ForEach(shelf.folders) { folder in
                folderSection(folder)
            }
            if !shelf.keptPages().isEmpty {
                Section {
                    ForEach(shelf.keptPages(), id: \.id) { page in
                        NavigationLink {
                            ComicDetailView(route: page.route)
                        } label: {
                            KeptPageRow(page: page)
                        }
                        .swipeActions {
                            Button("取消收藏", role: .destructive) {
                                shelf.forgetPage(page)
                            }
                        }
                    }
                } header: {
                    Text("图片收藏 · \(shelf.pictures.count) 张")
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
        .themedPage()
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink { DownloadsView() } label: {
                        Label("下载", systemImage: "arrow.down.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("shelf.more")
            }
            if let error = shelf.lastError {
                ToolbarItem(placement: .bottomBar) {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder
    private func historyRow(_ entry: ShelfHistory) -> some View {
        NavigationLink {
            ComicDetailView(route: entry.comic.route)
        } label: {
            HistoryRow(entry: entry)
        }
        .swipeActions {
            Button("移除", role: .destructive) {
                shelf.forgetHistory(source: entry.source, id: entry.id)
            }
        }
    }

    /// One folder. Kept apart from `body`: the whole list as one expression
    /// made the type checker give up in reasonable time.
    @ViewBuilder
    private func folderSection(_ folder: ShelfFolder) -> some View {
        Section {
            if folder.items.isEmpty {
                Text("（空）").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(folder.items, id: \.key) { comic in
                comicRow(comic, in: folder)
            }
        } header: {
            folderHeader(folder)
        }
    }

    @ViewBuilder
    private func comicRow(_ comic: ShelfComic, in folder: ShelfFolder) -> some View {
        NavigationLink {
            ComicDetailView(route: comic.route)
        } label: {
            ComicRow(comic: comic)
        }
        .swipeActions {
            Button("取消收藏", role: .destructive) {
                shelf.remove(comic, from: folder.name)
            }
        }
        .contextMenu {
            moveMenu(comic, in: folder)
        }
    }

    @ViewBuilder
    private func moveMenu(_ comic: ShelfComic, in folder: ShelfFolder) -> some View {
        let others = shelf.folderNames().filter { $0 != folder.name }
        if others.isEmpty {
            Text("只有一个收藏夹")
        } else {
            Menu("移动到") {
                ForEach(others, id: \.self) { name in
                    Button(name) { shelf.move(comic, to: name) }
                }
            }
        }
    }

    private func folderHeader(_ folder: ShelfFolder) -> some View {
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
        if let page = entry.page, page > 0 {
            parts.append("第 \(page) 页")
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

private struct KeptPageRow: View {
    let page: KeptPage

    var body: some View {
        HStack(spacing: 12) {
            SourceImage(key: ImageLoader.Key(source: page.source, url: page.url,
                                             comicID: page.comicID, chapterID: page.chapterID,
                                             isThumbnail: true), maxPixel: 180)
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(page.comicTitle).lineLimit(1)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let name = page.chapterName, !name.isEmpty {
            parts.append(name)
        } else {
            parts.append("第 \(page.chapterIndex + 1) 话")
        }
        parts.append("第 \(page.page) 页")
        return parts.joined(separator: " · ")
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

private extension KeptPage {
    /// A kept page opens the comic it came from; the reader starts from the
    /// shelf's own position, so no chapter is invented here.
    var route: ComicRoute {
        ComicRoute(source: source,
                   comic: Comic(id: comicID, title: comicTitle),
                   chapterID: chapterID.isEmpty ? nil : chapterID)
    }
}

private extension ShelfComic {
    /// The shelf keeps the fields it needs; the screens take the full comic.
    var asComic: Comic {
        Comic(id: id, title: title, subtitle: author, cover: cover)
    }

    var route: ComicRoute {
        ComicRoute(source: source, comic: asComic)
    }
}
