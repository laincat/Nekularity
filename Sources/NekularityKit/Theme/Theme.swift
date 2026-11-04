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

/// Where a theme file may come from.
///
/// A theme is only data, but the link is still an untrusted address fetched
/// over the network. HTTPS is required: plain HTTP would let anything on the
/// path replace what the app installs. A local file is a different entry point
/// (`install(data:)`) and is not covered by this rule.
public enum ThemeSource {
    /// A theme is a small JSON file. Anything past this is not a theme, and
    /// fetching it would spend the user's data for nothing.
    public static let maximumBytes = 1 << 20

    public static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw CoreError("主题链接必须是 https 地址")
        }
        guard url.host?.isEmpty == false else {
            throw CoreError("主题链接缺少主机名")
        }
    }

    /// Whether a redirect hop may be followed. Only HTTPS qualifies: `validate`
    /// sees the address the user typed, not where the server sends them next.
    public static func allowsRedirect(to url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    /// Fetches a theme without ever leaving HTTPS.
    ///
    /// URLSession follows redirects, so an HTTPS link that answers `302
    /// Location: http://…` would otherwise download the theme in the clear.
    /// A refused hop surfaces as the 3xx response itself, which the status
    /// check below rejects. `configuration` exists for tests, whose stub
    /// protocol cannot be installed into a session built here.
    public static func fetch(_ url: URL,
                             configuration: URLSessionConfiguration? = nil) async throws -> Data {
        try validate(url)
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        let redirects = HTTPSOnlyRedirects()
        let session = URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            // The delegate cancels a refused hop so the user does not wait for
            // the request timeout; report why instead of "cancelled".
            if redirects.refusedNonHTTPS {
                throw CoreError("主题链接重定向到了非 https 地址")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw CoreError("主题地址没有返回 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CoreError("主题地址返回了 HTTP \(http.statusCode)")
        }
        if http.expectedContentLength > Int64(maximumBytes) || data.count > maximumBytes {
            throw CoreError("主题文件超过 1 MiB")
        }
        return data
    }
}

/// Refuses any redirect that leaves HTTPS, so a plaintext hop cannot happen
/// inside a request whose original address passed `ThemeSource.validate`.
final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var refused = false

    /// True once a hop left HTTPS. `fetch` turns this into a message the user
    /// can act on rather than a generic "cancelled".
    var refusedNonHTTPS: Bool { lock.withLock { refused } }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard ThemeSource.allowsRedirect(to: request.url) else {
            lock.withLock { refused = true }
            completionHandler(nil)
            // Not following and then waiting for the timeout would make a
            // hostile redirect look like a slow server; stop now.
            task.cancel()
            return
        }
        completionHandler(request)
    }
}

/// What a theme asks the interface to do about light and dark.
///
/// The model stores `dark: Bool?`, where nil means "follow the system". That
/// three-way answer used to live in a single line in the view, so nothing could
/// test it and a reader had to decode an optional inside a ternary.
public enum ThemeAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

extension Theme {
    /// This theme's answer, with nil resolved to `.system`.
    public var appearance: ThemeAppearance {
        switch dark {
        case .some(true): return .dark
        case .some(false): return .light
        case .none: return .system
        }
    }
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
        // Checked here rather than only in the screen: a second caller must not
        // be able to fetch a theme over plaintext by skipping the view's guard.
        try ThemeSource.validate(url)
        let data = try await fetch(url)
        try install(data: data)
    }

    /// A file name that cannot escape the directory, since the id comes from a
    /// file someone else wrote.
    private func safe(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}
