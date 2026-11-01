import NekularityKit
import SwiftUI

/// The third tab: everything this app can reach, in one place.
///
/// Two halves, the way the reference app splits it: **sources** (media servers
/// when there are any, then the installed modules) and **what they feed** — a
/// search across every source, the library, video, downloads. The entries are
/// here rather than in the tab bar because the bar holds four, and a fifth would
/// fold the last one into 更多.
struct LibraryView: View {
    @Environment(SourceLibrary.self) private var library
    @Environment(VideoLibraryStore.self) private var media
    @Environment(DownloadStore.self) private var downloads
    @Environment(ShelfStore.self) private var shelf

    @State private var allSearch = false
    @State private var watching = false

    private var comics: [PluginRecord] { library.sources.filter { $0.type == "comic" } }
    private var videos: [PluginRecord] { library.sources.filter(\.isVideo) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("媒体服务器") {
                        card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("还没有连接服务器").font(.callout)
                                Text("Jellyfin、Emby、Plex 这些库还没有接；接上之后，它们会和本机视频出现在同一处。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("入口") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            entry("全源搜索", detail: "\(comics.filter(\.enabled).count) 个源一起搜",
                                  symbol: "magnifyingglass", id: "library.searchAll") {
                                allSearch = true
                            }
                            NavigationLink { ShelfView() } label: {
                                tile("书库", detail: "\(shelf.history.count) 部在读 · \(shelf.folders.flatMap(\.items).count) 部收藏",
                                     symbol: "books.vertical")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.shelf")

                            entry("视频", detail: "\(videos.count) 个源 · \(media.items.count) 个本机",
                                  symbol: "play.rectangle", id: "library.video") {
                                watching = true
                            }
                            NavigationLink { DownloadsView() } label: {
                                tile("下载", detail: "\(downloads.chapters.count) 话已保存",
                                     symbol: "arrow.down.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.downloads")
                        }
                    }

                    section("模块") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            tile("漫画源", detail: "\(comics.count) 个 · 安装与设置", symbol: "book.closed")
                            tile("视频源", detail: "\(videos.count) 个 · 插件与规则", symbol: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("资源库")
            .navigationDestination(isPresented: $allSearch) { SearchView(startsInAllSources: true) }
            .navigationDestination(isPresented: $watching) { VideoView() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    private func entry(_ title: String, detail: String, symbol: String, id: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(title, detail: detail, symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func tile(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
