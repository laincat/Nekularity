import NekularityKit
import Observation
import SwiftUI

/// Browse a source's own sections (its `explore` list) without searching.
///
/// The source decides what a browse looks like: one list with pages, several
/// titled parts, or a mix. All of them arrive as sections of comics, so this
/// screen shows sections and rows and lets the model do the rest.
struct BrowseView: View {
    @Environment(SourceLibrary.self) private var library
    @AppStorage("searchSource") private var sourceKey = ""
    @State private var model = BrowseModel()

    private var sources: [PluginRecord] { library.comicSources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView("没有可用的漫画源", systemImage: "puzzlepiece.extension",
                                           description: Text("先在“漫画源”里添加并启用一个源。"))
                } else {
                    content
                }
            }
            .navigationTitle("浏览")
            .navigationDestination(for: ComicRoute.self) { ComicDetailView(route: $0) }
            .toolbar {
                if !sources.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("漫画源", selection: $sourceKey) {
                            ForEach(sources) { Text($0.name).tag($0.key) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .onAppear {
                if !sources.contains(where: { $0.key == sourceKey }) { sourceKey = sources.first?.key ?? "" }
                Task { await model.open(library.core, source: sourceKey) }
            }
            .onChange(of: sourceKey) { Task { await model.open(library.core, source: sourceKey) } }
            .refreshable { await model.reload(library.core) }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if model.pages.count > 1 {
                browseTabs
                Divider()
            }
            browseBody(model)
        }
    }

    /// One chip per browse the source offers.
    private var browseTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.pages.enumerated()), id: \.offset) { i, page in
                    Button {
                        Task { await model.select(library.core, index: i) }
                    } label: {
                        Text(page.title.isEmpty ? "分类 \(i + 1)" : page.title)
                            .font(.callout)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(i == model.index ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                                        in: Capsule())
                            .foregroundStyle(i == model.index ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(i == model.index ? .isSelected : [])
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    @ViewBuilder private func browseBody(_ model: BrowseModel) -> some View {
        if model.loading && model.result == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.result == nil {
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("重试") { Task { await model.reload(library.core) } }
            }
        } else if model.pages.isEmpty {
            ContentUnavailableView("这个源没有分类浏览", systemImage: "square.grid.2x2")
        } else if let result = model.result, result.sections.isEmpty {
            ContentUnavailableView("这个分类没有内容", systemImage: "tray")
        } else if let result = model.result {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.comics) { comic in
                                NavigationLink(value: ComicRoute(source: model.source, comic: comic)) {
                                    BrowseRow(source: model.source, comic: comic)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 76)
                            }
                        } header: {
                            if !section.title.isEmpty {
                                Text(section.title)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal).padding(.vertical, 8)
                                    .background(.bar)
                            }
                        }
                    }
                    if result.maxPage > 0 { pager(result) }
                }
                .padding(.bottom, 24)
            }
        }
    }

    /// Pages, for a browse that pages instead of listing everything.
    private func pager(_ result: ExploreResult) -> some View {
        HStack {
            Text("第 \(model.page) / \(result.maxPage) 页").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("上一页") { Task { await model.loadPage(library.core, page: model.page - 1) } }
                .disabled(model.page <= 1 || model.loading)
            Button("下一页") { Task { await model.loadPage(library.core, page: model.page + 1) } }
                .disabled(model.page >= result.maxPage || model.loading)
        }
        .padding(.horizontal).padding(.vertical, 12)
    }
}

/// One comic in a browse list.
private struct BrowseRow: View {
    let source: String
    let comic: Comic

    var body: some View {
        HStack(spacing: 12) {
            SourceImage(key: .init(source: source, url: comic.cover ?? "", isThumbnail: true), maxPixel: 180)
                .frame(width: 56, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title).font(.subheadline).lineLimit(2)
                if let sub = comic.subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The browses of one source, and what the chosen one returned.
@MainActor @Observable
final class BrowseModel {
    private(set) var source = ""
    private(set) var pages: [ExplorePage] = []
    private(set) var index = 0
    private(set) var result: ExploreResult?
    private(set) var page = 1
    var loading = false
    var error: String?

    /// Bumped by each new source or browse, so a slow answer for an old one
    /// is dropped instead of showing under the new tab.
    private var generation = 0

    /// Opens a source: reads its browses, then the first one.
    func open(_ core: CoreClient, source: String) async {
        guard !source.isEmpty else {
            pages = []; result = nil; error = nil
            return
        }
        generation += 1
        let gen = generation
        self.source = source
        pages = []
        index = 0
        result = nil
        page = 1
        error = nil
        loading = true
        do {
            let pages = try await core.explorePages(key: source)
            guard gen == generation else { return }
            self.pages = pages
            loading = false
            guard !pages.isEmpty else { return }
            await load(core, index: 0, page: 1, generation: gen)
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
    }

    /// Chooses another browse of the same source.
    func select(_ core: CoreClient, index: Int) async {
        guard pages.indices.contains(index), index != self.index || result == nil else { return }
        generation += 1
        await load(core, index: index, page: 1, generation: generation)
    }

    /// Moves to another page of a paging browse.
    func loadPage(_ core: CoreClient, page: Int) async {
        guard let result, result.maxPage > 0, (1...result.maxPage).contains(page), page != self.page else { return }
        generation += 1
        await load(core, index: index, page: page, generation: generation)
    }

    /// Reads the chosen browse again, as pull-to-refresh asks.
    func reload(_ core: CoreClient) async {
        guard !source.isEmpty, !pages.isEmpty else { return }
        generation += 1
        await load(core, index: index, page: page, generation: generation)
    }

    private func load(_ core: CoreClient, index: Int, page: Int, generation gen: Int) async {
        loading = true
        error = nil
        self.index = index
        do {
            let result = try await core.explore(key: source, index: index, page: page)
            guard gen == generation else { return }
            self.result = result
            self.page = page
            loading = false
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            self.result = nil
        }
    }
}
