import NekularityKit
import SwiftUI

/// 媒体库: every film this environment can play, in one searchable list.
///
/// Local files and media servers answer the same question — "what can I watch" —
/// so they get one screen. The rows carry where they came from, because "why does
/// this one not play on the train" has an answer the user can act on.
struct MediaHubView: View {
    @Environment(MediaServerStore.self) private var servers
    @Environment(VideoLibraryStore.self) private var media
    @Environment(ShelfStore.self) private var shelf
    @Environment(MetadataStore.self) private var metadata

    @State private var query = ""
    @State private var serverRows: [(name: String, id: String, items: [MediaItem])] = []
    @State private var failures: [String] = []
    @State private var loading = false
    @State private var playing: Playing?

    private struct Playing: Identifiable {
        let id = UUID()
        let title: String
        let server: String
        let itemID: String
        let url: String
        let start: Double
        let poster: String?
    }

    private var identifier: String {
        ProcessInfo.processInfo.environment["NK_MEDIA_DEVICE"] ?? "nekularity-ios"
    }

    private var entries: [HubEntry] {
        let local = media.items.map { item in
            (id: item.id, title: item.title, poster: String?.none, progress: item.progress)
        }
        return MediaHub.entries(local: local, servers: serverRows)
    }

    private var shown: [HubEntry] { MediaHub.search(entries, query: query) }

    var body: some View {
        List {
            Section {
                TextField("搜索影片、剧名", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("mediaHub.search")
            }

            if loading {
                Section { ProgressView() }
            }

            ForEach(failures, id: \.self) { failure in
                Section {
                    Text(failure).font(.footnote).foregroundStyle(.orange)
                }
            }

            if query.isEmpty {
                let resume = MediaHub.continueWatching(shown)
                if !resume.isEmpty {
                    Section("继续观看") {
                        ForEach(resume) { entry in
                            row(entry)
                        }
                    }
                }
            }

            ForEach(MediaHub.grouped(shown), id: \.name) { group in
                Section(group.name) {
                    if group.rows.isEmpty {
                        Text("这里还没有影片。").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(group.rows) { entry in
                            row(entry)
                        }
                    }
                }
            }

            if !servers.servers.isEmpty {
                Section {
                    NavigationLink {
                        MediaServersView()
                    } label: {
                        Label("管理媒体服务器", systemImage: "externaldrive.badge.wifi")
                    }
                }
            }
        }
        .navigationTitle("媒体库")
        .task { await loadServers() }
        .refreshable { await loadServers() }
        .sheet(item: $playing) { pending in
            VideoPlayerView(title: pending.title, play: VideoPlay(url: pending.url, format: "mp4"),
                            provider: pending.server, showTitle: pending.title,
                            startPosition: pending.start) { position, seconds in
                // One history again: a film played from a server and one played
                // from a file both have a position worth remembering.
                shelf.recordVideo(provider: pending.server, videoID: pending.itemID,
                                  title: pending.title, cover: pending.poster,
                                  seconds: position, duration: seconds)
                if pending.server == "本机",
                   let local = media.items.first(where: { $0.id == pending.itemID }) {
                    media.update(local, position: position, seconds: seconds)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: HubEntry) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let poster = entry.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                    } else {
                        Color.secondary.opacity(0.15)
                            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 52, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.body)
                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.sourceName).font(.caption2).foregroundStyle(.tertiary)
                    if entry.progress > 0 {
                        ProgressView(value: entry.progress)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mediaHub.entry.\(entry.id)")
    }

    private func open(_ entry: HubEntry) {
        switch entry.origin {
        case .local(let fileID):
            guard let item = media.items.first(where: { $0.id == fileID }) else { return }
            playing = Playing(title: item.title, server: "本机", itemID: item.id,
                              url: media.url(for: item).absoluteString,
                              start: max(item.position,
                                         shelf.playbackStart(provider: "本机", videoID: item.id) ?? 0),
                              poster: nil)
        case .server(let serverID, let itemID):
            guard let server = servers.servers.first(where: { $0.id == serverID }),
                  let token = servers.token(for: server),
                  let item = serverRows.first(where: { $0.id == serverID })?
                      .items.first(where: { $0.id == itemID }) else { return }
            let client = MediaServerClient.live(deviceID: identifier)
            guard let url = try? client.playURL(server: server, token: token,
                                                item: MediaItem(id: itemID, title: entry.title)) else { return }
            // The server knows where its own account stopped; this environment
            // knows where *this* device stopped. The further one wins, so
            // watching on the phone is not undone by a stale server position.
            let remembered = shelf.playbackStart(provider: server.displayName, videoID: itemID) ?? 0
            playing = Playing(title: entry.title, server: server.displayName, itemID: itemID,
                              url: url, start: max(Double(item.position), remembered), poster: item.poster)
        }
    }

    /// Each server is asked on its own, so one unreachable NAS does not hide the
    /// films on the one that answered.
    private func loadServers() async {
        loading = true
        defer { loading = false }
        failures = []
        let client = MediaServerClient.live(deviceID: identifier)
        var loaded: [(name: String, id: String, items: [MediaItem])] = []
        for server in servers.servers {
            guard let token = servers.token(for: server) else {
                failures.append("\(server.displayName):没有保存的登录,请重新添加")
                continue
            }
            do {
                var all: [MediaItem] = []
                for library in try await client.libraries(server: server, token: token) {
                    all += try await client.items(server: server, token: token, library: library)
                }
                loaded.append((server.displayName, server.id, all))
            } catch {
                failures.append("\(server.displayName):\(error.localizedDescription)")
            }
        }
        serverRows = loaded
        await identifyShows()
    }

    /// Turns the series names a server reports into shows the calendar can date.
    ///
    /// Cached answers are free, so this only spends requests on names it has never
    /// seen; a name that matches nothing is left alone rather than retried on
    /// every visit.
    private func identifyShows() async {
        guard metadata.hasKey, let key = metadata.apiKey() else { return }
        let client = TMDBClient.live(apiKey: key)
        let names = Set(serverRows.flatMap { row in row.items.map(\.series) }.filter { !$0.isEmpty })
        var looked = 0
        for name in names {
            guard looked < 6 else { break }
            if metadata.series.values.contains(where: { $0.name == name }) { continue }
            looked += 1
            _ = try? await metadata.identify(title: name, client: client)
        }
    }
}
