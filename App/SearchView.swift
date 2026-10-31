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
                    VStack(spacing: 0) {
                        filters
                        results
                    }
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
            .onAppear {
                if !sources.contains(where: { $0.key == sourceKey }) { sourceKey = sources.first?.key ?? "" }
                prepare()
            }
            .onChange(of: sourceKey) {
                prepare()
                if !query.isEmpty { start() }
            }
            .task(id: sourceKey) { prepare() }
        }
    }

    /// The source's own search filters, one choice per group. A merged search
    /// shows none: the groups belong to one source, and choosing for every
    /// source at once would be a different feature.
    @ViewBuilder private var filters: some View {
        if scope == .current, !model.groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.groups.enumerated()), id: \.offset) { index, group in
                        Menu {
                            ForEach(Array(group.values.enumerated()), id: \.offset) { slot, value in
                                Button {
                                    model.choose(value, group: index)
                                    // Re-run so the choice reaches search.load;
                                    // an empty screen would look like a filter
                                    // that did nothing.
                                    if model.searched { start() }
                                } label: {
                                    Text(model.choice(at: index) == value
                                         ? "✓ " + groupLabel(group, slot)
                                         : groupLabel(group, slot))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(group.label)
                                    .foregroundStyle(.secondary)
                                Text(model.choiceLabel(at: index))
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().stroke(.quaternary))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
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

    /// Reads the source's filter groups without searching, so the row can be
    /// shown before the first keyword.
    private func prepare() {
        let key = sourceKey
        guard !key.isEmpty else { return }
        Task { await model.prepare(library.core, source: key) }
    }

    private func start() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let keys = scope == .current ? [sourceKey].filter { !$0.isEmpty } : sources.map(\.key)
        guard !keys.isEmpty else { return }
        searches.add(q)
        let chosen = scope
        let only = keys.first ?? ""
        Task {
            if chosen == .current { await model.prepare(library.core, source: only) }
            await model.search(library.core, sources: keys, keyword: q, scope: chosen)
        }
    }
}

/// The label of one value. A source may send fewer labels than values, so the
/// value itself is the fallback rather than an empty menu entry.
private func groupLabel(_ group: SearchOptionGroup, _ index: Int) -> String {
    group.labels.indices.contains(index) ? group.labels[index] : (group.values.indices.contains(index) ? group.values[index] : "")
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
    /// Which search is the current one. A request that started earlier must not
    /// write into the screen after a newer search took over: its results belong
    /// to a keyword the user has already replaced.
    private let generation = SearchGeneration()

    /// The current source's filter groups, and the value chosen for each. One
    /// value per group is what search.load takes; an empty choice leaves the
    /// source's own default in place.
    private(set) var groups: [SearchOptionGroup] = []
    private(set) var choices: [String] = []
    private(set) var optionSource = ""

    /// Reads the groups and starts from the source's defaults. Kept separate
    /// from search() so the filter row can appear before the first keyword.
    func prepare(_ core: CoreClient, source key: String) async {
        guard !key.isEmpty else { return }
        guard key != optionSource || groups.isEmpty else { return }
        optionSource = key
        groups = []
        choices = []
        guard let list = try? await core.searchOptions(key: key) else { return }
        guard optionSource == key else { return } // the user moved on meanwhile
        groups = list
        choices = list.map(\.defaultKey)
    }

    /// The chosen value of one group, or "" when it has none.
    func choice(at index: Int) -> String {
        choices.indices.contains(index) ? choices[index] : ""
    }

    /// What to draw on the chip: the chosen value's label, or the raw value.
    func choiceLabel(at index: Int) -> String {
        guard groups.indices.contains(index) else { return "" }
        let group = groups[index]
        let value = choice(at: index)
        if let slot = group.values.firstIndex(of: value) { return groupLabel(group, slot) }
        return value.isEmpty ? "默认" : value
    }

    func choose(_ value: String, group index: Int) {
        guard choices.indices.contains(index) else { return }
        choices[index] = value
    }

    /// One value per group, in the source's declared order. Falls back to the
    /// defaults for a source whose groups have not been read yet: search.load
    /// indexes into this array, so a short array would crash the source.
    private func optionValues(for key: String, groups list: [SearchOptionGroup]) -> [String] {
        if key == optionSource, choices.count == groups.count, !groups.isEmpty { return choices }
        return list.map(\.defaultKey)
    }

    /// Only one source can be paged; a merged search takes one page each.
    var canPage: Bool { scope == .current && !source.isEmpty }

    func search(_ core: CoreClient, sources: [String], keyword: String, scope: Scope) async {
        let current = generation.begin()
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
        defer {
            // Only the current search may clear the spinner: an older one
            // finishing late must not hide the newer search's progress.
            if generation.isCurrent(current) { loading = false }
        }

        if scope == .current {
            guard let only = sources.first else { searched = true; return }
            await loadPage(core, source: only, generation: current)
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

        // A newer search started while these sources were answering: their
        // results are for a keyword the user has already replaced.
        guard generation.isCurrent(current) else { return }

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
        await loadPage(core, source: source, generation: generation.currentToken)
    }

    private func loadPage(_ core: CoreClient, source key: String, generation current: Int) async {
        loading = true
        defer {
            if generation.isCurrent(current) { loading = false }
        }
        let next = page + 1
        do {
            // One value per search group, in the source's order: what the
            // filter row has chosen, or the source's defaults.
            let declared = try await core.searchOptions(key: key)
            let options = optionValues(for: key, groups: declared)
            let result = try await core.search(key: key, keyword: keyword, page: next, options: options)
            // Another search started while this one was answering; its results
            // would belong to a keyword that is no longer on screen.
            guard generation.isCurrent(current) else { return }
            // Sources repeat items across pages; keep the first.
            let seen = Set(hits.map(\.id))
            hits += result.comics.map { Hit(source: key, comic: $0) }.filter { !seen.contains($0.id) }
            page = next
            maxPage = result.maxPage ?? (result.comics.isEmpty ? next : nil)
        } catch {
            guard generation.isCurrent(current) else { return }
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
