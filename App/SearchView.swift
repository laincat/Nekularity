import NekularityKit
import Observation
import SwiftUI

/// Search one source.
struct SearchView: View {
    @Environment(SourceLibrary.self) private var library
    @AppStorage("searchSource") private var sourceKey = ""
    @AppStorage("searchScope") private var scope: SearchModel.Scope = .current
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
                        Picker("范围", selection: $scope) {
                            ForEach(SearchModel.Scope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    if scope == .current {
                        ToolbarItem(placement: .primaryAction) {
                            Picker("漫画源", selection: $sourceKey) {
                                ForEach(sources) { Text($0.name).tag($0.key) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .onAppear { if !sources.contains(where: { $0.key == sourceKey }) { sourceKey = sources.first?.key ?? "" } }
            .onChange(of: sourceKey) { if !query.isEmpty { start() } }
        }
    }

    @ViewBuilder private var results: some View {
        if let error = model.error, model.hits.isEmpty {
            ContentUnavailableView {
                Label("搜索失败", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: { Button("重试") { start() } }
        } else if model.hits.isEmpty {
            if model.loading { ProgressView() }
            else if model.searched { ContentUnavailableView.search(text: model.keyword) }
            else if searches.queries.isEmpty {
                ContentUnavailableView("输入关键词开始搜索", systemImage: "magnifyingglass")
            } else {
                recent
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)], spacing: 16) {
                    ForEach(model.hits) { hit in
                        NavigationLink(value: ComicRoute(source: hit.source, comic: hit.comic)) {
                            ComicCard(source: hit.source, comic: hit.comic, showsSource: model.scope == .all)
                        }
                        .buttonStyle(.plain)
                        // Opening another source's comic moves the picker with
                        // it, so the detail screen and the reader agree.
                        .simultaneousGesture(TapGesture().onEnded { sourceKey = hit.source })
                        .onAppear {
                            if hit.id == model.hits.last?.id {
                                Task { await model.loadMore(library.core) }
                            }
                        }
                    }
                }
                .padding()
                if model.loading { ProgressView().padding() }
                if !model.failedSources.isEmpty {
                    Text("这些源没有返回:" + model.failedSources.map { key in
                        library.sources.first { $0.key == key }?.name ?? key
                    }.joined(separator: "、"))
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary).padding() }
            }
        }
    }

    /// What was searched before, newest first; tapping one searches it again.
    private var recent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最近搜索").font(.headline)
                    Spacer()
                    Button("清空") { searches.clear() }
                        .font(.footnote)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 220), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(searches.queries, id: \.self) { word in
                        Button {
                            query = word
                            start()
                        } label: {
                            Text(word).lineLimit(1).font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            Button("删除这条", role: .destructive) { searches.remove(word) }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func start() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let keys = scope == .current ? [sourceKey].filter { !$0.isEmpty } : sources.map(\.key)
        guard !keys.isEmpty else { return }
        searches.add(q)
        let chosen = scope
        Task { await model.search(library.core, sources: keys, keyword: q, scope: chosen) }
    }
}

struct ComicRoute: Hashable {
    let source: String
    let comic: Comic
    /// Set when the route comes from a kept page, so the detail screen can
    /// offer the chapter that page belongs to.
    var chapterID: String? = nil
}

/// Search results, either one source paged or every source's first page.
@MainActor @Observable
final class SearchModel {
    struct Hit: Identifiable, Hashable {
        let source: String
        let comic: Comic
        var id: String { source + "/" + comic.id }
    }

    /// Which sources a search covers.
    enum Scope: String, CaseIterable, Identifiable {
        case current
        case all
        var id: String { rawValue }
        var title: String { self == .current ? "当前源" : "全部源" }
    }

    var hits: [Hit] = []
    var loading = false
    var searched = false
    var error: String?
    private(set) var scope: Scope = .current
    private(set) var keyword = ""
    /// Sources that failed in a merged search, for the footer.
    private(set) var failedSources: [String] = []
    /// The source being paged; empty for a merged search.
    private(set) var source = ""
    private var page = 1
    private var maxPage: Int?

    /// Only one source can be paged; a merged search takes one page each.
    var canPage: Bool { scope == .current && !source.isEmpty }

    func search(_ core: CoreClient, sources: [String], keyword: String, scope: Scope) async {
        self.scope = scope
        self.keyword = keyword
        source = scope == .current ? (sources.first ?? "") : ""
        hits = []
        page = 0
        maxPage = nil
        error = nil
        searched = false
        failedSources = []
        loading = true
        defer { loading = false }

        if scope == .current {
            guard let only = sources.first else { searched = true; return }
            await loadPage(core, source: only)
            return
        }

        // Merged: each source's first page, at most three in flight, results
        // kept in the order the sources are installed.
        var collected: [(index: Int, hits: [Hit], failed: Bool)] = []
        var start = 0
        while start < sources.count {
            let slice = Array(sources.enumerated())[start..<min(start + 3, sources.count)]
            let part = await withTaskGroup(of: (Int, [Hit], Bool).self) { group in
                for (index, key) in slice {
                    group.addTask {
                        let key = key
                        do {
                            let options = try await core.searchOptions(key: key).map(\.defaultKey)
                            let result = try await core.search(key: key, keyword: keyword, page: 1, options: options)
                            return (index, result.comics.map { Hit(source: key, comic: $0) }, false)
                        } catch {
                            return (index, [], true)
                        }
                    }
                }
                var out: [(Int, [Hit], Bool)] = []
                for await item in group { out.append(item) }
                return out
            }
            collected += part.map { (index: $0.0, hits: $0.1, failed: $0.2) }
            start += 3
        }

        // A source that returned nothing is not a failure; one that threw is.
        for item in collected.sorted(by: { $0.index < $1.index }) {
            if item.failed {
                failedSources.append(sources[item.index])
            }
            hits += item.hits
        }
        if hits.isEmpty, !failedSources.isEmpty {
            error = "所有源都没有返回结果"
        }
        searched = true
    }

    /// Next page of the one source being read. Merged searches never page.
    func loadMore(_ core: CoreClient) async {
        guard canPage, !loading, maxPage.map({ page < $0 }) ?? true else { return }
        await loadPage(core, source: source)
    }

    private func loadPage(_ core: CoreClient, source key: String) async {
        loading = true
        defer { loading = false }
        let next = page + 1
        do {
            // One value per search group: the source's defaults until the
            // filter UI arrives, because search.load indexes into them.
            let options = try await core.searchOptions(key: key).map(\.defaultKey)
            let result = try await core.search(key: key, keyword: keyword, page: next, options: options)
            // Sources repeat items across pages; keep the first.
            let seen = Set(hits.map(\.id))
            hits += result.comics.map { Hit(source: key, comic: $0) }.filter { !seen.contains($0.id) }
            page = next
            maxPage = result.maxPage ?? (result.comics.isEmpty ? next : nil)
        } catch {
            if (error as? CoreError)?.isCancelled != true {
                self.error = error.localizedDescription
            }
            // Stop paging after a failure; a retry restarts the search.
            maxPage = page
        }
        searched = true
    }
}

struct ComicCard: View {
    let source: String
    let comic: Comic
    /// A merged search mixes sources, so each card says which one it came from.
    var showsSource = false

    @Environment(SourceLibrary.self) private var library

    private var sourceLabel: String {
        library.sources.first { $0.key == source }?.name ?? source
    }

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
            if showsSource {
                Text(sourceLabel).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
