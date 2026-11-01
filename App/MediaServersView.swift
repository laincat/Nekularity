import NekularityKit
import SwiftUI

/// Media servers the user owns: connected, browsed and played from one place.
///
/// This is deliberately not part of 漫画源: a server is an account with a library,
/// and the two have different lifetimes, different secrets and different screens.
struct MediaServersView: View {
    @Environment(MediaServerStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    private var identifier: String {
        ProcessInfo.processInfo.environment["NK_MEDIA_DEVICE"] ?? "nekularity-ios"
    }

    var body: some View {
        List {
            if servers.servers.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有连接服务器", systemImage: "externaldrive.badge.wifi")
                    } description: {
                        Text("Jellyfin 或 Emby 的地址、账号和密码。片库留在你自己的服务器上。")
                    }
                }
            } else {
                Section("已连接") {
                    ForEach(servers.servers) { server in
                        NavigationLink {
                            MediaBrowserView(server: server, deviceID: identifier)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.displayName).font(.body.weight(.medium))
                                Text(server.baseURL).font(.caption).foregroundStyle(.secondary)
                                if let status = servers.status[server.id] {
                                    Text(status).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("media.server.\(server.id)")
                        .swipeActions {
                            Button("移除", role: .destructive) { servers.remove(server) }
                        }
                    }
                }
            }
        }
        .navigationTitle("媒体服务器")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("添加", systemImage: "plus") }
                    .accessibilityIdentifier("media.add")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(isPresented: $adding) {
            MediaServerAddView(deviceID: identifier)
        }
    }
}

/// The add form. Adding and signing in are one step: a row that never works is
/// worse than no row, and the user cannot tell which half was wrong.
struct MediaServerAddView: View {
    let deviceID: String
    @Environment(MediaServerStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MediaServer.Kind = .jellyfin
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach([MediaServer.Kind.jellyfin, .emby, .plex], id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("地址,例如 192.168.1.9:8096", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("media.address")
                    TextField("名称(可留空)", text: $name)
                } header: {
                    Text("服务器")
                } footer: {
                    Text("没有写协议就按 http 处理。证书是自签的也只在局域网内放行。")
                }
                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }
                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text(busy ? "正在连接…" : "连接")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(busy || address.isEmpty || username.isEmpty)
                    .accessibilityIdentifier("media.connect")
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        busy = true
        failure = nil
        defer { busy = false }
        do {
            _ = try await servers.add(
                client: MediaServerClient.live(deviceID: deviceID),
                server: MediaServer(kind: kind, name: name, baseURL: address),
                username: username, password: password)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// One server's libraries and their contents.
struct MediaBrowserView: View {
    let server: MediaServer
    let deviceID: String

    @Environment(MediaServerStore.self) private var servers
    @Environment(ShelfStore.self) private var shelf
    @State private var libraries: [MediaLibrary] = []
    @State private var items: [MediaItem] = []
    @State private var selected: MediaLibrary?
    @State private var playing: Playing?
    @State private var failure: String?
    @State private var loading = true

    private struct Playing: Identifiable {
        let id = UUID()
        let item: MediaItem
        let url: String
    }

    private var client: MediaServerClient { .live(deviceID: deviceID) }

    var body: some View {
        List {
            if let failure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                }
            }
            if !libraries.isEmpty {
                Section {
                    Picker("媒体库", selection: Binding(get: { selected?.id ?? "" },
                                                    set: { id in
                        selected = libraries.first { $0.id == id }
                        Task { await loadItems() }
                    })) {
                        ForEach(libraries) { library in
                            Text(library.name).tag(library.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if loading {
                Section { ProgressView() }
            } else if items.isEmpty, failure == nil {
                Section {
                    Text("这个媒体库里没有影片。").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section("影片") {
                    ForEach(items) { item in
                        Button {
                            open(item)
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(server.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLibraries() }
        .sheet(item: $playing) { pending in
            VideoPlayerView(title: pending.item.title,
                            play: VideoPlay(url: pending.url, format: "mp4"),
                            startPosition: Double(pending.item.position)) { position, seconds in
                // Watching from a server is watching: it belongs in the same
                // history as everything else.
                shelf.recordVideo(provider: server.displayName, videoID: pending.item.id,
                                  title: pending.item.title, cover: pending.item.poster,
                                  episode: pending.item.series.isEmpty ? nil : pending.item.title,
                                  seconds: position, duration: seconds)
            }
        }
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let poster = item.poster, let url = URL(string: poster) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 56, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body)
                if !item.series.isEmpty {
                    Text(item.series).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let year = item.year { Text("\(String(year))") }
                    if item.runtime > 0 { Text(Self.clock(item.runtime)) }
                }
                .font(.caption2).foregroundStyle(.secondary)
                if item.progress > 0 {
                    ProgressView(value: item.progress)
                }
            }
        }
    }

    private func loadLibraries() async {
        loading = true
        defer { loading = false }
        guard let token = servers.token(for: server) else {
            failure = "没有保存的登录,请重新添加这个服务器。"
            return
        }
        do {
            libraries = try await client.libraries(server: server, token: token)
            selected = libraries.first
            await loadItems()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func loadItems() async {
        guard let token = servers.token(for: server) else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await client.items(server: server, token: token, library: selected)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func open(_ item: MediaItem) {
        guard let token = servers.token(for: server) else { return }
        do {
            playing = Playing(item: item, url: try client.playURL(server: server, token: token, item: item))
        } catch {
            failure = error.localizedDescription
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        return "\(minutes):" + (rest < 10 ? "0\(rest)" : "\(rest)")
    }
}
