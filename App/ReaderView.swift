import NekularityKit
import SwiftUI

/// Vertical scrolling reader for one chapter, with previous/next chapter.
struct ReaderView: View {
    @State var route: ReaderRoute
    @Environment(SourceLibrary.self) private var library
    @Environment(ShelfStore.self) private var shelf
    @State private var images: [String] = []
    @State private var error: String?
    @State private var loading = true
    @State private var chromeHidden = false
    @State private var lastPage = 0
    /// Result of the last "收藏本页", shown briefly in the toolbar.
    @State private var keptNote: String?
    @AppStorage("readerLayout") private var layout: ReaderLayout = .vertical
    @AppStorage("readerRightToLeft") private var rightToLeft = false
    /// Whether reaching the end of a chapter opens the next one. Off by
    /// default: a reader that jumps on its own is a surprise.
    @AppStorage("readerAutoNext") private var autoNext = false
    /// Which page a paged reader shows, by its number in the chapter.
    @State private var pagedNumber = 1
    /// The page to return to once the chapter's images arrive.
    @State private var restorePage: Int?

    init(route: ReaderRoute) { _route = State(initialValue: route) }

    var body: some View {
        GeometryReader { geo in
            if layout == .paged {
                paged(geo)
            } else {
                vertical(geo)
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("重试") { Task { await load() } } }
            }
        }
        .background(Color.black.opacity(0.03))
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    keepPage()
                } label: {
                    Label(keptNote ?? "收藏本页", systemImage: "bookmark")
                }
                .disabled(images.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排版", selection: $layout) {
                        ForEach(ReaderLayout.allCases) { Text($0.title).tag($0) }
                    }
                    if layout == .paged {
                        Picker("方向", selection: $rightToLeft) {
                            Text("左→右").tag(false)
                            Text("右→左").tag(true)
                        }
                    }
                    Toggle("自动接续", isOn: $autoNext)
                } label: {
                    Label("排版", systemImage: "rectangle.split.3x1")
                }
            }
        }
        .statusBarHidden(chromeHidden)
        .onTapGesture { withAnimation { chromeHidden.toggle() } }
        .task(id: route.index) { await load() }
    }

    /// One page under the last: the long strip the app started with.
    @ViewBuilder
    private func vertical(_ geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                            ReaderPage(key: .init(source: route.source, url: url, comicID: route.comicID,
                                                  chapterID: route.chapterID, isThumbnail: false),
                                       width: geo.size.width, number: i + 1)
                                .id(i)
                                .background(GeometryReader { page in
                                    Color.clear.preference(
                                        key: PageOffsetKey.self,
                                        value: [i: page.frame(in: .named("reader")).minY])
                                })
                        }
                        if !images.isEmpty {
                            chapterFooter
                            // Reaching this marker means the chapter's end has
                            // been scrolled to; the next chapter is the only
                            // thing left to show.
                            if autoNext {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear(perform: nextChapterIfPossible)
                            }
                        }
                    }
                }
                .onChange(of: route.index) { proxy.scrollTo("top") }
                // Coming back to a chapter the shelf knows resumes where it
                // stopped, once, so the reader does not lose the place.
                .onChange(of: images.count) {
                    guard let page = restorePage, images.indices.contains(page - 1) else { return }
                    proxy.scrollTo(page - 1, anchor: .top)
                    restorePage = nil
                }
                .coordinateSpace(name: "reader")
                .onPreferenceChange(PageOffsetKey.self) { offsets in
                    // The callback may run off the main actor; the shelf is not
                    // safe to touch there.
                    Task { @MainActor in recordProgress(offsets) }
                }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// One page at a time, swipe to turn. Right-to-left reverses the order so
    /// a swipe from the right edge goes forward, as printed manga reads.
    @ViewBuilder
    private func paged(_ geo: GeometryProxy) -> some View {
        let order = rightToLeft ? Array(images.indices.reversed()) : Array(images.indices)
        TabView(selection: $pagedNumber) {
            ForEach(order, id: \.self) { i in
                VStack(spacing: 0) {
                    ReaderPage(key: .init(source: route.source, url: images[i], comicID: route.comicID,
                                          chapterID: route.chapterID, isThumbnail: false),
                               width: geo.size.width, number: i + 1)
                        .frame(maxHeight: .infinity, alignment: .center)
                    chapterFooter
                }
                .tag(i + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: pagedNumber) { old, new in
            guard new != old else { return }
            recordPage(new)
        }
        .onChange(of: route.index) { pagedNumber = 1 }
        .onChange(of: images.count) {
            guard !images.isEmpty else { return }
            if let page = restorePage, images.indices.contains(page - 1) {
                pagedNumber = page
                restorePage = nil
            }
            recordPage(pagedNumber)
        }
    }

    private var chapterFooter: some View {
        HStack {
            if route.index > 0 {
                Button { route.index -= 1 } label: { Label("上一章", systemImage: "chevron.left") }
            }
            Spacer()
            if route.index + 1 < route.chapters.count {
                Button { route.index += 1 } label: { Label("下一章", systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("已是最后一章").foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    /// Opens the next chapter once the reader has scrolled to the end of this
    /// one. A chapter with a single page is not a scroll, so it stays put.
    private func nextChapterIfPossible() {
        guard autoNext, images.count > 1, lastPage > 1, route.index + 1 < route.chapters.count else { return }
        route.index += 1
    }

    /// Writes a page number to the shelf, for the paged reader.
    private func recordPage(_ number: Int) {
        guard !images.isEmpty else { return }
        lastPage = min(max(1, number), images.count)
        let percent = min(100, max(0, Int((Double(lastPage) / Double(images.count) * 100).rounded())))
        let comic = ShelfComic(source: route.source, id: route.comicID,
                               title: route.comicTitle.isEmpty ? route.title : route.comicTitle,
                               author: route.author, cover: route.cover)
        if !shelf.updateProgress(source: route.source, id: route.comicID,
                                 chapter: route.title, chapterIndex: route.index,
                                 page: lastPage, percent: percent) {
            shelf.record(ShelfHistory(comic: comic, chapter: route.title,
                                     chapterIndex: route.index, page: lastPage, percent: percent))
        }
    }

    /// The page at the top of the screen is the page the shelf remembers.
    private func recordProgress(_ offsets: [Int: CGFloat]) {
        guard !images.isEmpty, !offsets.isEmpty else { return }
        let top = offsets.filter { $0.value <= 1 }.max { $0.value < $1.value }?.key
            ?? offsets.min { $0.value < $1.value }?.key ?? 0
        let page = top + 1
        guard page != lastPage else { return }
        lastPage = page
        let percent = min(100, max(0, Int((Double(page) / Double(images.count) * 100).rounded())))
        let comic = ShelfComic(source: route.source, id: route.comicID,
                               title: route.comicTitle.isEmpty ? route.title : route.comicTitle,
                               author: route.author, cover: route.cover)
        // Scrolling is not opening a new chapter, so an existing entry is
        // moved along instead of being written again from scratch.
        if !shelf.updateProgress(source: route.source, id: route.comicID,
                                 chapter: route.title, chapterIndex: route.index,
                                 page: page, percent: percent) {
            shelf.record(ShelfHistory(comic: comic, chapter: route.title,
                                     chapterIndex: route.index, page: page, percent: percent))
        }
    }

    /// Keeps the page at the top of the screen, the one the reader is on.
    private func keepPage() {
        let number = max(1, lastPage)
        guard images.indices.contains(number - 1) else { return }
        // A single-chapter comic has no chapter id; the shelf stores "" for
        // it, the same way an empty chapter name is stored.
        let page = KeptPage(source: route.source, comicID: route.comicID,
                            comicTitle: route.comicTitle.isEmpty ? route.title : route.comicTitle,
                            chapterID: route.chapterID ?? "", chapterIndex: route.index,
                            chapterName: route.title, page: number, url: images[number - 1])
        let added = shelf.keepPage(page)
        keptNote = added ? "已收藏" : "已经收藏过"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            keptNote = nil
        }
    }

    private func load() async {
        loading = true
        error = nil
        images = []
        lastPage = 0
        defer { loading = false }
        do {
            // Reopening the chapter the shelf remembers returns to its page.
            // The page is decided before the images land, so the first update
            // that sees them can scroll straight there.
            // The page count is not known yet; the first update that sees the
            // images checks the page against them.
            let wanted = shelf.resumePage(source: route.source, id: route.comicID,
                                          chapterIndex: route.index, pageCount: Int.max)
            images = try await library.core.chapterImages(key: route.source, comicID: route.comicID, chapterID: route.chapterID)
            restorePage = wanted
            if images.isEmpty { error = "这一章没有图片" }
            // Opening a chapter is what the shelf remembers.
            shelf.record(ShelfHistory(
                comic: ShelfComic(source: route.source, id: route.comicID,
                                  title: route.comicTitle.isEmpty ? route.title : route.comicTitle,
                                  author: route.author, cover: route.cover),
                chapter: route.title, chapterIndex: route.index))
        } catch {
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
    }
}

/// How the reader lays a chapter out.
enum ReaderLayout: String, CaseIterable, Identifiable {
    /// One page under the last, scrolled vertically.
    case vertical
    /// One page per screen, swiped sideways.
    case paged

    var id: String { rawValue }
    var title: String { self == .vertical ? "竖向滚动" : "单页翻页" }
}

/// How far each page sits from the top of the reader.
private struct PageOffsetKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/// One page. Until it loads it reserves a portrait-sized slot, so the
/// scroll position does not jump.
private struct ReaderPage: View {
    let key: ImageLoader.Key
    let width: CGFloat
    let number: Int
    @Environment(\.imageLoader) private var loader
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .accessibilityLabel("第 \(number) 页")
            } else {
                ZStack {
                    if failed {
                        Button { attempt += 1 } label: {
                            Label("第 \(number) 页加载失败,点按重试", systemImage: "arrow.clockwise")
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: width, height: width * 1.4)
            }
        }
        .task(id: TaskKey(key: key, attempt: attempt)) {
            failed = false
            do {
                image = try await loader?.image(key, maxWidth: Int(width * scale)).image
            } catch { failed = !Task.isCancelled }
        }
    }

    struct TaskKey: Hashable { let key: ImageLoader.Key; let attempt: Int }
}
