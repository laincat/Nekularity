import Foundation

/// One row of the provider list.
public struct MagpieProviderRow: Identifiable, Sendable, Hashable {
    public var provider: String
    public var name: String
    public var version: String
    /// Whether the package's plugin declares a sign-in at all.
    public var hasSignIn: Bool
    /// Whether this device holds a sign-in for it.
    public var signedIn: Bool
    public var methods: [String]

    public var id: String { provider }
}

/// The provider list: what is installed, who is signed in, and the runner for
/// each package.
///
/// Runners are kept, not rebuilt per call: loading a package compiles it, and
/// rebuilding on every tap would make the list feel broken. They are closed when
/// a package is removed or the account signed out.
public final class MagpieAccounts: @unchecked Sendable {
    /// Builds a runner for a package's files. Core's own factory in the app; a
    /// stub in tests.
    public typealias RunnerFactory = @Sendable (String, [String: Data]) throws -> MagpieRunner

    private let packages: MagpiePackageStore
    private let auth: MagpieAuthStore
    private let makeRunner: RunnerFactory
    private let lock = NSLock()
    private var runners: [String: MagpieRunner] = [:]

    public init(packages: MagpiePackageStore, auth: MagpieAuthStore, makeRunner: @escaping RunnerFactory) {
        self.packages = packages
        self.auth = auth
        self.makeRunner = makeRunner
    }

    /// What to show. A package whose sign-in cannot be read is listed as not
    /// signed in rather than dropped: the user installed it, and hiding it
    /// would look like the install failed.
    public func rows() throws -> [MagpieProviderRow] {
        try packages.list().map { package in
            let runner = try? runner(for: package.provider)
            let spec = try? runner?.auth(provider: package.provider)
            let signedIn = (try? auth.loadAuthJSON(provider: package.provider)) ?? nil != nil
            return MagpieProviderRow(
                provider: package.provider,
                name: package.name,
                version: package.version,
                hasSignIn: (spec?.methods.isEmpty == false),
                signedIn: signedIn,
                methods: spec?.methods.map(\.label) ?? []
            )
        }
    }

    /// Installs a package from a folder and loads it once, so a broken package
    /// fails now rather than on the first sign-in.
    @discardableResult
    public func install(provider: String, folder: URL) throws -> MagpieProviderRow {
        let files = try MagpiePackageReader.files(from: folder)
        guard MagpiePackageReader.looksLikePackage(files: files) else {
            throw MagpiePackageReader.Rejection("包里没有可加载的入口(需要 exports[./server]、main 或 index 文件)")
        }
        // Core is the authority on whether this package can run: it compiles the
        // package before anything is stored, so a rejected package leaves no
        // half-installed row behind.
        let runner = try makeRunner(provider, files)
        let spec = try runner.auth(provider: provider)
        let package = try packages.install(provider: provider, files: files)
        let previous = lock.withLock { () -> MagpieRunner? in
            let old = runners[provider]
            runners[provider] = runner
            return old
        }
        previous?.close()
        return MagpieProviderRow(
            provider: provider,
            name: package.name,
            version: package.version,
            hasSignIn: (spec?.methods.isEmpty == false),
            signedIn: (try auth.loadAuthJSON(provider: provider)) != nil,
            methods: spec?.methods.map(\.label) ?? []
        )
    }

    /// Installs from a folder without being told which provider it serves: the
    /// package's own plugin says so, and that id is what the account is stored
    /// under. Asking the user to type it would only invite a typo that looks
    /// like a broken package.
    @discardableResult
    public func install(folder: URL) throws -> MagpieProviderRow {
        let files = try MagpiePackageReader.files(from: folder)
        guard MagpiePackageReader.looksLikePackage(files: files) else {
            throw MagpiePackageReader.Rejection("包里没有可加载的入口(需要 exports[./server]、main 或 index 文件)")
        }
        // The id is only known after the package runs, so it is loaded under the
        // folder's name first and re-keyed once the plugin names itself.
        let provisional = folder.lastPathComponent
        let runner = try makeRunner(provisional, files)
        let spec = try runner.auth(provider: provisional)
        guard let provider = spec?.provider, !provider.isEmpty else {
            runner.close()
            throw MagpieError("这个插件没有声明 auth.provider,无法作为供应商使用")
        }
        let package = try packages.install(provider: provider, files: files)
        let previous = lock.withLock { () -> MagpieRunner? in
            let old = runners[provider]
            runners[provider] = runner
            return old
        }
        previous?.close()
        return MagpieProviderRow(
            provider: provider,
            name: package.name,
            version: package.version,
            hasSignIn: (spec?.methods.isEmpty == false),
            signedIn: (try auth.loadAuthJSON(provider: provider)) != nil,
            methods: spec?.methods.map(\.label) ?? []
        )
    }

    public func remove(provider: String) throws {
        let runner = lock.withLock { runners.removeValue(forKey: provider) }
        runner?.close()
        try auth.remove(provider: provider)
        try packages.remove(provider: provider)
    }

    public func signOut(provider: String) throws {
        let runner = lock.withLock { runners[provider] }
        try runner?.signOut(provider: provider)
        try auth.remove(provider: provider)
    }

    /// The runner for a package, created and cached on first use.
    public func runner(for provider: String) throws -> MagpieRunner {
        if let existing = lock.withLock({ runners[provider] }) { return existing }
        guard let files = try packages.files(provider: provider) else {
            throw MagpieError("这个供应商还没有安装")
        }
        let runner = try makeRunner(provider, files)
        lock.withLock { runners[provider] = runner }
        return runner
    }

    /// A sign-in for one provider, using the cached runner.
    public func makeSignIn(provider: String, inputs: [String: String] = [:]) throws -> MagpieSignIn {
        try runner(for: provider).makeSignIn(provider: provider, inputs: inputs)
    }

    public func usageJSON(provider: String) throws -> String {
        try runner(for: provider).usage(provider: provider)
    }
}
