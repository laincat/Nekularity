import NekularityKit
import SwiftUI

/// System tabs own navigation material, safe areas and each section's lifetime.
/// Search uses the system search role rather than a second custom floating bar.
struct RootView: View {
    /// Magpie accounts are a plain class, not an Observable one, so they are
    /// passed down rather than put in the SwiftUI environment.
    let magpie: MagpieAccounts
    @Environment(ThemeStore.self) private var themes
    @Environment(DownloadStore.self) private var downloads
    @State private var section = Section.discover
    /// One Live Activity for the whole app: the island tells one story at a time.
    @State private var activityBridge = DownloadActivityBridge()

    enum Section: Hashable {
        case discover, mine, library, settings, search
    }

    private var accent: Color { Color(hex: themes.active.accent) ?? .accentColor }

    var body: some View {
        TabView(selection: $section) {
            Tab("发现", systemImage: "sparkles", value: Section.discover) {
                DiscoverView()
            }
            Tab("我的", systemImage: "person.crop.circle", value: Section.mine) {
                MineView()
            }
            Tab("资源库", systemImage: "archivebox", value: Section.library) {
                LibraryView(magpie: magpie)
            }
            Tab("设置", systemImage: "gearshape", value: Section.settings) {
                SettingsView(magpie: magpie)
            }
            Tab(value: Section.search, role: .search) {
                NavigationStack { SearchView() }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
        }
        .tint(accent)
        // The theme answers with three states; only the view knows how to turn
        // them into a SwiftUI value, which is why this mapping stays here.
        .preferredColorScheme(themes.active.appearance.colorScheme)
        // The signature changes on every page written and when a chapter starts or
        // ends, which is exactly when the island has something to say.
        .onChange(of: downloads.activitySignature) { _, _ in
            Task { await activityBridge.sync(downloads) }
        }
        .task { await activityBridge.sync(downloads) }
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
            do {
                let loaded = try await loader?.image(key, maxPixel: maxPixel).image
                guard !Task.isCancelled else { return }
                image = loaded
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}

private extension ThemeAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
