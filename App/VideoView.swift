import NekularityKit
import Observation
import SwiftUI

/// One video provider's search results.
///
/// A video source answers with the same list shape a comic source does, minus
/// chapters: an episode plays, it is not paged through. The provider's own id
/// and key travel together into the detail screen, because a video id is only
/// meaningful to the provider that issued it.
struct VideoRoute: Hashable, Identifiable {
    let key: String
    let id: String
    let title: String
}

@MainActor
@Observable
final class VideoSearchModel {
    var sourceKey = ""
    var query = ""
    var items: [VideoPage.Item] = []
    var next: String?
    var loading = false
    var failure: String?

    func search(core: CoreClient, reset: Bool = true) async {
        guard !sourceKey.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await core.videoSearch(
                key: sourceKey, keyword: query,
                cursor: reset ? "" : (next ?? ""))
            items = reset ? page.items : items + page.items
            next = page.next
            failure = nil
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }

    @ObservationIgnored var library: CoreClient!
}

/// Video browsing: pick a provider, search it, open a result.
struct VideoView: View {
    @Environment(SourceLibrary.self) private var library
    @State private var model = VideoSearchModel()

    private var sources: [PluginRecord] {
        library.sources.filter { $0.enabled && $0.isVideo }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView("没有可用的视频源", systemImage: "play.rectangle",
                                           description: Text("视频源是插件：先安装一个再回来。"))
                } else {
                    VStack(spacing: 0) {
                        field
                        results
                    }
                }
            }
            .navigationTitle("视频")
            .navigationDestination(for: VideoRoute.self) { route in
                VideoDetailView(route: route)
            }
        }
        .task {
            if model.sourceKey.isEmpty || !sources.contains(where: { $0.key == model.sourceKey }) {
                model.sourceKey = sources.first?.key ?? ""
            }
        }
    }

    private var field: some View {
        VStack(spacing: 8) {
            Picker("视频源", selection: $model.sourceKey) {
                ForEach(sources) { source in
                    Text(source.name).tag(source.key)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("video.source")
            HStack {
                TextField("搜索影片", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.search(core: library.core) } }
                    .accessibilityIdentifier("video.query")
                Button("搜索") { Task { await model.search(core: library.core) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("video.search")
            }
        }
        .padding()
    }

    @ViewBuilder
    private var results: some View {
        if let failure = model.failure {
            ContentUnavailableView {
                Label("搜索失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else if model.items.isEmpty {
            if model.loading { ProgressView() } else {
                ContentUnavailableView("还没有结果", systemImage: "magnifyingglass",
                                       description: Text("输入关键词后搜索。"))
            }
        } else {
            List {
                ForEach(model.items) { item in
                    NavigationLink(value: VideoRoute(key: model.sourceKey, id: item.id, title: item.title)) {
                        HStack(alignment: .top, spacing: 12) {
                            if let cover = item.cover, let url = URL(string: cover) {
                                SourceImage(key: .init(source: model.sourceKey, url: url.absoluteString, isThumbnail: true), maxPixel: 200)
                                    .frame(width: 64, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                if let tags = item.tags, !tags.isEmpty {
                                    Text(tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if model.next?.isEmpty == false {
                    Button("加载更多") { Task { await model.search(core: library.core, reset: false) } }
                }
            }
        }
    }
}

/// One video's lines and episodes.
struct VideoDetailView: View {
    let route: VideoRoute
    @Environment(SourceLibrary.self) private var library
    @State private var details: VideoDetails?
    @State private var failure: String?
    @State private var playing: PendingPlay?

    var body: some View {
        Group {
            if let failure {
                ContentUnavailableView {
                    Label("打不开", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                }
            } else if let details {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(details.title).font(.title3.bold())
                            if let description = details.description, !description.isEmpty {
                                Text(description).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(details.lines) { line in
                        Section(line.title) {
                            ForEach(line.episodes) { episode in
                                Button(episode.title) {
                                    Task { await open(details: details, line: line, episode: episode) }
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $playing) { pending in
            VideoPlayerView(title: pending.title, play: pending.play)
        }
    }

    private struct PendingPlay: Identifiable {
        let title: String
        let play: VideoPlay
        var id: String { title + (play.url ?? "") }
    }

    private func load() async {
        do {
            details = try await library.core.videoDetails(key: route.key, id: route.id)
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }

    private func open(details: VideoDetails, line: VideoDetails.Line,
                      episode: VideoDetails.Line.Episode) async {
        do {
            let play = try await library.core.videoPlay(key: route.key, itemID: details.id,
                                                        lineID: line.id, episodeID: episode.id)
            guard play.isPlayable else {
                failure = play.sniff != nil
                    ? "这个源需要先嗅探播放页，客户端还没有这条路径"
                    : "这个源给出的地址无法直接播放"
                return
            }
            playing = PendingPlay(title: episode.title, play: play)
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }
}
