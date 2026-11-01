import NekularityKit
import Observation
import SwiftUI

/// A source's category page: pick a value from each dimension, then read the
/// list it returns.
///
/// A `random` dimension is not loaded at all. Its declared meaning is "take
/// this many values and search for them", which is what `nhentai`'s Tags
/// dimension does, so that dimension gets a button instead of a list.
struct CategoryBrowser: View {
    let source: String
    @Environment(SourceLibrary.self) private var library
    @Environment(ThemeStore.self) private var themes
    /// A category parameter to open on, from a tapped tag.
    var initialParam: String = ""
    @State private var model = CategoryModel()

    var body: some View {
        Group {
            if model.loading && model.page == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error, model.comics.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await model.reload(library.core) } }
                }
            } else if model.page == nil || model.page?.parts.isEmpty == true {
                ContentUnavailableView("这个源没有分类", systemImage: "square.grid.2x2")
            } else if let page = model.page {
                VStack(spacing: 0) {
                    dimensions(page)
                    Divider()
                    list
                }
            }
        }
        .task(id: source) { await model.open(library.core, source: source, param: initialParam) }
    }

    /// One row per dimension: the value it currently has selected, and for a
    /// random dimension the button that searches instead.
    private func dimensions(_ page: CategoryPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(page.parts.enumerated()), id: \.element.id) { i, part in
                HStack(alignment: .top, spacing: 8) {
                    Text(part.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    if part.isRandom || part.searchesInsteadOfLoading {
                        Button(model.randomLabel) {
                            Task { await model.searchRandom(library.core, part: part) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.loading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(part.categories, id: \.self) { value in
                                    chip(value, selected: model.values[i] == value) {
                                        Task { await model.select(library.core, part: i, value: value) }
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if let ranking = page.ranking, !ranking.options.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("排行").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ranking.options) { option in
                                chip(option.label, selected: model.rankOption == option.value) {
                                    Task { await model.selectRanking(library.core, option: option.value) }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if !model.options.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("选项").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(model.options.enumerated()), id: \.offset) { gi, group in
                                ForEach(group.values, id: \.self) { value in
                                    // A multi-select group takes several values; the
                                    // chip toggles rather than replaces.
                                    chip(model.optionLabel(group, value),
                                         selected: model.isOptionSelected(group, value, at: gi)) {
                                        Task { await model.pickOption(library.core, group: gi, value: value) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
                .foregroundStyle(selected ? themes.active.onAccent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var list: some View {
        if model.comics.isEmpty && !model.loading {
            ContentUnavailableView("这个分类没有内容", systemImage: "tray")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let note = model.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.top, 8)
                    }
                    ForEach(model.comics) { comic in
                        NavigationLink(value: ComicRoute(source: source, comic: comic)) {
                            BrowseRow(source: source, comic: comic)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 76)
                    }
                    if model.maxPage > 0 {
                        HStack {
                            Text("第 \(model.pageNumber) / \(model.maxPage) 页").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("上一页") { Task { await model.loadPage(library.core, page: model.pageNumber - 1) } }
                                .disabled(model.pageNumber <= 1 || model.loading)
                            Button("下一页") { Task { await model.loadPage(library.core, page: model.pageNumber + 1) } }
                                .disabled(model.pageNumber >= model.maxPage || model.loading)
                        }
                        .padding(.horizontal).padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await model.reload(library.core) }
        }
    }
}

/// The category page of one source, the values chosen so far, and the list
/// they produce.
@MainActor @Observable
final class CategoryModel {
    private(set) var source = ""
    private(set) var page: CategoryPage?
    /// One chosen value per dimension.
    private(set) var values: [String] = []
    /// One chosen value per option group.
    private(set) var optionValues: [String] = []
    private(set) var comics: [Comic] = []
    private(set) var pageNumber = 1
    private(set) var maxPage = 0
    /// Set when the list came from a random search rather than a dimension.
    private(set) var note: String?
    /// The ranking option whose list is showing; nil while a dimension is.
    private(set) var rankOption: String?
    var loading = false
    var error: String?

    /// Bumped by every new load, so a slow answer for an old choice is dropped.
    private var generation = 0

    /// A random dimension searches for one of its values; repeated taps pick
    /// again. The source's `randomNumber` is not used here: see searchRandom.
    let randomLabel = "随机一个标签"

    /// Values of the dimension currently chosen, for the interface to read.
    var options: [SearchOptionGroup] { page?.options ?? [] }

    /// Loads the declaration and, when the caller names a category parameter,
    /// opens on the value that carries it — a tapped tag lands where the source
    /// meant instead of on the first value.
    func open(_ core: CoreClient, source: String, param: String = "") async {
        generation += 1
        guard !source.isEmpty else {
            self.source = ""; page = nil; comics = []; values = []; optionValues = []
            activePart = nil; searchedKeyword = nil; note = nil; error = nil; loading = false
            return
        }
        let gen = generation
        self.source = source
        page = nil
        comics = []
        note = nil
        error = nil
        loading = true
        do {
            let page = try await core.categoryPage(key: source)
            guard gen == generation else { return }
            self.page = page
            self.values = (page?.parts ?? []).map { $0.categories.first ?? "" }
            self.optionValues = (page?.options ?? []).map(\.defaultSearchValue)
            loading = false
            guard let page, !page.parts.isEmpty else { return }
            if !param.isEmpty, let hit = Self.paramTarget(page, param) {
                self.values[hit.part] = page.parts[hit.part].categories[hit.value]
                await load(core, part: hit.part, page: 1, generation: gen)
                return
            }
            // The first dimension that can actually be loaded.
            if let first = page.parts.firstIndex(where: { !$0.isRandom && !$0.searchesInsteadOfLoading }) {
                await load(core, part: first, page: 1, generation: gen)
            }
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
    }

    /// The part and value whose parameter is param, using the same rule the
    /// loader applies: a per-value parameter if the source maps them, else the
    /// dimension's own parameter, else the value itself.
    nonisolated static func paramTarget(_ page: CategoryPage, _ param: String) -> (part: Int, value: Int)? {
        page.paramTarget(for: param)
    }

    /// Picks another value of a dimension and reads page one again.
    func select(_ core: CoreClient, part: Int, value: String) async {
        guard let page, page.parts.indices.contains(part) else { return }
        guard values.indices.contains(part), values[part] != value || activePart != part else { return }
        values[part] = value
        generation += 1
        await load(core, part: part, page: 1, generation: generation)
    }

    /// The source's label for a value, falling back to the value itself.
    func optionLabel(_ group: SearchOptionGroup, _ value: String) -> String {
        guard let index = group.values.firstIndex(of: value),
              group.labels.indices.contains(index) else { return value }
        return group.labels[index]
    }

    /// Whether a chip is on. A multi-select group holds a JSON array, so the
    /// value is one of several rather than the whole answer.
    func isOptionSelected(_ group: SearchOptionGroup, _ value: String, at index: Int) -> Bool {
        let current = optionValues[safe: index] ?? group.defaultSearchValue
        guard group.isMultiSelect else { return current == value }
        return Self.selections(current).contains(value)
    }

    /// A tap on a chip: a single-value group replaces, a multi-select group
    /// toggles one value and re-encodes the array the source expects.
    func pickOption(_ core: CoreClient, group index: Int, value: String) async {
        guard options.indices.contains(index) else { return }
        let group = options[index]
        guard group.isMultiSelect else {
            await setOption(core, group: index, value: value)
            return
        }
        let current = optionValues[safe: index] ?? group.defaultSearchValue
        var chosen = Self.selections(current)
        if let at = chosen.firstIndex(of: value) {
            chosen.remove(at: at)
        } else {
            chosen.append(value)
        }
        await setOption(core, group: index, value: SearchOptionGroup.encodeSelections(chosen))
    }

    /// The values inside a multi-select group's encoded array.
    static func selections(_ encoded: String) -> [String] {
        guard let data = encoded.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    /// One option changed: the list depends on it, so read it again.
    func setOption(_ core: CoreClient, group: Int, value: String) async {
        guard optionValues.indices.contains(group), optionValues[group] != value else { return }
        optionValues[group] = value
        guard let part = activePart else { return }
        generation += 1
        await load(core, part: part, page: 1, generation: generation)
    }

    func loadPage(_ core: CoreClient, page number: Int) async {
        guard maxPage > 0, (1...maxPage).contains(number), number != pageNumber else { return }
        guard let page, !page.parts.isEmpty else { return }
        // The random search keeps its own pages, and a dimension reload starts
        // from the dimension that produced the current list.
        if note != nil {
            guard let keyword = searchedKeyword else { return }
            generation += 1
            await search(core, keyword: keyword, page: number, generation: generation)
            return
        }
        if let option = rankOption {
            generation += 1
            await loadRanking(core, option: option, page: number, generation: generation)
            return
        }
        guard let part = activePart else { return }
        generation += 1
        await load(core, part: part, page: number, generation: generation)
    }

    func reload(_ core: CoreClient) async {
        guard let page, !page.parts.isEmpty else { return }
        generation += 1
        if let keyword = searchedKeyword {
            await search(core, keyword: keyword, page: pageNumber, generation: generation)
            return
        }
        if let option = rankOption {
            await loadRanking(core, option: option, page: pageNumber, generation: generation)
            return
        }
        guard let part = activePart else { return }
        await load(core, part: part, page: pageNumber, generation: generation)
    }

    /// Reads one page of the source's ranking page, which is a flat option
    /// list with its own loader rather than a dimension.
    func selectRanking(_ core: CoreClient, option: String) async {
        guard rankOption != option || comics.isEmpty else { return }
        generation += 1
        await loadRanking(core, option: option, page: 1, generation: generation)
    }

    private func loadRanking(_ core: CoreClient, option: String, page number: Int, generation gen: Int) async {
        loading = true
        error = nil
        note = nil
        searchedKeyword = nil
        activePart = nil
        rankOption = option
        do {
            let result = try await core.rankingComics(key: source, option: option, page: number)
            guard gen == generation else { return }
            comics = result.comics
            pageNumber = number
            maxPage = result.maxPage ?? 0
            loading = false
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            comics = []
        }
    }

    /// Searches for one value of a random dimension.
    ///
    /// `randomNumber` is not the number of values to join: the source's own
    /// note reads "the number of comics to display at the same time", and a
    /// comic search treats several tags as all-of-them. Joining twenty nhentai
    /// tags asks for works carrying all twenty — measured on the live site,
    /// eight tags still answered 20 comics, ten answered none, twenty were
    /// rejected. One value per tap is what the site accepts.
    func searchRandom(_ core: CoreClient, part: CategoryPart) async {
        let keyword = Self.randomKeyword(from: part.categories)
        guard !keyword.isEmpty else { return }
        generation += 1
        let gen = generation
        searchedKeyword = keyword
        note = "随机标签搜索：\(keyword)"
        await search(core, keyword: keyword, page: 1, generation: gen)
    }

    /// One value, picked at random, used as the keyword.
    static func randomKeyword(from values: [String]) -> String {
        values.randomElement() ?? ""
    }

    private(set) var searchedKeyword: String?

    /// The dimension whose value produced the current list; paging and
    /// refreshing stay on it.
    private(set) var activePart: Int?

    private func load(_ core: CoreClient, part: Int, page number: Int, generation gen: Int) async {
        guard let page, page.parts.indices.contains(part) else { return }
        let p = page.parts[part]
        let value = values[safe: part] ?? p.categories.first ?? ""
        guard !value.isEmpty else { return }
        loading = true
        error = nil
        note = nil
        searchedKeyword = nil
        rankOption = nil
        activePart = part
        do {
            let result = try await core.categoryComics(key: source, category: value,
                                                       param: p.param(for: value),
                                                       options: optionValues, page: number)
            guard gen == generation else { return }
            comics = result.comics
            pageNumber = number
            maxPage = result.maxPage ?? 0
            loading = false
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            comics = []
        }
    }

    private func search(_ core: CoreClient, keyword: String, page number: Int, generation gen: Int) async {
        loading = true
        error = nil
        activePart = nil
        rankOption = nil
        do {
            let defaults = (try? await core.searchOptions(key: source))?.map(\.defaultSearchValue)
                ?? (page?.options?.map(\.defaultSearchValue) ?? [])
            let result = try await core.searchPage(key: source, keyword: keyword, page: number, options: defaults)
            guard gen == generation else { return }
            comics = result.comics
            pageNumber = number
            maxPage = result.maxPage ?? 0
            loading = false
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            comics = []
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
