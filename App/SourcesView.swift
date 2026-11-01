import NekularityKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Installed sources, install from URL or index, and source details.
struct SourcesView: View {
    let magpie: MagpieAccounts
    /// Presented from Settings, so it needs a way to close.
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SourceLibrary.self) private var library
    @Environment(ShelfStore.self) private var shelf
    @Environment(SearchHistoryStore.self) private var searches
    @State private var showAdd = false
    @State private var pickingBackup = false
    /// Restoring the old single jar's cookies is off unless asked for: they are
    /// credentials, and the default import has always left them out.
    @State private var restoreCookies = false
    /// One notice at a time: a view shows one alert, so failures and the
    /// import summary share it.
    @State private var notice: Notice?
    /// The exported archive, waiting for the share sheet to take it.
    @State private var exported: ExportFile?
    @State private var showLogs = false
    @State private var showAI = false

    var body: some View {
        List {
            if !library.restoreFailures.isEmpty {
                Section("未能恢复") {
                    ForEach(library.restoreFailures.sorted(by: { $0.key < $1.key }), id: \.key) { key, reason in
                        VStack(alignment: .leading) {
                            Text(key).font(.headline)
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                ForEach(library.comicSources) { source in
                    NavigationLink(value: source) { SourceRow(source: source) }
                        // A stable handle for the interface tests: a label is
                        // localized and a source renames itself.
                        .accessibilityIdentifier("source.\(source.key)")
                }
                .onDelete { offsets in
                    let keys = offsets.map { library.comicSources[$0].key }
                    Task {
                        for k in keys {
                            do { try await library.remove(k) } catch {
                                notice = Notice(title: "删除失败", text: error.localizedDescription)
                            }
                        }
                    }
                }
            } footer: {
                if library.comicSources.isEmpty {
                    Text("还没有漫画源。点右上角的 + 从订阅或链接添加。")
                }
            }
        }
        .navigationTitle("漫画源")
        .navigationDestination(for: PluginRecord.self) { SourceDetailView(source: $0) }
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("添加", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button { restoreCookies = false; pickingBackup = true } label: {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                    Button { restoreCookies = true; pickingBackup = true } label: {
                        Label("导入备份并恢复登录状态", systemImage: "key")
                    }
                    Divider()
                    Button { Task { await exportBackup() } } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                    Button { showLogs = true } label: {
                        Label("源日志", systemImage: "text.alignleft")
                    }
                    Divider()
                    Button { showAI = true } label: {
                        Label("AI 供应商", systemImage: "sparkles")
                    }
                } label: {
                    Label("导入备份", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddSourceView() }
        .fileImporter(isPresented: $pickingBackup, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await importBackup(url) }
            case .failure(let failure):
                notice = Notice(title: "导入失败", text: failure.localizedDescription)
            }
        }
        .sheet(isPresented: $showLogs) { SourceLogView() }
        .sheet(isPresented: $showAI) {
            MagpieProvidersView(accounts: magpie, showsClose: true)
        }
        .sheet(item: $exported) { file in
            // The share sheet saves it to Files, mails it, or anything else
            // the user has: an export is a document, not a private format.
            ShareSheet(url: file.url)
        }
        .alert(notice?.title ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        ), presenting: notice) { _ in
            Button("好") { notice = nil }
        } message: { Text($0.text) }
        .refreshable { await library.refresh() }
    }

    /// Reads a `.venera` file through Core and lands what it holds here.
    /// The file has to be copied out of its security scope first: Core opens
    /// a path, and a document picker URL is only readable inside the scope.
    private func importBackup(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "nekularity-\(UUID().uuidString).venera")
        do {
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: url, to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let plan = try await library.core.planBackup(
                path: tmp.path,
                tempDir: tmp.deletingLastPathComponent().path,
                knownKeys: library.sources.map(\.key),
                includeCookies: restoreCookies)
            // Only hand the jars over when the user chose cookies: an import that
            // silently wrote credentials would be worse than one that skipped them.
            let result = await BackupImporter().apply(
                plan, library: library, shelf: shelf, searches: searches,
                jars: restoreCookies ? library.cookieJars : nil)
            var parts = [
                "源 \(result.sourcesInstalled) 个",
                "历史 \(result.historyAdded) 条",
                "收藏 \(result.favouritesAdded) 部",
                "搜索 \(result.searchesAdded) 条",
            ]
            if result.valuesRestored > 0 {
                parts.append("源数据 \(result.valuesRestored) 项")
            }
            if result.pagesAdded > 0 {
                parts.append("图片 \(result.pagesAdded) 张")
            }
            if result.pagesAlreadyKept > 0 {
                parts.append("图片已在书架 \(result.pagesAlreadyKept) 页")
            }
            if result.picturesSkipped > 0 || result.pagesSkipped > 0 {
                var line = "图片收藏跳过 \(result.picturesSkipped) 部"
                if result.pagesSkipped > 0 {
                    line += "、\(result.pagesSkipped) 页"
                }
                parts.append(line)
            }
            if result.cookiesAdded > 0 {
                parts.append("登录状态 \(result.cookiesAdded) 条")
            }
            if result.pendingRows > 0 {
                parts.append("\(result.pendingRows) 条待装源后再导")
            }
            if !result.sourcesFailed.isEmpty {
                parts.append("源失败 " + result.sourcesFailed.joined(separator: "、"))
            }
            notice = Notice(title: "导入结果", text: parts.joined(separator: ","))
        } catch {
            notice = Notice(title: "导入失败", text: error.localizedDescription)
        }
    }
}

/// A message shown in the single alert this screen owns.
/// One exported archive, so the share sheet can write it wherever the user says.
/// The file is written to the temporary directory: an export is a document, not
/// something this app keeps.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

extension SourcesView {
    /// Builds a .venera archive from the installed sources and this device's
    /// search history, then offers it to the share sheet.
    ///
    /// Cookies are not in it: Core leaves them out, because they are per-source
    /// credentials and an export is a file people mail to themselves.
    func exportBackup() async {
        do {
            // The store keeps the newest first; the archive expects oldest first.
            let data = try await library.core.exportBackup(
                searchHistory: searches.queries.reversed(),
                sourceKeys: library.comicSources.map(\.key))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nekularity-\(Self.stamp()).venera")
            try data.write(to: url, options: .atomic)
            exported = ExportFile(url: url)
        } catch {
            notice = Notice(title: "导出失败", text: error.localizedDescription)
        }
    }

    /// A file name that sorts by time and carries no spaces: 20261101-010203.
    static func stamp(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }
}

/// A share sheet for one file. SwiftUI's ShareLink needs a value known when the
/// view is built; here the file is made in response to a tap, so the controller
/// is presented directly.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private struct SourceRow: View {
    let source: PluginRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(source.name).font(.headline)
                if !source.enabled { Text("已停用").font(.caption).foregroundStyle(.secondary) }
            }
            Text("\(source.key) · v\(source.version)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SourceDetailView: View {
    let source: PluginRecord
    @Environment(SourceLibrary.self) private var library
    @State private var error: String?
    @State private var busy = false

    /// The live record, which changes after enabling or updating.
    private var current: PluginRecord { library.sources.first { $0.key == source.key } ?? source }

    var body: some View {
        Form {
            Section {
                LabeledContent("名称", value: current.name)
                LabeledContent("Key", value: current.key)
                LabeledContent("版本", value: current.version)
                LabeledContent("作者", value: authors)
                if let home = current.attribution?.homepage, let url = URL(string: home) {
                    Link(destination: url) { LabeledContent("主页", value: home) }
                } else {
                    LabeledContent("主页", value: "未提供")
                }
                if let origin = current.origin, !origin.isEmpty { LabeledContent("来源", value: origin).lineLimit(2) }
            }
            if let warnings = current.warnings, !warnings.isEmpty {
                Section("提示") { ForEach(warnings, id: \.self) { Text($0).font(.footnote) } }
            }
            Section {
                NavigationLink {
                    SourceSettingsView(source: current)
                } label: {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("source.settings")
                NavigationLink {
                    SourceFavoritesView(source: current)
                } label: {
                    Label("源收藏", systemImage: "heart")
                }
                .accessibilityIdentifier("source.favorites")
                Toggle("启用", isOn: Binding(get: { current.enabled }, set: { on in
                    Task { await run { try await library.setEnabled(current.key, on) } }
                }))
                if let origin = current.origin, let url = URL(string: origin), url.scheme?.hasPrefix("http") == true {
                    Button("从来源更新") {
                        Task { await run { try await library.install(from: url, indexURL: current.indexUrl.flatMap(URL.init(string:))) } }
                    }
                }
            }
        }
        .navigationTitle(current.name)
        .disabled(busy)
        .alert("操作失败", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("好") { error = nil }
        } message: { Text($0) }
    }

    private var authors: String {
        let names = (current.attribution?.authors ?? []).map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "未提供" : names.joined(separator: "、")
    }

    private func run(_ body: () async throws -> some Any) async {
        busy = true
        defer { busy = false }
        do { _ = try await body() } catch { self.error = error.localizedDescription }
    }
}

/// Add from an index (index.json) or a script URL.
private struct AddSourceView: View {
    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastIndexURL") private var indexText = ""
    @State private var scriptText = ""
    @State private var index: ComicIndex?
    @State private var indexURL: URL?
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/index.json", text: $indexText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("读取订阅") { Task { await loadIndex() } }.disabled(URL(string: indexText)?.host() == nil)
                } header: { Text("订阅") } footer: { Text("兼容 Venera 的 index.json。") }

                if let index, let indexURL {
                    Section("订阅中的源") {
                        ForEach(index.rows) { row in
                            IndexEntryRow(row: row, busy: busy == row.key) {
                                Task { await install(row.entry, from: indexURL) }
                            }
                        }
                    }
                    if let problems = index.problems, !problems.isEmpty {
                        Section("已跳过") {
                            ForEach(problems, id: \.index) { p in
                                Text("第 \(p.index + 1) 项\(p.key.map { "(\($0))" } ?? ""):\(p.reason)").font(.footnote)
                            }
                        }
                    }
                }

                Section("脚本链接") {
                    TextField("https://…/source.js", text: $scriptText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("安装") { Task { await installScript() } }.disabled(URL(string: scriptText)?.host() == nil)
                }
            }
            .navigationTitle("添加漫画源").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .disabled(busy == "index" || busy == "script")
            .overlay { if busy == "index" || busy == "script" { ProgressView() } }
            .alert("操作失败", isPresented: .constant(error != nil), presenting: error) { _ in
                Button("好") { error = nil }
            } message: { Text($0) }
        }
    }

    private func loadIndex() async {
        guard let url = URL(string: indexText.trimmingCharacters(in: .whitespaces)) else { return }
        busy = "index"
        defer { busy = nil }
        do {
            index = try await library.loadIndex(url)
            indexURL = url
        } catch { self.error = error.localizedDescription }
    }

    private func install(_ entry: IndexEntry, from url: URL) async {
        busy = entry.key
        defer { busy = nil }
        do {
            try await library.install(entry: entry, indexURL: url)
            index = try await library.loadIndex(url) // refresh statuses
        } catch { self.error = error.localizedDescription }
    }

    private func installScript() async {
        guard let url = URL(string: scriptText.trimmingCharacters(in: .whitespaces)) else { return }
        busy = "script"
        defer { busy = nil }
        do {
            try await library.install(from: url)
            scriptText = ""
        } catch { self.error = error.localizedDescription }
    }
}

private struct IndexEntryRow: View {
    let row: ComicIndex.Row
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                switch row.status {
                case "new": Button("安装", action: action).buttonStyle(.borderedProminent)
                case "update": Button("更新", action: action).buttonStyle(.bordered)
                case "installed": Text("已安装").font(.caption).foregroundStyle(.secondary)
                case "other": Text("已从其他订阅安装").font(.caption).foregroundStyle(.secondary)
                case "too-new": Text("需要更新 App").font(.caption).foregroundStyle(.orange)
                default: EmptyView()
                }
            }
        }
    }

    private var detail: String {
        var parts = ["v\(row.version)"]
        if let v = row.installedVersion, v != row.version { parts[0] = "v\(v) → v\(row.version)" }
        if let d = row.description, !d.isEmpty { parts.append(d) }
        return parts.joined(separator: " · ")
    }
}
