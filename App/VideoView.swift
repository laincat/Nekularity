import NekularityKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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
}

/// Video, in two places: what is on this device, and what the sources offer.
///
/// The device comes first because it is the half that works with no connection
/// and no account — it is the part of a library the user owns outright.
struct VideoView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case library, sources
        var id: String { rawValue }
        var title: String { self == .library ? "本机" : "在线源" }
    }

    @Environment(SourceLibrary.self) private var library
    @Environment(VideoLibraryStore.self) private var media
    @Environment(ShelfStore.self) private var shelf
    @State private var mode: Mode = .library
    @State private var model = VideoSearchModel()
    @State private var importing = false
    @State private var playing: Playing?
    @State private var note: String?

    private var sources: [PluginRecord] {
        library.sources.filter { $0.enabled && $0.isVideo }
    }

    struct Playing: Identifiable {
        let id = UUID()
        /// Where the episode came from: the provider key, or 本地 for a file.
        let provider: String
        let videoID: String
        let title: String
        let episode: String?
        let cover: String?
        let play: VideoPlay
        let start: Double
        let local: VideoLibraryStore.Item?
    }

    var body: some View {
        Group {
            switch mode {
            case .library: libraryTab
            case .sources: sourcesTab
            }
        }
        .navigationTitle("视频")
        .safeAreaInset(edge: .top) {
            Picker("来源", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityIdentifier("video.mode")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .video]) { result in
            switch result {
            case .success(let url):
                do {
                    try media.importVideo(from: url)
                } catch {
                    note = error.localizedDescription
                }
            case .failure(let error):
                note = error.localizedDescription
            }
        }
        .sheet(item: $playing) { item in
            VideoPlayerView(title: item.title, play: item.play,
                            provider: item.provider, showTitle: item.title,
                            startPosition: item.start) { position, seconds in
                if let local = item.local {
                    media.update(local, position: position, seconds: seconds)
                }
                // Watching belongs in the same history as reading: the calendar
                // asks one question, so it needs one list.
                shelf.recordVideo(provider: item.provider, videoID: item.videoID, title: item.title,
                                  cover: item.cover, episode: item.episode,
                                  seconds: position, duration: seconds)
            }
        }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("好") { note = nil }
        }
        .task {
            if model.sourceKey.isEmpty || !sources.contains(where: { $0.key == model.sourceKey }) {
                model.sourceKey = sources.first?.key ?? ""
            }
        }
    }

    // MARK: - This device

    private var libraryTab: some View {
        Group {
            if media.items.isEmpty {
                ContentUnavailableView {
                    Label("本机还没有视频", systemImage: "play.rectangle.on.rectangle")
                } description: {
                    Text("把手机里的视频导入进来，这里会记住你看到哪儿。")
                } actions: {
                    Button("导入视频") { importing = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if let resume = media.resume {
                        Section("继续观看") {
                            row(resume, prominent: true)
                        }
                    }
                    Section("本机视频") {
                        ForEach(media.items) { item in row(item, prominent: false) }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: {
                    Label("导入", systemImage: "plus")
                }
                .accessibilityIdentifier("video.import")
            }
        }
    }

    private func row(_ item: VideoLibraryStore.Item, prominent: Bool) -> some View {
        Button {
            let url = media.url(for: item)
            playing = Playing(provider: "本地", videoID: item.id, title: item.title, episode: nil,
                              cover: nil, play: VideoPlay(url: url.absoluteString, format: "mp4"),
                              start: item.position, local: item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(prominent ? .headline : .body)
                if item.seconds > 0 {
                    ProgressView(value: item.progress)
                    HStack {
                        Text(PlaybackProgress.clock(item.position)).font(.caption.monospacedDigit())
                        Spacer()
                        Text(PlaybackProgress.clock(item.seconds)).font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("未看").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button("删除", role: .destructive) { media.remove(item) }
        }
    }

    // MARK: - Sources

    private var sourcesTab: some View {
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
                    NavigationLink {
                        VideoDetailView(route: VideoRoute(key: model.sourceKey, id: item.id, title: item.title))
                    } label: {
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
    @Environment(ShelfStore.self) private var shelf
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
            VideoPlayerView(title: pending.episode ?? pending.title, play: pending.play,
                            provider: pending.provider, showTitle: pending.title,
                            startPosition: shelf.playbackStart(provider: pending.provider,
                                                              videoID: pending.videoID) ?? 0) { position, seconds in
                shelf.recordVideo(provider: pending.provider, videoID: pending.videoID, title: pending.title,
                                  cover: pending.cover, episode: pending.episode,
                                  seconds: position, duration: seconds)
            }
        }
    }

    private struct PendingPlay: Identifiable {
        let id = UUID()
        let provider: String
        let videoID: String
        let title: String
        let episode: String?
        let cover: String?
        let play: VideoPlay
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
            playing = PendingPlay(provider: route.key, videoID: details?.id ?? route.id,
                                  title: details?.title ?? episode.title, episode: episode.title,
                                  cover: details?.cover, play: play)
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }
}
