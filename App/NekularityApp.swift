import Foundation
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
                    RootView(magpie: env.magpie)
                        .environment(env.library)
                        .environment(env.prompts)
                        .environment(env.shelf)
                        .environment(env.searches)
                        .environment(env.downloads)
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
        /// Installed AI provider packages and their accounts, separate from
        /// comic sources in every way.
        let magpie: MagpieAccounts
        let downloads: DownloadStore
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
            let config = CoreConfig(appVersion: Self.sourceLevel, locale: Locale.current.identifier, defaultUserAgent: ua,
                                    memoryLimitBytes: 256 << 20)
            // Core start-up parses and compiles the prelude; keep it off the
            // main thread.
            let core = try await Task.detached { try CoreClient(config: config, host: host) }.value
            let prompts = PromptCenter(cookies: cookies, userAgent: ua)
            host.ui = prompts
            let library = SourceLibrary(core: core, cookieJars: cookies)
            await library.restore()
            let keychain = KeychainMagpieAuthStore()
            let magpieDir = support.appending(path: "Magpie", directoryHint: .isDirectory)
            let magpie = MagpieAccounts(
                packages: MagpiePackageStore(directory: magpieDir),
                auth: keychain,
                options: MagpieOptionStore(directory: magpieDir),
                makeRunner: { provider, files in
                    // `install` loads the package and then hands Core its
                    // provider, which is the call Core builds the package's
                    // client bridge from. Doing it here rather than on the first
                    // sign-in is what keeps `client.auth` from being missing.
                    //
                    // The chunked transport lets a package's reply arrive as the
                    // server writes it, so a chat is drawn while it is still
                    // being written.
                    let runner = try MagpieRunner(
                        core: CoreMagpie(host: host, stream: CoreStreamHost(transport: transport)),
                        store: keychain)
                    try runner.install(provider: provider, files: files)
                    return runner
                },
                // Archive install needs a Core that is not bound to a package;
                // MagpieAccounts closes it after expanding.
                makeCore: { try CoreMagpie(host: host, stream: CoreStreamHost(transport: transport)) })
            // Downloads are asked before the network, so a kept chapter opens
            // with no connection at all.
            let downloads = DownloadStore(root: support.appending(path: "Downloads", directoryHint: .isDirectory))
            state = .ready(Environment(
                library: library,
                images: ImageLoader(core: core, offline: { key in
                    await downloads.bytes(for: key)
                }),
                downloads: downloads,
                prompts: prompts,
                shelf: ShelfStore(directory: support),
                searches: SearchHistoryStore(directory: support),
                magpie: magpie))
        } catch {
            started = false
            state = .failed(error.localizedDescription)
        }
    }

    /// The source API level, named once in the kit so a test can check it.
    static let sourceLevel = SourceAPI.level

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
