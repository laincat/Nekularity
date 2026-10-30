import NekularityKit
import Observation
import SwiftUI

/// Search one source.
struct SearchView: View {
    @Environment(SourceLibrary.self) private var library
    @AppStorage("searchSource") private var sourceKey = ""
    @State private var query = ""
    @Environment(SearchHistoryStore.self) private var searches
    @State private var model = SearchModel()

    private var sources: [PluginRecord] { library.comicSources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView("没有可用的漫画源", systemImage: "puzzlepiece.extension",
                                           description: Text("先在“漫画源”里添加并启用一个源。"))
                } else {
                    results
                }
            }
            .navigationTitle("搜索")
            .navigationDestination(for: ComicRoute.self) { ComicDetailView(route: $0) }
            .searchable(text: $query, prompt: "关键词")
            .onSubmit(of: .search) { start() }
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
            .onAppear { if !sources.contains(where: { $0.key == sourceKey }) { sourceKey = sources.first?.key ?? "" } }
            .onChange(of: sourceKey) { if !query.isEmpty { start() } }
        }
    }

    @ViewBuilder private var results: some View {
        if let error = model.error, model.comics.isEmpty {
            ContentUnavailableView {
                Label("搜索失败", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: { Button("重试") { start() } }
        } else if model.comics.isEmpty {
            if model.loading { ProgressView() }
            else if model.searched { ContentUnavailableView.search(text: model.keyword) }
            else { ContentUnavailableView("输入关键词开始搜索", systemImage: "magnifyingglass") }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)], spacing: 16) {
                    ForEach(model.comics) { comic in
                        NavigationLink(value: ComicRoute(source: model.source, comic: comic)) {
                            ComicCard(source: model.source, comic: comic)
                        }
                        .buttonStyle(.plain)
                        .onAppear { if comic.id == model.comics.last?.id { Task { await model.loadMore(library.core) } } }
                    }
                }
                .padding()
                if model.loading { ProgressView().padding() }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary).padding() }
            }
        }
    }

    private func start() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !sourceKey.isEmpty else { return }
        searches.add(q)
        Task { await model.search(library.core, source: sourceKey, keyword: q) }
    }
}

struct ComicRoute: Hashable {
    let source: String
    let comic: Comic
}

/// Paged search results of one source.
@MainActor @Observable
final class SearchModel {
    var comics: [Comic] = []
    var loading = false
    var searched = false
    var error: String?
    private(set) var source = ""
    private(set) var keyword = ""
    private var page = 1
    private var maxPage: Int?
    /// Bumped by each new search so late pages of an old one are dropped.
    private var generation = 0

    func search(_ core: CoreClient, source: String, keyword: String) async {
        generation += 1
        loading = false
        self.source = source; self.keyword = keyword
        comics = []; page = 0; maxPage = nil; error = nil; searched = false
        await loadMore(core)
    }

    func loadMore(_ core: CoreClient) async {
        guard !loading, maxPage.map({ page < $0 }) ?? true, !(searched && comics.isEmpty) else { return }
        let gen = generation
        loading = true
        defer { if gen == generation { loading = false } }
        let next = page + 1
        do {
            // One value per search group: the source's defaults until there
            // is a filter UI, because search.load indexes into them.
            let options = try await core.searchOptions(key: source).map(\.defaultKey)
            let result = try await core.search(key: source, keyword: keyword, page: next, options: options)
            guard gen == generation else { return }
            // Sources repeat items across pages; keep the first.
            let seen = Set(comics.map(\.id))
            comics += result.comics.filter { !seen.contains($0.id) }
            page = next
            maxPage = result.maxPage ?? (result.comics.isEmpty ? next : nil)
            searched = true
        } catch {
            guard gen == generation else { return }
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            searched = true
            maxPage = page // stop paging after a failure; retry restarts
        }
    }
}

struct ComicCard: View {
    let source: String
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.15)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    if let cover = comic.cover, !cover.isEmpty {
                        SourceImage(key: .init(source: source, url: cover, isThumbnail: true), maxPixel: 400)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(comic.title).font(.subheadline).lineLimit(2)
            if let sub = comic.subtitle, !sub.isEmpty {
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
