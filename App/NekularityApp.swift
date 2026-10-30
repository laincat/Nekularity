import NekularityKit
import Observation
import SwiftUI

@main
struct NekularityApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch app.state {
                case .starting:
                    ProgressView("正在启动…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("启动失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") { Task { await app.start() } }
                    }
                case .ready(let env):
                    RootView()
                        .environment(env.library)
                        .environment(env.prompts)
                        .environment(env.shelf)
                        .environment(env.searches)
                        .environment(\.imageLoader, env.images)
                        .sourcePrompts(env.prompts)
                }
            }
            .task { await app.start() }
        }
    }
}

/// Builds the Core environment once at launch.
@MainActor @Observable
final class AppModel {
    enum State {
        case starting
        case failed(String)
        case ready(Environment)
    }

    struct Environment {
        let library: SourceLibrary
        let images: ImageLoader
        let prompts: PromptCenter
        /// Reading history and favourites.
        let shelf: ShelfStore
        /// Keywords the reader searched for.
        let searches: SearchHistoryStore
    }

    var state: State = .starting
    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        state = .starting
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "Nekularity", directoryHint: .isDirectory)
            let store = try SourceStore(root: support)
            let cookies = CookieJars(file: support.appending(path: "cookies.json"))
            let ua = Self.userAgent
            let transport = URLSessionTransport(cookies: cookies, defaultUserAgent: ua)
            let host = CoreHost(store: store, cookies: cookies, transport: transport, log: { level, title, content in
                #if DEBUG
                print("[\(level)] \(title): \(content)")
                #endif
            })
            let config = CoreConfig(appVersion: Self.appVersion, locale: Locale.current.identifier, defaultUserAgent: ua,
                                    memoryLimitBytes: 256 << 20)
            // Core start-up parses and compiles the prelude; keep it off the
            // main thread.
            let core = try await Task.detached { try CoreClient(config: config, host: host) }.value
            let prompts = PromptCenter(cookies: cookies, userAgent: ua)
            host.ui = prompts
            let library = SourceLibrary(core: core)
            await library.restore()
            state = .ready(Environment(
                library: library,
                images: ImageLoader(core: core),
                prompts: prompts,
                shelf: ShelfStore(directory: support),
                searches: SearchHistoryStore(directory: support)))
        } catch {
            started = false
            state = .failed(error.localizedDescription)
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    /// A Safari-like User-Agent. Sites block unknown agents, and the
    /// verification WebView reports its own.
    static var userAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion)_\(os.minorVersion)"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(version) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(os.majorVersion).0 Mobile/15E148 Safari/604.1"
    }
}

extension EnvironmentValues {
    @Entry var imageLoader: ImageLoader? = nil
}
