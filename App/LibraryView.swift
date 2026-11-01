import NekularityKit
import SwiftUI

/// The third tab: what this app can read and play, and where it comes from.
///
/// Rex splits this into 媒体服务器 (Emby/Jellyfin/Plex) and 模块 (scripts). We
/// have the module half — comic sources and video sources — and no server
/// connections yet, so the server section says so instead of showing an empty
/// list that looks broken.
struct LibraryView: View {
    @Environment(SourceLibrary.self) private var library
    @Environment(VideoLibraryStore.self) private var media

    private var comics: [PluginRecord] { library.sources.filter { $0.type == "comic" } }
    private var videos: [PluginRecord] { library.sources.filter(\.isVideo) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("媒体服务器") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还没有连接服务器").font(.callout)
                            Text("Jellyfin、Emby、Plex 这些库还没有接；接上之后，它们会和本机视频出现在同一处。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }

                    section("模块") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            module("漫画源", count: comics.count,
                                   detail: "安装、更新与源设置", symbol: "book.closed")
                            NavigationLink { VideoView() } label: {
                                module("视频", count: videos.count,
                                       detail: "插件、规则与本机视频", symbol: "play.rectangle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.video")
                        }
                    }

                    section("本机") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(media.items.count) 个视频 · \(library.sources.count) 个源")
                                .font(.callout)
                            Text("视频从这里导入，源从「漫画源」里安装。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(16)
            }
            .navigationTitle("资源库")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func module(_ title: String, count: Int, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).foregroundStyle(.tint)
                Spacer()
                Text("\(count)").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
