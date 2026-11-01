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

/// Appearance, storage and the version of what is running.
///
/// A theme is a JSON file — installed from Files, kept under Application
/// Support, picked here — so a look can be shared without rebuilding the app.
struct SettingsView: View {
    @Environment(ThemeStore.self) private var themes
    @Environment(DownloadStore.self) private var downloads
    @State private var importing = false
    @State private var note: String?

    var body: some View {
        List {
            Section {
                ForEach(themes.all) { theme in
                    Button {
                        themes.select(theme)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: theme.accent) ?? .accentColor)
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
            } header: {
                Text("外观")
            } footer: {
                Text("主题是 JSON 文件：圆角、强调色、背景与深浅都能改。装一个主题就是把文件导进来，不涉及代码。")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("导入主题文件", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("settings.importTheme")
            } footer: {
                Text("主题文件示例：\n{\"id\":\"mine\",\"name\":\"我的主题\",\"accent\":\"#FF6B6B\",\"radius\":16}")
                    .font(.caption2.monospaced())
            }

            Section {
                LabeledContent("已下载", value: "\(downloads.chapters.count) 话")
                Button("清空下载", role: .destructive) { downloads.removeAll() }
                    .disabled(downloads.chapters.isEmpty)
            } header: {
                Text("存储")
            }

            Section("关于") {
                LabeledContent("版本", value: Self.version)
                LabeledContent("Core", value: CoreVersion.short)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
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
        .alert(note ?? "", isPresented: Binding(
            get: { note != nil },
            set: { if !$0 { note = nil } }
        )) {
            Button("好") { note = nil }
        }
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
