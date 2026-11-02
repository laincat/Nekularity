import Foundation

/// A theme: the colours and shapes a screen draws with.
///
/// A theme is data, not code, so one can be written by hand, shared as a file
/// and installed without rebuilding the app. Only the tokens a screen actually
/// supports are here: a theme that promised to restyle every control would be a
/// theme that mostly did not.
public struct Theme: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Accent, as `#RRGGBB`.
    public var accent: String
    /// Page background; nil keeps the system's.
    public var background: String?
    /// Card and sheet surface; nil keeps the system's.
    public var surface: String?
    /// Corner radius for cards, chips and sheets.
    public var radius: Double
    /// Forces light or dark; nil follows the system.
    public var dark: Bool?
    /// Author, shown in the picker. Optional because most themes have none.
    public var author: String?

    public init(id: String, name: String, accent: String, background: String? = nil,
                surface: String? = nil, radius: Double = 12, dark: Bool? = nil,
                author: String? = nil) {
        self.id = id
        self.name = name
        self.accent = accent
        self.background = background
        self.surface = surface
        self.radius = radius
        self.dark = dark
        self.author = author
    }
}

extension Theme {
    /// Whether text drawn on `accent` should be black rather than white.
    ///
    /// A theme's accent is a hex string from a file, so it can be anything: the
    /// shipped and imported accents can both benefit from dark text.
    /// White on a pale accent is unreadable and no screenshot catches it because
    /// it only happens with a theme nobody installed yet.
    public var accentTextIsDark: Bool {
        guard let rgb = Self.components(of: accent) else { return false }
        // White only when it is still readable. The shipped accents all clear this
        // (iOS blue is 3.44:1, above the 3:1 large-text floor), and flipping them to
        // black because black scores a little higher would restyle the whole app to
        // fix a case that is not broken. Below the floor white is genuinely unreadable
        // and dark text wins.
        return Self.contrast(Self.luminance(rgb), 1) < 3
    }

    /// Contrast ratio between two relative luminances.
    static func contrast(_ a: Double, _ b: Double) -> Double {
        let (hi, lo) = a > b ? (a, b) : (b, a)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Parses `#RRGGBB`, with or without the hash.
    static func components(of hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    /// Relative luminance, as WCAG defines it.
    static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }
}

/// Themes that ship with the app.
public enum BuiltinThemes {
    /// The system's own colours: no accent override, no forced scheme.
    public static let system = Theme(id: "system", name: "跟随系统", accent: "#0A84FF", radius: 12)
    /// Only the system's own look ships. Everything else is content someone installs:
    /// a palette written by hand here is a palette nobody asked for, and the two that
    /// did ship — Miuix and Miuix dark — were never used.
    public static let all = [system]
}

/// Installed themes plus which one is active.
///
/// Installed themes are files: `Themes/<id>.json` under Application Support.
/// That is what makes a theme shareable — one JSON file, opened from Files,
/// kept, and picked in settings.
@MainActor
@Observable
public final class ThemeStore {
    public private(set) var themes: [Theme] = []
    public private(set) var active: Theme = BuiltinThemes.system
    public private(set) var failure: String?

    private let directory: URL
    private let defaults: UserDefaults

    public init(directory: URL, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        reload()
    }

    public var all: [Theme] { BuiltinThemes.all + themes.filter { theme in
        !BuiltinThemes.all.contains(where: { $0.id == theme.id })
    }}

    public func select(_ theme: Theme) {
        active = theme
        defaults.set(theme.id, forKey: "theme")
    }

    /// Installs a theme file. The id comes from the file, so installing the same
    /// theme twice replaces it rather than piling up.
    public func install(data: Data) throws {
        let theme = try JSONDecoder().decode(Theme.self, from: data)
        guard !theme.id.isEmpty, !theme.name.isEmpty else {
            throw CoreError("主题缺少 id 或 name")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(safe(theme.id)).json")
        try data.write(to: file, options: .atomic)
        reload()
    }

    public func remove(_ theme: Theme) {
        guard !BuiltinThemes.all.contains(where: { $0.id == theme.id }) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: "\(safe(theme.id)).json"))
        if active.id == theme.id { select(BuiltinThemes.system) }
        reload()
    }

    private func reload() {
        failure = nil
        var found: [Theme] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            do {
                found.append(try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file)))
            } catch {
                // One bad file must not hide the good ones; it is reported when the
                // user asks to install, and skipped here.
                continue
            }
        }
        themes = found.sorted { $0.name < $1.name }
        let wanted = defaults.string(forKey: "theme") ?? BuiltinThemes.system.id
        active = all.first { $0.id == wanted } ?? BuiltinThemes.system
    }

    /// Installs a theme from a link.
    ///
    /// The same file a person would import by hand, fetched instead of picked. The
    /// fetch is passed in rather than done here: the kit has no transport of its own,
    /// and a test should not need a network to prove what this does with an answer.
    public func install(from url: URL,
                        fetch: @Sendable (URL) async throws -> Data) async throws {
        let data = try await fetch(url)
        try install(data: data)
    }

    /// A file name that cannot escape the directory, since the id comes from a
    /// file someone else wrote.
    private func safe(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}
