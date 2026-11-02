import SwiftUI
import NekularityKit

struct ComicDetailView: View {
    let route: ComicRoute
    @Environment(SourceLibrary.self) private var library
    @Environment(ShelfStore.self) private var shelf
    @Environment(TagGlossaryStore.self) private var glossary
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.imageLoader) private var images
    @State private var details: ComicDetails?
    @State private var error: String?
    /// The source's own favorites: whether it keeps them, its folders, and
    /// whether this comic is in one. A separate list from the local shelf.
    @State private var sourceFavorites = SourceFavoriteState()
    /// What the source declares about comments, read once with the details.
    @State private var commentSupport: CommentSupport?
    @State private var showingComments = false
    /// Whether the source answers `onClickTag`; read once with the details.
    @State private var tagSupport = false
    @State private var tagSearch: TagSearchRequest?
    @State private var tagCategory: TagCategoryRequest?
    @State private var tagNotice: String?
    @State private var downloadNote: String?

    /// Both notices go through one alert; see the note at the modifier.
    private var note: String? { tagNotice ?? downloadNote }
    private func clearNote() { tagNotice = nil; downloadNote = nil }

    var body: some View {
        Group {
            if let details {
                content(details)
            } else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("重试") { Task { await load() } } }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(route.comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tagSearch) { request in
            SourceSearchSheet(source: route.source, keyword: request.keyword)
        }
        .sheet(item: $tagCategory) { request in
            NavigationStack {
                CategoryBrowser(source: route.source, initialParam: request.param)
                    .navigationTitle(route.source)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingComments) {
            ComicCommentsView(source: route.source, comicID: route.comic.id, subID: details?.subId ?? "")
        }
        .task { if details == nil { await load() } }
        .toolbar {
            if let details {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await downloadAll(details) }
                        } label: {
                            Label("下载全部章节", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .accessibilityIdentifier("detail.download")
                }
            }
        }
        // One alert: SwiftUI keeps a single one per view, and this screen used to
        // carry two, so whichever came second silently never appeared. The two
        // notices share the slot; the first non-nil wins.
        .alert(note ?? "", isPresented: Binding(
            get: { note != nil },
            set: { if !$0 { clearNote() } }
        )) {
            Button("好") { clearNote() }
        }
    }

    private func load() async {
        error = nil
        do {
            details = try await library.core.details(key: route.source, comicID: route.comic.id)
        } catch {
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
        await sourceFavorites.load(library.core, source: route.source, comicID: route.comic.id)
        commentSupport = try? await library.core.commentSupport(key: route.source)
        tagSupport = await library.core.hasComic(key: route.source, path: "comic.onClickTag")
    }

    /// Asks the source what its tag means and does that.
    ///
    /// The meaning belongs to the source: one says "search 作者:<name>", another
    /// names a category parameter. A source that throws has its own words shown,
    /// because that is the only honest answer to "why did nothing happen".
    private func tapTag(_ namespace: String, _ tag: String) async {
        tagNotice = nil
        do {
            let action = try await library.core.clickTag(key: route.source, namespace: namespace, tag: tag)
            switch action.action {
            case "search":
                guard !action.keyword.isEmpty else {
                    tagNotice = "这个源没有给出「\(tag)」的搜索词"
                    return
                }
                tagSearch = TagSearchRequest(keyword: action.keyword)
            case "category":
                tagCategory = TagCategoryRequest(param: action.param)
            default:
                tagNotice = "这个源没有说明「\(tag)」该做什么"
            }
        } catch {
            tagNotice = error.localizedDescription
        }
    }

    /// The source's own favorites, drawn only when the source keeps them.
    @ViewBuilder private var sourceFavoriteRow: some View {
        if sourceFavorites.support.supported {
            VStack(alignment: .leading, spacing: 6) {
                if sourceFavorites.support.folders, sourceFavorites.folders.count > 1 {
                    Picker("收藏夹", selection: Binding(
                        get: { sourceFavorites.folder ?? "" },
                        set: { value in Task { await sourceFavorites.choose(value) } })) {
                            ForEach(sourceFavorites.folderList, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                }
                Button(sourceFavorites.isHeld ? "已在源收藏" : "收藏到源") {
                    let handle = details?.favoriteId ?? route.comic.favoriteId
                    Task { await sourceFavorites.toggle(library.core, source: route.source,
                                                        comicID: route.comic.id, favoriteID: handle) }
                }
                .disabled(sourceFavorites.busy)
                if let message = sourceFavorites.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A way into the thread, only when the source keeps one. Asking Core once
    /// per comic keeps a source call out of the view body.
    @ViewBuilder private var commentRow: some View {
        if let support = commentSupport, support.load {
            Button {
                showingComments = true
            } label: {
                Label("评论", systemImage: "text.bubble")
            }
            .accessibilityIdentifier("detail.comments")
        }
    }

    /// The source's own score, drawn as five stars with the number beside them.
    ///
    /// The number is what the source said; the stars are only a reading of it, so
    /// they are rounded for display and never replace the value.
    private func ratingRow(stars: Double, likes: Int?, liked: Bool?) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: Double(index) + 0.5 <= stars ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Text(String(format: "%.1f", stars)).font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let likes, likes > 0 {
                Text("· \(likes) 人喜欢").font(.caption2).foregroundStyle(.secondary)
            }
            if liked == true {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
            }
        }
        .accessibilityIdentifier("detail.rating")
        .accessibilityValue(String(format: "%.1f", stars))
    }

    private func content(_ d: ComicDetails) -> some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    if let cover = d.cover ?? route.comic.cover, !cover.isEmpty {
                        SourceImage(key: .init(source: route.source, url: cover, isThumbnail: true), maxPixel: 400)
                            .frame(width: 110, height: 152).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.title.isEmpty ? route.comic.title : d.title).font(.title3.bold()).textSelection(.enabled)
                        if let sub = d.subtitle, !sub.isEmpty { Text(sub).foregroundStyle(.secondary) }
                        // The source rates it or it does not; a row of empty stars
                        // would be a claim that it was rated zero.
                        if let stars = d.stars {
                            ratingRow(stars: stars, likes: d.likesCount, liked: d.isLiked)
                        } else if let likes = d.likesCount, likes > 0 {
                            Text("\(likes) 人喜欢").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                if let desc = d.description, !desc.isEmpty {
                    Text(desc).font(.callout).textSelection(.enabled)
                }
                commentRow
                sourceFavoriteRow
                ForEach(Array(d.tags.enumerated()), id: \.offset) { _, tag in
                    // A plain row, not `LabeledContent`: that container gives its
                    // content a hit area that does not take a press, which is how a
                    // callback button in the settings screen ended up visible but
                    // unpressable. A tag has to be tappable — that is the whole point
                    // of a source declaring what the tap means.
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(tag.group).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        // A tag is a way out of the comic when the source says
                        // what tapping it means; a source with no opinion leaves
                        // it as text rather than pretending otherwise.
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(Array(tag.values.enumerated()), id: \.offset) { _, value in
                                let label = glossary.label(for: value)
                                if tagSupport {
                                    // .link is macOS-only; a plain button with
                                    // the accent colour reads the same on iOS.
                                    // The source's own spelling is what a tag tap
                                    // sends: the translation is for this reader, and
                                    // the source has never heard of it.
                                    Button(label.text) { Task { await tapTag(tag.group, value) } }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.tint)
                                        .accessibilityValue(value)
                                } else {
                                    Text(label.text).multilineTextAlignment(.trailing)
                                        .accessibilityValue(value)
                                }
                            }
                        }
                    }
                    .font(.callout)
                }
            }

            if d.chapters.isEmpty {
                // Single-chapter comics have no chapter list; loadEp gets nil.
                Section {
                    NavigationLink("开始阅读") {
                        ReaderView(route: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                      comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                      author: route.comic.subtitle,
                                                      cover: route.comic.cover,
                                                      chapters: [], index: 0))
                    }
                }
            } else {
                // A kept page remembers its chapter; offer that chapter first.
                if let wanted = route.chapterID,
                   let index = d.chapters.firstIndex(where: { $0.id == wanted }) {
                    Section {
                        NavigationLink {
                            ReaderView(route: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                          comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                          author: route.comic.subtitle,
                                                          cover: route.comic.cover,
                                                          chapters: d.chapters, index: index))
                        } label: {
                            Label("打开收藏页所在的那一话 · \(d.chapters[index].title)", systemImage: "bookmark")
                        }
                    }
                }
                if let resume = shelf.entry(source: route.source, id: route.comic.id) {
                    Section {
                        NavigationLink {
                            ReaderView(route: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                          comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                          author: route.comic.subtitle,
                                                          cover: route.comic.cover,
                                                          chapters: d.chapters,
                                                          index: min(max(0, resume.chapterIndex), d.chapters.count - 1)))
                        } label: {
                            Label("继续阅读 · \(resumePosition(resume))", systemImage: "book.pages")
                        }
                    }
                }
                ForEach(groups(d.chapters), id: \.name) { group in
                    Section(group.name ?? "章节") {
                        ForEach(group.items, id: \.offset) { i, chapter in
                            NavigationLink {
                                ReaderView(route: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                              comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                              author: route.comic.subtitle,
                                                              cover: route.comic.cover,
                                                              chapters: d.chapters, index: i))
                            } label: {
                                chapterRow(chapter, index: i)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Keeps one chapter, using the page list the reader would have loaded.
    private func download(_ chapter: ComicDetails.Chapter) async {
        guard let images, let comicInfo = details else { return }
        do {
            let pages = try await library.core.chapterImages(key: route.source, comicID: route.comic.id,
                                                             chapterID: chapter.id)
            guard !pages.isEmpty else { downloadNote = "这一章没有图片"; return }
            downloads.download(.init(sourceKey: route.source, comicID: route.comic.id,
                                     comicTitle: comicInfo.title, chapterID: chapter.id,
                                     chapterTitle: chapter.title, pages: pages), loader: images)
            downloadNote = "已加入下载"
        } catch {
            downloadNote = CoreError.readable(error.localizedDescription)
        }
    }

    private func downloadAll(_ comic: ComicDetails) async {
        for chapter in comic.chapters {
            await download(chapter)
        }
    }

    private func chapterRow(_ chapter: ComicDetails.Chapter, index: Int) -> some View {
        let here = shelf.entry(source: route.source, id: route.comic.id)?.chapterIndex == index
        return HStack {
            Text(chapter.title)
            Spacer()
            if here {
                Text("读到").font(.caption).foregroundStyle(.secondary)
            }
            if downloads.isDownloaded(sourceKey: route.source, comicID: route.comic.id, chapterID: chapter.id) {
                Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button {
                Task { await download(chapter) }
            } label: {
                Label("下载这一话", systemImage: "arrow.down.circle")
            }
        }
    }

    /// What the shelf remembers about where reading stopped, in one line.
    private func resumePosition(_ entry: ShelfHistory) -> String {
        var parts: [String] = []
        if let page = entry.page, page > 0 { parts.append("第 \(page) 页") }
        if let percent = entry.percent, percent > 0 { parts.append("\(percent)%") }
        if parts.isEmpty, let chapter = entry.chapter, !chapter.isEmpty { parts.append(chapter) }
        return parts.isEmpty ? "上次的位置" : parts.joined(separator: " · ")
    }

    /// Chapters by group, keeping the global index each reader route uses.
    private func groups(_ chapters: [ComicDetails.Chapter]) -> [(name: String?, items: [(offset: Int, element: ComicDetails.Chapter)])] {
        var out: [(name: String?, items: [(offset: Int, element: ComicDetails.Chapter)])] = []
        for (i, c) in chapters.enumerated() {
            if out.last?.name == c.group, !out.isEmpty { out[out.count - 1].items.append((i, c)) }
            else { out.append((c.group, [(i, c)])) }
        }
        return out
    }
}

struct ReaderRoute: Hashable {
    let source: String
    let comicID: String
    /// The comic's own title, author and cover, so the shelf can record a
    /// reading position without asking the source again.
    var comicTitle: String = ""
    var author: String? = nil
    var cover: String? = nil
    /// Empty for a single-chapter comic.
    let chapters: [ComicDetails.Chapter]
    var index: Int

    var chapterID: String? { chapters.indices.contains(index) ? chapters[index].id : nil }
    var title: String { chapters.indices.contains(index) ? chapters[index].title : "阅读" }
}

/// The source's own favorites for the comic on screen: whether it keeps them,
/// which folders it has, and whether this comic is already in one.
///
/// A separate list from the local shelf, so it gets its own control rather than
/// sharing the shelf's bookmark.
@MainActor @Observable
final class SourceFavoriteState {
    private(set) var support = FavoritesSupport(supported: false, multiFolder: false, folders: false, canLoad: false)
    private(set) var folders: [String: String] = [:]
    private(set) var folder: String?
    private(set) var held: [String] = []
    private(set) var busy = false
    private(set) var message: String?

    var isHeld: Bool { !held.isEmpty }
    var folderList: [(id: String, name: String)] {
        folders.keys.sorted().map { ($0, folders[$0] ?? $0) }
    }

    /// Reads what the source offers for this comic. A source that keeps no
    /// favorites stays silent, and no control appears.
    func load(_ core: CoreClient, source: String, comicID: String) async {
        support = await core.favoritesSupport(key: source)
        guard support.supported else { return }
        guard support.folders else { return }
        // A source that needs a session refuses here, and its own words are the
        // reason worth showing.
        if let (folders, favorited) = try? await core.favoriteFolders(key: source, comicID: comicID) {
            self.folders = folders
            held = favorited
            folder = favorited.first ?? folderList.first?.id
        }
    }

    func choose(_ value: String) async {
        folder = value.isEmpty ? nil : value
    }

    /// Adds the comic to the chosen folder, or removes it when the source
    /// already reports it there.
    func toggle(_ core: CoreClient, source: String, comicID: String, favoriteID: String?) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        let adding = held.isEmpty
        do {
            // A single-folder source takes no folder id at all.
            let target = support.multiFolder ? folder : nil
            try await core.setFavorite(key: source, comicID: comicID, folder: target,
                                       favoriteID: favoriteID, adding: adding)
            if adding {
                held = [target ?? ""]
                message = "已加入源收藏"
            } else {
                held = []
                message = "已从源收藏移除"
            }
        } catch {
            // The source's own words: "Login expired", or whatever it chose.
            message = error.localizedDescription
        }
    }
}

/// One tap on a tag, resolved by the source into something to open.
struct TagSearchRequest: Identifiable, Hashable {
    let id = UUID()
    let keyword: String
}

/// One tap on a tag the source mapped to a category parameter.
struct TagCategoryRequest: Identifiable, Hashable {
    let id = UUID()
    let param: String
}
