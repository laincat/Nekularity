import NekularityKit
import SwiftUI

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
