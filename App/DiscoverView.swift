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
    @Environment(MetadataStore.self) private var metadata
    @Environment(LocalComicStore.self) private var local

    @State private var editing = false
    /// Counts long presses, so the board can give a tap of feedback when it switches
    /// into arranging.
    @State private var editPulse = 0
    @State private var searching = false
    @State private var browsing = false
    @State private var adding = false
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
                            card(block)
                                .wideBlock(block.span == 2)
                                // Drag is the arrangement; the up and down buttons it
                                // replaced asked the user to move things one step at a
                                // time and to count positions.
                                .draggable(block.id)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let id = items.first else { return false }
                                    layout.moveBlock(id, before: block.id)
                                    return true
                                }
                        }
                    }
                    // A drop below the last card means "at the end".
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first else { return false }
                        layout.moveBlockToEnd(id)
                        return true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("发现")
            .overlay {
                if editing {
                    // Taps land on the editing controls, not on the cards underneath:
                    // opening a comic while trying to resize one was the complaint.
                    Color.clear.contentShape(Rectangle()).allowsHitTesting(false)
                }
            }
            .contentMargins(.bottom, 76, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "完成" : "编辑") {
                        if editing { editing = false } else { editing = true }
                    }
                    .buttonStyle(Pill(filled: editing))
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
            // While arranging, a tap on a cover should not open a comic: the card is
            // being moved, not read.
            Group {
            switch block.kind {
            case .template(let template):
                switch template {
                case .history: historyBlock
                case .continueWatching: continueWatchingBlock
                case .upcoming: upcomingBlock
                case .localComics: localComicsBlock
                case .favorites: favoritesBlock
                case .searches: searchesBlock
                case .downloads: downloadsBlock
                case .localVideos: localVideosBlock
                case .videoSources: videoBlock
                }
            case .source(let ref):
                SourceStrip(ref: ref)
            }
            }
            .allowsHitTesting(!editing)
            if editing {
                HStack(spacing: 16) {
                    // The handle says the card can be dragged; without it the gesture
                    // is invisible and the card looks inert.
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("拖动排序")

                    Button {
                        layout.setColumns(block, block.span == 2 ? 1 : 2)
                    } label: {
                        Label(block.span == 2 ? "改为半宽" : "改为整宽",
                              systemImage: block.span == 2 ? "rectangle.split.2x1" : "rectangle")
                    }
                    .accessibilityIdentifier("home.size.\(block.id)")

                    Button { layout.setEnabled(block, false) } label: {
                        Label("隐藏", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("home.hide.\(block.id)")

                    Spacer()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onLongPressGesture(minimumDuration: 0.35) {
            guard !editing else { return }
            editPulse += 1
            withAnimation(.snappy) { editing = true }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: editPulse)
    }

    private func header(_ block: HomeBlock) -> some View {
        SectionHeader(title: block.title, subtitle: block.subtitle)
    }

    // MARK: - Blocks the app builds itself

    private var historyBlock: some View {
        Group {
            // Watching has its own block; a video row here would open a comic
            // screen that has nothing to show.
            let recent = Array(shelf.history.filter { !$0.isVideo }.prefix(6))
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

    /// What to watch next, in the same history the reader's own list comes from.
    ///
    /// Rows rather than covers: a film's position is the useful fact here, and a
    /// poster grid says nothing about how far in it is.
    private var continueWatchingBlock: some View {
        Group {
            let rows = shelf.history.filter { entry in
                guard entry.isVideo, let percent = entry.videoPercent else { return false }
                return percent > 2 && percent < 95
            }.prefix(5)
            if rows.isEmpty {
                Text("没有看到一半的视频").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(rows), id: \.key) { entry in
                        NavigationLink {
                            MediaHubView()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(entry.title).font(.callout).lineLimit(1)
                                    Spacer()
                                    if let percent = entry.videoPercent {
                                        Text("\(String(percent))%").font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(entry.source).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                if let percent = entry.videoPercent {
                                    ProgressView(value: Double(percent) / 100)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Episodes with a date, which is the only way this screen can say "upcoming"
    /// without inventing one.
    private var upcomingBlock: some View {
        Group {
            let rows = metadata.upcoming()
            if rows.isEmpty {
                Text(metadata.hasKey
                     ? "还没有对上的剧集:打开一次媒体库,会用剧名去 TMDB 对一次。"
                     : "在「设置 → 元数据」填 TMDB key,这里才会显示播出日期。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows.prefix(4), id: \.info.key) { row in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.info.name).font(.callout).lineLimit(1)
                                if let episode = row.info.nextEpisode {
                                    Text("S\(String(episode.season))E\(String(episode.number)) · \(episode.name)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(row.airs.formatted(.dateTime.month().day()))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Comics on this device, which work with no network at all.
    private var localComicsBlock: some View {
        Group {
            if local.comics.isEmpty {
                NavigationLink { LocalComicsView() } label: {
                    Text("导入一个图片文件夹或 .cbz").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(local.comics.prefix(8)) { comic in
                            NavigationLink { LocalComicReaderView(comic: comic) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Color.secondary.opacity(0.15)
                                        .frame(width: 96, height: 132)
                                        .overlay(Image(systemName: "folder").foregroundStyle(.secondary))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(comic.title).font(.caption).lineLimit(1)
                                    Text("\(comic.pageCount) 页").font(.caption2).foregroundStyle(.secondary)
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
