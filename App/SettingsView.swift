import NekularityKit
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`. A theme file is written by hand, so a colour
    /// that will not parse falls back to the system's rather than drawing black.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// The fourth tab: storage, accounts, modules, appearance.
///
/// Rex's settings opens with what the app costs on disk and then groups the rest
/// by what the user came for. The same order here, with the sections this app
/// can actually fill.
struct SettingsView: View {
    let magpie: MagpieAccounts
    @Environment(ThemeStore.self) private var themes
    @Environment(DownloadStore.self) private var downloads
    @Environment(VideoLibraryStore.self) private var media
    @Environment(ProfileStore.self) private var profiles
    @Environment(MetadataStore.self) private var metadata
    @State private var tmdbKey = ""
    @State private var reminders = AiringReminders()
    @State private var remindersOn = false
    @State private var metadataNote: String?
    @Environment(\.switchProfile) private var switchProfile
    @State private var showingProfiles = false
    @State private var importing = false
    @State private var note: String?
    @State private var showAI = false

    private var videoBytes: Int64 { Int64(media.items.reduce(0) { $0 + $1.bytes }) }
    private var total: Int64 { max(1, videoBytes + downloads.totalBytes) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("空间占用")
                            Spacer()
                            Text(Self.size(videoBytes + downloads.totalBytes)).foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            HStack(spacing: 2) {
                                bar(width: proxy.size.width * Double(videoBytes) / Double(total),
                                    color: .blue)
                                bar(width: proxy.size.width * Double(downloads.totalBytes) / Double(total),
                                    color: .orange)
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 10)
                        HStack(spacing: 14) {
                            legend("视频", color: .blue, value: Self.size(videoBytes))
                            legend("下载", color: .orange, value: Self.size(downloads.totalBytes))
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }

                Section("环境") {
                    Button { showingProfiles = true } label: {
                        LabeledContent("当前环境", value: profiles.active.name)
                    }
                    .accessibilityIdentifier("settings.profiles")
                    if profiles.profiles.count > 1 {
                        Text("共 \(profiles.profiles.count) 个环境").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("账号与平台") {
                    Button { showAI = true } label: {
                        Label("AI 供应商与标准接口", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("settings.ai")
                    LabeledContent("漫画源登录", value: "在源的设置里登录")
                        .foregroundStyle(.secondary)
                }

                Section("模块与源") {
                    NavigationLink {
                        SourcesView(magpie: magpie)
                    } label: {
                        Label("漫画源与视频源", systemImage: "puzzlepiece.extension")
                    }
                    .accessibilityIdentifier("settings.sources")
                }

                Section {
                    SecureField(metadata.hasKey ? "已保存,粘贴新 key 可替换" : "TMDB API key",
                                text: $tmdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.tmdbKey")
                    HStack {
                        Button("保存") { saveKey() }
                            .disabled(tmdbKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        if metadata.hasKey {
                            Button("清除", role: .destructive) {
                                try? metadata.setKey("")
                                tmdbKey = ""
                                metadataNote = "已清除"
                            }
                        }
                    }
                    if let metadataNote {
                        Text(metadataNote).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("元数据")
                } footer: {
                    Text("TMDB 的 key 或 v4 令牌,都存在钥匙串里。用它把剧名对到播出日期,日历才有「即将播出」。")
                }

                Section {
                    Toggle("追剧提醒", isOn: $remindersOn)
                        .accessibilityIdentifier("settings.reminders")
                        .onChange(of: remindersOn) { _, on in
                            Task { await toggleReminders(on) }
                        }
                    Button {
                        Task { await syncReminders() }
                    } label: {
                        Label("立即同步提醒", systemImage: "bell.badge")
                    }
                    .disabled(!reminders.authorised)
                    .accessibilityIdentifier("settings.reminders.sync")
                    if reminders.authorised {
                        Text("已安排 \(reminders.pending) 条").font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = reminders.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("在播出日当天上午提醒。日期来自 TMDB;没有 key 时没有日期,也就没有提醒。")
                }

                Section("外观") {
                    ForEach(themes.all) { theme in
                        Button { themes.select(theme) } label: {
                            HStack {
                                Circle().fill(Color(hex: theme.accent) ?? .accentColor)
                                    .frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.name)
                                    if let author = theme.author {
                                        Text(author).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if themes.active.id == theme.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions {
                            if !BuiltinThemes.all.contains(where: { $0.id == theme.id }) {
                                Button("删除", role: .destructive) { themes.remove(theme) }
                            }
                        }
                    }
                    Button { importing = true } label: {
                        Label("导入主题文件", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings.importTheme")
                }

                Section {
                    NavigationLink { DiagnosticsView() } label: {
                        Label("自检", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("settings.diagnostics")
                }

                Section("关于") {
                    LabeledContent("版本", value: Self.version)
                    LabeledContent("Core", value: CoreVersion.short)
                }
            }
            .navigationTitle("设置")
            // The bar floats over the content, so the last row needs room or it
            // is unreadable underneath it.
            .contentMargins(.bottom, 76, for: .scrollContent)
            .sheet(isPresented: $showingProfiles) {
                ProfilesView(profiles: profiles, switchTo: switchProfile)
            }
            .sheet(isPresented: $showAI) { MagpieProvidersView(accounts: magpie, showsClose: true) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try themes.install(data: Data(contentsOf: url))
                        note = "已导入主题，在上面的列表里选中它即可"
                    } catch {
                        note = (error as? CoreError)?.message ?? error.localizedDescription
                    }
                case .failure(let error):
                    note = error.localizedDescription
                }
            }
            .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
                Button("好") { note = nil }
            }
        }
    }

    private func bar(width: Double, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func legend(_ name: String, color: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(value)").foregroundStyle(.secondary)
        }
    }

    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    /// Saving is also the check: a key that the source rejects is worse than no
    /// key, because the calendar would then quietly show nothing for ever.
    private func saveKey() {
        do {
            try metadata.setKey(tmdbKey)
            let client = TMDBClient.live(apiKey: tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines))
            metadataNote = "正在验证…"
            Task {
                do {
                    let found = try await client.search(query: "Severance")
                    metadataNote = found.isEmpty ? "key 可用" : "key 可用,能查到剧集"
                } catch {
                    metadataNote = error.localizedDescription
                }
                tmdbKey = ""
            }
        } catch {
            metadataNote = error.localizedDescription
        }
    }


    private func toggleReminders(_ on: Bool) async {
        guard on else {
            await reminders.cancelAll()
            return
        }
        guard await reminders.requestAuthorisation() else { return }
        await syncReminders()
    }

    /// Plans from what the metadata store already knows, so this needs no network
    /// round-trip of its own.
    private func syncReminders() async {
        let plan = AiringPlan.plan(metadata.upcoming(within: 30, from: Date()).map(\.info))
        await reminders.sync(plan: plan)
    }

}
