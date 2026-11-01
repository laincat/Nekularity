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
    @State private var importing = false
    @State private var note: String?
    @State private var showAI = false
    @State private var showSources = false

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

                Section("账号与平台") {
                    Button { showAI = true } label: {
                        Label("AI 供应商与标准接口", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("settings.ai")
                    LabeledContent("漫画源登录", value: "在源的设置里登录")
                        .foregroundStyle(.secondary)
                }

                Section("模块与源") {
                    Button { showSources = true } label: {
                        Label("漫画源与视频源", systemImage: "puzzlepiece.extension")
                    }
                    .accessibilityIdentifier("settings.sources")
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

                Section("关于") {
                    LabeledContent("版本", value: Self.version)
                    LabeledContent("Core", value: CoreVersion.short)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showAI) { MagpieProvidersView(accounts: magpie, showsClose: true) }
            .sheet(isPresented: $showSources) { SourcesView(magpie: magpie, showsClose: true) }
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
}
