import SwiftUI
import NekularityKit

struct ComicDetailView: View {
    let route: ComicRoute
    @Environment(SourceLibrary.self) private var library
    @State private var details: ComicDetails?
    @State private var error: String?

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
        .navigationDestination(for: ReaderRoute.self) { ReaderView(route: $0) }
        .task { if details == nil { await load() } }
    }

    private func load() async {
        error = nil
        do { details = try await library.core.details(key: route.source, comicID: route.comic.id) } catch {
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
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
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                if let desc = d.description, !desc.isEmpty {
                    Text(desc).font(.callout).textSelection(.enabled)
                }
                ForEach(Array(d.tags.enumerated()), id: \.offset) { _, tag in
                    LabeledContent(tag.group) {
                        Text(tag.values.joined(separator: "、")).multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }
            }

            if d.chapters.isEmpty {
                // Single-chapter comics have no chapter list; loadEp gets nil.
                Section {
                    NavigationLink("开始阅读", value: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                       comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                       author: route.comic.subtitle,
                                                       cover: route.comic.cover,
                                                       chapters: [], index: 0))
                }
            } else {
                ForEach(groups(d.chapters), id: \.name) { group in
                    Section(group.name ?? "章节") {
                        ForEach(group.items, id: \.offset) { i, chapter in
                            NavigationLink(chapter.title,
                                           value: ReaderRoute(source: route.source, comicID: route.comic.id,
                                                             comicTitle: d.title.isEmpty ? route.comic.title : d.title,
                                                             author: route.comic.subtitle,
                                                             cover: route.comic.cover,
                                                             chapters: d.chapters, index: i))
                        }
                    }
                }
            }
        }
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
