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
    /// shipped ones are all dark enough for white text, and a pale one is not.
    /// White on a pale accent is unreadable and no screenshot catches it because
    /// it only happens with a theme nobody installed yet.
    public var accentTextIsDark: Bool {
        guard let rgb = Self.components(of: accent) else { return false }
        // WCAG contrast against black and against white; the larger one wins.
        let onBlack = (Self.luminance(rgb) + 0.05) / 0.05
        let onWhite = 1.05 / (Self.luminance(rgb) + 0.05)
        return onBlack > onWhite
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
    /// Soft, rounded and blue — the Miuix look, as tokens rather than code.
    public static let miuix = Theme(id: "miuix", name: "Miuix", accent: "#3482FF",
                                    background: "#F7F8FA", surface: "#FFFFFF", radius: 20)
    public static let miuixDark = Theme(id: "miuix-dark", name: "Miuix 深色", accent: "#6BA4FF",
                                        background: "#0F1115", surface: "#1A1D23", radius: 20, dark: true)
    public static let all = [system, miuix, miuixDark]
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

    /// A file name that cannot escape the directory, since the id comes from a
    /// file someone else wrote.
    private func safe(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}
