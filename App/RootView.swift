import SwiftUI
import NekularityKit

struct RootView: View {
    var body: some View {
        // Five tabs, because the bar holds five: a sixth pushes the last ones
        // into 更多, and 漫画源 is where the source screens live. The AI
        // providers therefore sit behind 漫画源's toolbar rather than taking a
        // tab of their own.
        TabView {
            Tab("搜索", systemImage: "magnifyingglass") { SearchView() }
            Tab("浏览", systemImage: "square.grid.2x2") { BrowseView() }
            Tab("书架", systemImage: "books.vertical") { ShelfView() }
            Tab("视频", systemImage: "play.rectangle") { VideoView() }
            Tab("漫画源", systemImage: "puzzlepiece.extension") { SourcesView() }
        }
    }
}

/// A cover or page image loaded through the source's own request rules.
struct SourceImage: View {
    let key: ImageLoader.Key
    var maxPixel = 600
    var contentMode: ContentMode = .fill
    @Environment(\.imageLoader) private var loader
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary).imageScale(.large)
            } else {
                ProgressView()
            }
        }
        .task(id: key) {
            image = nil
            failed = false
            do { image = try await loader?.image(key, maxPixel: maxPixel).image } catch { failed = !Task.isCancelled }
        }
    }
}
