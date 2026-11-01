import NekularityKit
import SwiftUI

/// The first tab: blocks the user arranges.
///
/// A block is either one of the app's own lists or a section a source declares —
/// a source's recommendation strip, its ranking, its own favourites. The second
/// kind is what makes the home screen read the installed plugins instead of only
/// local records.
struct DiscoverView: View {
    @Environment(HomeLayout.self) private var layout
    @Environment(ShelfStore.self) private var shelf
    @Environment(SearchHistoryStore.self) private var searches
    @Environment(DownloadStore.self) private var downloads
    @Environment(VideoLibraryStore.self) private var media
    @Environment(SourceLibrary.self) private var library

    @State private var editing = false
    @State private var searching = false
    @State private var browsing = false
    @State private var watching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if layout.visible.isEmpty {
                    ContentUnavailableView("首页是空的", systemImage: "square.grid.2x2",
                                           description: Text("编辑里把要看的卡片打开。"))
                        .padding(.top, 60)
                } else {
                    MasonryLayout(spacing: 12) {
                        ForEach(layout.visible) { block in
                            card(block).wideBlock(block.isWide)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "完成" : "编辑") {
                        if editing { editing = false } else { editing = true }
                    }
                    .accessibilityIdentifier("discover.edit")
                }
                if editing {
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: { Label("从源添加", systemImage: "plus") }
                            .accessibilityIdentifier("discover.addBlock")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { searching = true } label: { Label("搜索", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("discover.search")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { browsing = true } label: { Label("浏览", systemImage: "square.grid.2x2") }
                        .accessibilityIdentifier("discover.browse")
                }
            }
            .navigationDestination(isPresented: $searching) { SearchView() }
            .navigationDestination(isPresented: $browsing) { BrowseView() }
            .navigationDestination(isPresented: $watching) { VideoView() }
            .sheet(isPresented: $adding) {
                SourcePickerView { ref in layout.add(ref) }.environment(library)
            }
            .navigationDestination(for: ComicRoute.self) { ComicDetailView(route: $0) }
        }
    }

    private func card(_ block: HomeBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(block)
            switch block.kind {
            case .template(let template):
                switch template {
                case .history: historyBlock
                case .favorites: favoritesBlock
                case .searches: searchesBlock
                case .downloads: downloadsBlock
                case .localVideos: localVideosBlock
                case .videoSources: videoBlock
                }
            case .source(let ref):
                SourceStrip(ref: ref)
            }
            if editing {
                HStack(spacing: 14) {
                    Button { layout.setEnabled(block, false) } label: {
                        Label("隐藏", systemImage: "eye.slash")
                    }
                    Button { layout.move(block, by: -1) } label: {
                        Label("上移", systemImage: "arrow.up")
                    }
                    .disabled(layout.blocks.first?.id == block.id)
                    Button { layout.move(block, by: 1) } label: {
                        Label("下移", systemImage: "arrow.down")
                    }
                    .disabled(layout.blocks.last?.id == block.id)
                    Spacer()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func header(_ block: HomeBlock) -> some View {
        HStack(spacing: 6) {
            Image(systemName: block.symbol).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title).font(.subheadline.weight(.semibold))
                if let subtitle = block.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Blocks the app builds itself

    private var historyBlock: some View {
        Group {
            let recent = Array(shelf.history.prefix(6))
            if recent.isEmpty {
                Text("还没有阅读记录").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recent, id: \.key) { entry in
                            NavigationLink(value: ComicRoute(source: entry.source,
                                                             comic: Comic(id: entry.id, title: entry.title,
                                                                          subtitle: entry.author, cover: entry.cover))) {
                                VStack(alignment: .leading, spacing: 4) {
                                    cover(entry.source, entry.comic.cover, width: 96, height: 132)
                                    Text(entry.comic.title).font(.caption).lineLimit(1)
                                    if let chapter = entry.chapter {
                                        Text(chapter).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var favoritesBlock: some View {
        Group {
            let folders = shelf.folders
            if folders.allSatisfy({ $0.items.isEmpty }) {
                Text("收藏夹还是空的").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(folders.prefix(3), id: \.name) { folder in
                        HStack {
                            Text(folder.name).font(.caption)
                            Spacer()
                            Text("\(folder.items.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var searchesBlock: some View {
        Group {
            let words = Array(searches.queries.prefix(6))
            if words.isEmpty {
                Text("没有搜索记录").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowRow(items: words) { word in
                    Button(word) { searching = true }
                        .font(.caption).buttonStyle(.bordered)
                }
            }
        }
    }

    private var downloadsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(downloads.chapters.count)").font(.title2.bold())
            Text("话已保存").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var localVideosBlock: some View {
        Group {
            if media.items.isEmpty {
                Button("导入视频") { watching = true }.font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(media.items.count)").font(.title2.bold())
                    Text("个本机视频").font(.caption).foregroundStyle(.secondary)
                    if let resume = media.resume {
                        Button("继续 \(resume.title)") { watching = true }
                            .font(.caption2).lineLimit(1)
                    }
                }
            }
        }
    }

    private var videoBlock: some View {
        Button { watching = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(library.sources.filter { $0.enabled && $0.isVideo }.count)").font(.title2.bold())
                Text("个视频源").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func cover(_ source: String, _ url: String?, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let url, let parsed = URL(string: url) {
                SourceImage(key: .init(source: source, url: parsed.absoluteString, isThumbnail: true), maxPixel: 300)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One strip of a source's own browse page: its recommendations, its ranking.
///
/// The list comes from the same Core call the browse screen uses, so a source
/// that already works in 浏览 works here without knowing this screen exists.
struct SourceStrip: View {
    let ref: HomeBlock.SourceRef
    @Environment(SourceLibrary.self) private var library
    @State private var comics: [Comic] = []
    @State private var failure: String?

    var body: some View {
        Group {
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
            } else if comics.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(comics.prefix(10)) { comic in
                            NavigationLink(value: ComicRoute(source: ref.key, comic: comic)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Group {
                                        if let cover = comic.cover, let url = URL(string: cover) {
                                            SourceImage(key: .init(source: ref.key, url: url.absoluteString,
                                                                   isThumbnail: true), maxPixel: 300)
                                        } else {
                                            Color.secondary.opacity(0.2)
                                        }
                                    }
                                    .frame(width: 96, height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(comic.title).font(.caption).lineLimit(1)
                                    if let subtitle = comic.subtitle {
                                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let result = try await library.core.explore(key: ref.key, index: ref.index)
            comics = result.sections.flatMap(\.comics)
            if comics.isEmpty { failure = "这个分区没有内容" }
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }
}

/// A wrapping row of small chips, which SwiftUI has no built-in for.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in content(item) }
                }
            }
        }
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
    }
}
