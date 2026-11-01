import NekularityKit
import SwiftUI

/// Arranging the home screen: order, visibility, and sections taken from sources.
///
/// The second half is the point. A source that declares a 推荐 or 排行 page can
/// be put on the home screen here, which is how the home reads plugin content
/// rather than only local records.
struct HomeEditorView: View {
    @Environment(HomeLayout.self) private var layout
    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false

    private var hiddenTemplates: [HomeBlock.Template] {
        HomeBlock.Template.allCases.filter { template in
            layout.blocks.first { $0.id == "template:\(template.rawValue)" }?.enabled != true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("卡片") {
                    ForEach(layout.blocks) { block in
                        row(block)
                    }
                    .onMove { from, to in layout.move(from: from, to: to) }
                }

                if !hiddenTemplates.isEmpty {
                    Section("隐藏的卡片") {
                        ForEach(hiddenTemplates) { template in
                            Button {
                                layout.setEnabled(template, true)
                            } label: {
                                Label(template.title, systemImage: template.symbol)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        picking = true
                    } label: {
                        Label("从源添加分区", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("editor.addSource")
                } footer: {
                    Text("源声明的推荐、排行、分类都能作为首页卡片；取的是「浏览」里同一个分区。")
                }
            }
            .navigationTitle("编辑首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .sheet(isPresented: $picking) {
                SourcePickerView { ref in layout.add(ref) }
                    .environment(library)
            }
        }
    }

    private func row(_ block: HomeBlock) -> some View {
        HStack(spacing: 10) {
            Image(systemName: block.symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                if let subtitle = block.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !block.enabled {
                Text("隐藏").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            if case .source = block.kind {
                Button("删除", role: .destructive) { layout.remove(block) }
            } else {
                Button("隐藏") { layout.setEnabled(template(of: block), false) }
            }
        }
    }

    private func template(of block: HomeBlock) -> HomeBlock.Template {
        if case .template(let template) = block.kind { return template }
        return .history
    }
}

/// Picks a source, then one of the browse pages it declares.
struct SourcePickerView: View {
    let add: (HomeBlock.SourceRef) -> Void
    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: PluginRecord?
    @State private var pages: [ExplorePage] = []
    @State private var failure: String?
    @State private var loading = false

    private var sources: [PluginRecord] { library.comicSources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            Group {
                if let chosen {
                    pageList(chosen)
                } else {
                    sourceList
                }
            }
            .navigationTitle(chosen?.name ?? "选择源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if chosen != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("返回") { chosen = nil; pages = [] }
                    }
                }
            }
        }
    }

    private var sourceList: some View {
        List {
            if sources.isEmpty {
                ContentUnavailableView("没有可用的漫画源", systemImage: "puzzlepiece.extension")
            }
            ForEach(sources) { source in
                Button(source.name) { Task { await open(source) } }
            }
        }
    }

    private func pageList(_ source: PluginRecord) -> some View {
        List {
            if loading { ProgressView() }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                Button {
                    add(HomeBlock.SourceRef(key: source.key, sourceName: source.name,
                                            index: index, title: page.title))
                    dismiss()
                } label: {
                    HStack {
                        Text(page.title)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private func open(_ source: PluginRecord) async {
        chosen = source
        loading = true
        defer { loading = false }
        do {
            pages = try await library.core.explorePages(key: source.key)
            if pages.isEmpty { failure = "这个源没有声明浏览分区" }
        } catch {
            failure = CoreError.readable(error.localizedDescription)
        }
    }
}
