import NekularityKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Comics on this device: imported folders and `.cbz` archives.
///
/// It sits beside 漫画源 rather than inside it. A local comic has no script, no
/// network and no id to agree with a source on; putting it in the source list would
/// mean pretending it has those things.
struct LocalComicsView: View {
    @Environment(LocalComicStore.self) private var comics
    @State private var importing = false
    @State private var note: String?

    var body: some View {
        List {
            if comics.comics.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有本地漫画", systemImage: "folder.badge.plus")
                    } description: {
                        Text("导入一个图片文件夹,或一个 .cbz / .zip 压缩包。")
                    }
                }
            } else {
                Section("已导入") {
                    ForEach(comics.comics) { comic in
                        NavigationLink {
                            LocalComicReaderView(comic: comic)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comic.title).font(.body.weight(.medium))
                                Text("\(comic.pageCount) 页" + (comic.lastPage > 0 ? " · 停在第 \(comic.lastPage + 1) 页" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("local.comic.\(comic.id)")
                        .swipeActions {
                            Button("删除", role: .destructive) { comics.remove(comic) }
                        }
                    }
                }
            }
        }
        .navigationTitle("本地漫画")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("导入", systemImage: "plus") }
                    .accessibilityIdentifier("local.import")
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder, .zip, UTType(filenameExtension: "cbz") ?? .data],
                      allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let comic = try comics.importComic(at: url)
                note = "已导入《\(comic.title)》\(comic.pageCount) 页"
            } catch {
                note = error.localizedDescription
            }
        }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("好") { note = nil }
        }
    }
}

/// Reads one imported comic, page by page, and remembers where it stopped.
struct LocalComicReaderView: View {
    let comic: LocalComic
    @Environment(LocalComicStore.self) private var comics
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int

    init(comic: LocalComic) {
        self.comic = comic
        _page = State(initialValue: min(max(0, comic.lastPage), max(0, comic.pages.count - 1)))
    }

    var body: some View {
        Group {
            if comic.pages.isEmpty {
                ContentUnavailableView("这本没有页", systemImage: "photo.on.rectangle")
            } else {
                TabView(selection: $page) {
                    ForEach(Array(comic.pages.enumerated()), id: \.offset) { index, _ in
                        pageImage(index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(.black)
            }
        }
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(page + 1)/\(comic.pages.count)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("local.page")
            }
        }
        .onChange(of: page) { _, value in
            comics.mark(comic, page: value)
        }
        .onDisappear {
            comics.mark(comic, page: page)
        }
    }

    private func pageImage(_ index: Int) -> some View {
        let url = comics.pageURL(comic, index: index)
        return Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                // A page that will not decode says so on the page itself rather
                // than leaving a blank screen with nothing to explain it.
                ContentUnavailableView("这一页读不出来", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
