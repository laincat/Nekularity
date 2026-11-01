import NekularityKit
import Observation
import SwiftUI

/// A source's own favorites: the ones it keeps on its side, which are a
/// different thing from the local shelf.
///
/// The shapes differ and do not overlap. `nhentai` has one folder and no folder
/// list, `ehentai` has folders but no list function at all, `wnacg` has both.
/// The screen therefore shows what the source can do and says so when it
/// cannot list anything.
struct SourceFavoritesView: View {
    let source: PluginRecord
    @Environment(SourceLibrary.self) private var library
    @State private var model = FavoritesModel()

    var body: some View {
        Group {
            if model.loading && model.page == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error, model.comics.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await model.open(library.core, source: source.key) } }
                }
            } else if !model.support.supported {
                ContentUnavailableView("这个源没有提供收藏", systemImage: "heart")
            } else if !model.support.hasList {
                // ehentai: folders and a toggle, but nothing to read.
                ContentUnavailableView("这个源没有提供收藏列表", systemImage: "heart.slash")
            } else {
                VStack(spacing: 0) {
                    if model.support.folders, !model.folders.isEmpty {
                        folders
                        Divider()
                    }
                    list
                }
            }
        }
        .navigationTitle("\(source.name) 的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: source.key) { await model.open(library.core, source: source.key) }
    }

    /// One chip per folder the source keeps.
    private var folders: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.folderList, id: \.id) { folder in
                    Button {
                        Task { await model.selectFolder(library.core, folder: folder.id) }
                    } label: {
                        Text(folder.name)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(model.folder == folder.id
                                        ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                                        in: Capsule())
                            .foregroundStyle(model.folder == folder.id ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    @ViewBuilder private var list: some View {
        if model.comics.isEmpty && !model.loading {
            ContentUnavailableView("这个收藏夹没有内容", systemImage: "tray")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.comics) { comic in
                        NavigationLink(value: ComicRoute(source: source.key, comic: comic)) {
                            BrowseRow(source: source.key, comic: comic)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 76)
                    }
                    if model.maxPage > 0 {
                        HStack {
                            Text("第 \(model.page) / \(model.maxPage) 页").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("上一页") { Task { await model.loadPage(library.core, page: model.page - 1) } }
                                .disabled(model.page <= 1 || model.loading)
                            Button("下一页") { Task { await model.loadPage(library.core, page: model.page + 1) } }
                                .disabled(model.page >= model.maxPage || model.loading)
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

/// The favorites a source keeps, and the list they produce.
@MainActor @Observable
final class FavoritesModel {
    private(set) var support = FavoritesSupport(supported: false, multiFolder: false, folders: false, canLoad: false)
    private(set) var folders: [String: String] = [:]
    private(set) var folder: String?
    private(set) var comics: [Comic] = []
    private(set) var page = 1
    private(set) var maxPage = 0
    var loading = false
    var error: String?

    /// Bumped by each new load, so a slow answer for an old source is dropped.
    private var generation = 0

    /// The folders in a stable order, so the chips do not move around.
    var folderList: [(id: String, name: String)] {
        folders.keys.sorted().map { ($0, folders[$0] ?? $0) }
    }

    func open(_ core: CoreClient, source: String) async {
        generation += 1
        let gen = generation
        sourceKey = source
        loading = true
        error = nil
        support = await core.favoritesSupport(key: source)
        guard gen == generation else { return }
        guard support.supported else {
            loading = false
            return
        }
        if support.folders {
            // A source that needs a session refuses here, and its own words are
            // the reason worth showing.
            if let (folders, _) = try? await core.favoriteFolders(key: source, comicID: nil) {
                self.folders = folders
            }
        }
        guard gen == generation else { return }
        loading = false
        guard support.hasList else { return }
        // A single-folder source takes no folder id at all.
        let first = folderList.first?.id
        await load(core, folder: support.multiFolder ? first : nil, page: 1, generation: gen)
    }

    func selectFolder(_ core: CoreClient, folder: String) async {
        guard self.folder != folder else { return }
        generation += 1
        await load(core, folder: folder, page: 1, generation: generation)
    }

    func loadPage(_ core: CoreClient, page number: Int) async {
        guard maxPage > 0, (1...maxPage).contains(number), number != page else { return }
        generation += 1
        await load(core, folder: folder, page: number, generation: generation)
    }

    func reload(_ core: CoreClient) async {
        guard support.supported else { return }
        generation += 1
        await load(core, folder: folder, page: page, generation: generation)
    }

    private func load(_ core: CoreClient, folder: String?, page number: Int, generation gen: Int) async {
        guard let source = sourceKey else { return }
        loading = true
        error = nil
        do {
            let result = try await core.favoriteComics(key: source, folder: folder, page: number)
            guard gen == generation else { return }
            comics = result.comics
            self.folder = folder
            page = number
            maxPage = result.maxPage ?? 0
            loading = false
        } catch {
            guard gen == generation else { return }
            loading = false
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
            comics = []
        }
    }

    /// The source whose favorites are open.
    private(set) var sourceKey: String?
}
