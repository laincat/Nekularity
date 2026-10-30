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
    /// How many switches the plugin declares; zero means no options screen.
    public var optionCount: Int

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
    /// A Core that is not bound to a package, used to expand archives.
    public typealias CoreFactory = @Sendable () throws -> any MagpieRunner.Core

    private let packages: MagpiePackageStore
    private let auth: MagpieAuthStore
    private let makeRunner: RunnerFactory
    private let makeCore: CoreFactory?
    /// The user's choices for the plugins' own switches, when the app keeps them.
    public let options: MagpieOptionStore?
    private let lock = NSLock()
    private var runners: [String: MagpieRunner] = [:]
    /// What each package's plugin declared, kept so a list refresh does not
    /// evaluate every package again: each evaluation starts a JavaScript
    /// runtime, and a list with ten providers would pay for ten.
    private var specs: [String: MagpieAuthSpec] = [:]

    public init(
        packages: MagpiePackageStore,
        auth: MagpieAuthStore,
        options: MagpieOptionStore? = nil,
        makeRunner: @escaping RunnerFactory,
        makeCore: CoreFactory? = nil
    ) {
        self.packages = packages
        self.auth = auth
        self.options = options
        self.makeRunner = makeRunner
        self.makeCore = makeCore
    }

    /// What to show. A package whose sign-in cannot be read is listed as not
    /// signed in rather than dropped: the user installed it, and hiding it
    /// would look like the install failed.
    public func rows() throws -> [MagpieProviderRow] {
        try packages.list().map { package in
            // A stored declaration is enough for the row; only packages installed
            // before it was recorded need their runtime started again.
            if let json = package.specJSON,
               let spec = try? JSONDecoder().decode(MagpieAuthSpec.self, from: Data(json.utf8)) {
                return row(for: package, spec: spec)
            }
            let spec = specCache(provider: package.provider) {
                guard let runner = try? runner(for: package.provider) else { return nil }
                return try? runner.auth(provider: package.provider)
            }
            // A package installed before the declaration was recorded pays for
            // one evaluation, then stops paying.
            if let spec, let encoded = try? JSONEncoder().encode(spec) {
                var updated = package
                updated.specJSON = String(decoding: encoded, as: UTF8.self)
                try? packages.replace(updated)
            }
            return row(for: package, spec: spec)
        }
    }

    /// The declaration as text, for storing beside the package. `nil` when the
    /// plugin declared nothing, which is a package that cannot be a provider.
    private func declarationJSON(_ spec: MagpieAuthSpec?) -> String? {
        guard let spec, let encoded = try? JSONEncoder().encode(spec) else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// One row, from a package and whatever its plugin declared. Kept in one
    /// place so a stored declaration and a freshly evaluated one cannot produce
    /// different lists.
    private func row(for package: MagpiePackage, spec: MagpieAuthSpec?) -> MagpieProviderRow {
        // `try?` around a throwing load, then compare with nil: written this way
        // because `?? nil != nil` binds the comparison first and does not mean
        // what it looks like.
        let stored = try? auth.loadAuthJSON(provider: package.provider)
        return MagpieProviderRow(
            provider: package.provider,
            name: package.name,
            version: package.version,
            hasSignIn: (spec?.methods.isEmpty == false),
            signedIn: (stored ?? nil) != nil,
            methods: spec?.methods.map(\.label) ?? [],
            optionCount: spec?.options.count ?? 0
        )
    }

    /// Installs a package from an archive the user downloaded (zip or tar.gz).
    @discardableResult
    public func install(provider: String, archive: URL) throws -> MagpieProviderRow {
        let files = try archiveFiles(from: archive)
        return try install(provider: provider, files: files)
    }

    /// Installs from a folder and loads it once, so a broken package fails now
    /// rather than on the first sign-in.
    @discardableResult
    public func install(provider: String, folder: URL) throws -> MagpieProviderRow {
        try install(provider: provider, files: try MagpiePackageReader.files(from: folder))
    }

    @discardableResult
    private func install(provider: String, files: [String: Data]) throws -> MagpieProviderRow {
        guard MagpiePackageReader.looksLikePackage(files: files) else {
            throw MagpiePackageReader.Rejection("包里没有可加载的入口(需要 exports[./server]、main 或 index 文件)")
        }
        // Core is the authority on whether this package can run: it compiles the
        // package before anything is stored, so a rejected package leaves no
        // half-installed row behind.
        let runner = try makeRunner(provider, files)
        let spec = try runner.auth(provider: provider)
        // The package has to be the one it claims to be: storing it under
        // another id would send its sign-in to the wrong account.
        guard let declared = spec?.provider, declared == provider else {
            runner.close()
            throw MagpieError("这个插件声明的是 \(spec?.provider ?? "（没有声明）"),不是 \(provider)")
        }
        // Remembering what the plugin declared keeps the list from starting a
        // runtime per provider on every refresh. It goes in with the files, in
        // one write, rather than as a second pass over the whole table.
        let package = try packages.install(provider: provider, files: files,
                                           specJSON: declarationJSON(spec))
        let previous = lock.withLock { () -> MagpieRunner? in
            let old = runners[provider]
            runners[provider] = runner
            if let spec { specs[provider] = spec }
            return old
        }
        previous?.close()
        return MagpieProviderRow(
            provider: provider,
            name: package.name,
            version: package.version,
            hasSignIn: (spec?.methods.isEmpty == false),
            signedIn: (try auth.loadAuthJSON(provider: provider)) != nil,
            methods: spec?.methods.map(\.label) ?? [],
            optionCount: spec?.options.count ?? 0
        )
    }

    /// Installs an archive without being told which provider it serves.
    @discardableResult
    public func install(archive: URL) throws -> MagpieProviderRow {
        let files = try archiveFiles(from: archive)
        return try install(files: files, provisional: archive.deletingPathExtension().lastPathComponent)
    }

    /// Installs from a folder without being told which provider it serves: the
    /// package's own plugin says so, and that id is what the account is stored
    /// under. Asking the user to type it would only invite a typo that looks
    /// like a broken package.
    @discardableResult
    public func install(folder: URL) throws -> MagpieProviderRow {
        try install(files: try MagpiePackageReader.files(from: folder), provisional: folder.lastPathComponent)
    }

    @discardableResult
    private func install(files: [String: Data], provisional: String) throws -> MagpieProviderRow {
        guard MagpiePackageReader.looksLikePackage(files: files) else {
            throw MagpiePackageReader.Rejection("包里没有可加载的入口(需要 exports[./server]、main 或 index 文件)")
        }
        // The id is only known after the package runs, so it is loaded under the
        // folder's name first and re-keyed once the plugin names itself.
        let runner = try makeRunner(provisional, files)
        let spec = try runner.auth(provider: provisional)
        guard let provider = spec?.provider, !provider.isEmpty else {
            runner.close()
            throw MagpieError("这个插件没有声明 auth.provider,无法作为供应商使用")
        }
        let package = try packages.install(provider: provider, files: files,
                                           specJSON: declarationJSON(spec))
        let previous = lock.withLock { () -> MagpieRunner? in
            let old = runners[provider]
            runners[provider] = runner
            if let spec { specs[provider] = spec }
            return old
        }
        previous?.close()
        return row(for: package, spec: spec)
    }

    public func remove(provider: String) throws {
        let runner = lock.withLock { () -> MagpieRunner? in
            specs[provider] = nil
            return runners.removeValue(forKey: provider)
        }
        runner?.close()
        try auth.remove(provider: provider)
        try packages.remove(provider: provider)
    }

    public func signOut(provider: String) throws {
        let runner = lock.withLock { runners[provider] }
        try runner?.signOut(provider: provider)
        try auth.remove(provider: provider)
    }

    /// Expands an archive with a Core that is thrown away afterwards: extraction
    /// does not depend on a package, and closing it keeps one install from
    /// leaving a JavaScript runtime behind.
    private func archiveFiles(from archive: URL) throws -> [String: Data] {
        // An archive is read whole, so a mis-picked video would be loaded into
        // memory before Core ever sees it. Twice the extracted limit is already
        // far more than a provider package needs.
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * MagpiePackageReader.maxTotalBytes else {
            throw MagpiePackageReader.Rejection("这个文件有 \(size / 1024 / 1024) MiB,不像是插件包")
        }
        let data = try Data(contentsOf: archive)
        let core = try archiveReader()
        defer { core.close() }
        return try MagpiePackageReader.files(fromArchive: data, core: core)
    }

    /// A Core whose only job is to expand an archive. Extraction does not depend
    /// on a loaded package, so this cannot disturb the runners already serving
    /// accounts; when the app did not supply one, installing from an archive says
    /// so instead of failing somewhere deeper.
    private func archiveReader() throws -> any MagpieRunner.Core {
        guard let makeCore else {
            throw MagpieError("这个构建不支持从压缩包安装,请解开后选文件夹")
        }
        return try makeCore()
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

    /// The declared spec, loaded once per provider: evaluating a package starts
    /// its JavaScript runtime, and a list refresh should not pay for that again.
    private func specCache(provider: String, load: () -> MagpieAuthSpec?) -> MagpieAuthSpec? {
        if let known = lock.withLock({ specs[provider] }) { return known }
        let spec = load()
        if let spec { lock.withLock { specs[provider] = spec } }
        return spec
    }
}
