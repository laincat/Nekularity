import SwiftUI
import NekularityKit

/// Vertical scrolling reader for one chapter, with previous/next chapter.
struct ReaderView: View {
    @State var route: ReaderRoute
    @Environment(SourceLibrary.self) private var library
    @Environment(ShelfStore.self) private var shelf
    @State private var images: [String] = []
    @State private var error: String?
    @State private var loading = true
    @State private var chromeHidden = false

    init(route: ReaderRoute) { _route = State(initialValue: route) }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                            ReaderPage(key: .init(source: route.source, url: url, comicID: route.comicID,
                                                  chapterID: route.chapterID, isThumbnail: false),
                                       width: geo.size.width, number: i + 1)
                        }
                        if !images.isEmpty { chapterFooter }
                    }
                }
                .onChange(of: route.index) { proxy.scrollTo("top") }
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("重试") { Task { await load() } } }
            }
        }
        .background(Color.black.opacity(0.03))
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(chromeHidden)
        .onTapGesture { withAnimation { chromeHidden.toggle() } }
        .task(id: route.index) { await load() }
    }

    private var chapterFooter: some View {
        HStack {
            if route.index > 0 {
                Button { route.index -= 1 } label: { Label("上一章", systemImage: "chevron.left") }
            }
            Spacer()
            if route.index + 1 < route.chapters.count {
                Button { route.index += 1 } label: { Label("下一章", systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("已是最后一章").foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func load() async {
        loading = true
        error = nil
        images = []
        defer { loading = false }
        do {
            images = try await library.core.chapterImages(key: route.source, comicID: route.comicID, chapterID: route.chapterID)
            if images.isEmpty { error = "这一章没有图片" }
            // Opening a chapter is what the shelf remembers.
            shelf.record(ShelfHistory(
                comic: ShelfComic(source: route.source, id: route.comicID,
                                  title: route.comicTitle.isEmpty ? route.title : route.comicTitle,
                                  author: route.author, cover: route.cover),
                chapter: route.title, chapterIndex: route.index))
        } catch {
            if (error as? CoreError)?.isCancelled != true { self.error = error.localizedDescription }
        }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/// One page. Until it loads it reserves a portrait-sized slot, so the
/// scroll position does not jump.
private struct ReaderPage: View {
    let key: ImageLoader.Key
    let width: CGFloat
    let number: Int
    @Environment(\.imageLoader) private var loader
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .accessibilityLabel("第 \(number) 页")
            } else {
                ZStack {
                    if failed {
                        Button { attempt += 1 } label: {
                            Label("第 \(number) 页加载失败,点按重试", systemImage: "arrow.clockwise")
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: width, height: width * 1.4)
            }
        }
        .task(id: TaskKey(key: key, attempt: attempt)) {
            failed = false
            do {
                image = try await loader?.image(key, maxWidth: Int(width * scale)).image
            } catch { failed = !Task.isCancelled }
        }
    }

    struct TaskKey: Hashable { let key: ImageLoader.Key; let attempt: Int }
}
