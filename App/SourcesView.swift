import SwiftUI
import NekularityKit

/// Installed sources, install from URL or index, and source details.
struct SourcesView: View {
    @Environment(SourceLibrary.self) private var library
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
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
                    }
                    .onDelete { offsets in
                        let keys = offsets.map { library.comicSources[$0].key }
                        Task {
                            for k in keys {
                                do { try await library.remove(k) } catch { self.error = error.localizedDescription }
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
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label("添加", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddSourceView() }
            .alert("操作失败", isPresented: .constant(error != nil), presenting: error) { _ in
                Button("好") { error = nil }
            } message: { Text($0) }
            .refreshable { await library.refresh() }
        }
    }
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
