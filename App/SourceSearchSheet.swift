import NekularityKit
import SwiftUI

/// Search results from one source, opened by tapping one of its tags.
///
/// The search text is the source's own: `copy_manga` answers an author tag with
/// "作者:<name>", so the client must not build the query itself. A source that
/// answers with a category parameter is handled by the category browser instead.
struct SourceSearchSheet: View {
    let source: String
    let keyword: String

    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var comics: [Comic] = []
    @State private var pending = true
    @State private var error: String?
    @State private var page = 1
    @State private var maxPage = 0
    @State private var cursor = ""
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            Group {
                if let error, comics.isEmpty {
                    ContentUnavailableView {
                        Label("搜索失败", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("重试") { Task { await load(1, cursor: "") } }
                    }
                } else if pending && comics.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comics.isEmpty {
                    ContentUnavailableView("没有结果", systemImage: "magnifyingglass")
                } else {
                    List {
                        Section {
                            ForEach(comics) { comic in
                                NavigationLink(value: ComicRoute(source: source, comic: comic)) {
                                    row(comic)
                                }
                            }
                        }
                        Section {
                            HStack {
                                if cursor.isEmpty {
                                    Button("上一页") { Task { await load(page - 1, cursor: "") } }
                                        .disabled(pending || page <= 1)
                                    Spacer()
                                    Text("第 \(page) 页").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("下一页") { Task { await load(page + 1, cursor: "") } }
                                        .disabled(pending || maxPage == 0 || page >= maxPage)
                                } else {
                                    // A cursor source has no page count to show;
                                    // the source only hands out the next token.
                                    Button("下一页") { Task { await load(page + 1, cursor: cursor) } }
                                        .disabled(pending)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: ComicRoute.self) { ComicDetailView(route: $0) }
                }
            }
            .navigationTitle("\(source) · \(keyword)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load(1, cursor: "") }
        }
    }

    private func row(_ comic: Comic) -> some View {
        HStack(spacing: 12) {
            SourceImage(key: .init(source: source, url: comic.cover ?? "", isThumbnail: true), maxPixel: 180)
                .frame(width: 48, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title).font(.subheadline).lineLimit(2)
                if let sub = comic.subtitle, !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func load(_ wanted: Int, cursor next: String) async {
        let target = max(1, wanted)
        generation += 1
        let ticket = generation
        pending = true
        error = nil
        do {
            let options = (try? await library.core.searchOptions(key: source))?.map(\.defaultSearchValue) ?? []
            let result: ComicPage
            if next.isEmpty {
                result = try await library.core.searchPage(
                    key: source, keyword: keyword, page: target, options: options)
            } else {
                result = try await library.core.searchNext(
                    key: source, keyword: keyword, cursor: next, options: options)
            }
            guard ticket == generation else { return }
            comics = result.comics
            page = target
            maxPage = result.maxPage ?? 0
            cursor = result.next ?? ""
            pending = false
        } catch {
            guard ticket == generation else { return }
            pending = false
            if (error as? CoreError)?.isCancelled != true {
                self.error = error.localizedDescription
            }
            comics = []
        }
    }
}
