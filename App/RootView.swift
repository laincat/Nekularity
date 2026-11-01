import NekularityKit
import SwiftUI

/// The shell: four sections over one shared canvas, with a floating bar.
///
/// The reference app floats a pill-shaped bar with a round search button beside
/// it, and blurs a two-tone gradient behind everything. A stock `TabView` cannot
/// draw that, so the bar is here and the sections are plain views. The section
/// buttons keep identifiers because the interface tests tap them.
struct RootView: View {
    /// Magpie accounts are a plain class, not an Observable one, so they are
    /// passed down rather than put in the SwiftUI environment.
    let magpie: MagpieAccounts
    @Environment(ThemeStore.self) private var themes
    @Environment(\.colorScheme) private var scheme

    @State private var section = Section.discover
    @State private var searching = false

    enum Section: String, CaseIterable, Identifiable {
        case discover, mine, library, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .discover: "发现"
            case .mine: "我的"
            case .library: "资源库"
            case .settings: "设置"
            }
        }
        var symbol: String {
            switch self {
            case .discover: "sparkles"
            case .mine: "person.crop.circle"
            case .library: "archivebox"
            case .settings: "gearshape"
            }
        }
    }

    private var accent: Color { Color(hex: themes.active.accent) ?? .accentColor }

    var body: some View {
        ZStack {
            Color.canvas(accent, dark: themeIsDark).ignoresSafeArea()

            Group {
                switch section {
                case .discover: DiscoverView()
                case .mine: MineView()
                case .library: LibraryView()
                case .settings: SettingsView(magpie: magpie)
                }
            }
            .safeAreaInset(edge: .bottom) { bar }
        }
        .tint(accent)
        .preferredColorScheme(themes.active.dark == nil ? nil : (themes.active.dark! ? .dark : .light))
        // Presented, not pushed: the sections own their own navigation stacks,
        // and a destination registered here would sit outside all of them.
        .sheet(isPresented: $searching) { NavigationStack { SearchView() } }
    }

    private var themeIsDark: Bool {
        if let forced = themes.active.dark { return forced }
        return scheme == .dark
    }

    /// The floating bar: four sections in one capsule, and search in its own.
    private var bar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol).font(.system(size: 17, weight: .medium))
                            Text(item.title).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(section == item ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                        .background {
                            if section == item {
                                Capsule().fill(accent.opacity(0.16))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab.\(item.rawValue)")
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            // Clip the whole strip: a selected capsule is drawn wider than its
            // slot at the edge and would otherwise slide under the search button.
            .clipShape(Capsule())

            Button {
                searching = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tab.search")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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
