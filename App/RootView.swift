import SwiftUI
import NekularityKit

struct RootView: View {
    /// Magpie accounts are a plain class, not an Observable one, so they are
    /// passed down rather than put in the SwiftUI environment.
    let magpie: MagpieAccounts
    @Environment(ThemeStore.self) private var themes

    var body: some View {
        // Four tabs, matching the shape the user asked for: a home they arrange,
        // their own calendar, the sources, and settings. Search, reading and
        // video are reached from the home screen rather than taking tabs — a
        // sixth tab is how the bar folds entries into 更多.
        TabView {
            Tab("发现", systemImage: "sparkles") { DiscoverView() }
            Tab("我的", systemImage: "person.crop.circle") { MineView() }
            Tab("资源库", systemImage: "archivebox") { LibraryView() }
            Tab("设置", systemImage: "gearshape") { SettingsView(magpie: magpie) }
        }
        // The theme is applied once, here, so every screen inherits it: an
        // accent colour that only some views used would look like a bug.
        .tint(Color(hex: themes.active.accent) ?? .accentColor)
        .preferredColorScheme(themes.active.dark == nil ? nil : (themes.active.dark! ? .dark : .light))
        .background(Color(hex: themes.active.background ?? "") ?? Color(.systemBackground))
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
