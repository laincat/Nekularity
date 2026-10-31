import Foundation

/// Runs one installed Magpie provider package for one account.
///
/// The package, its sign-in and its requests stay apart from comic sources:
/// Core reaches the network only through the client's `Host`, and the sign-in
/// is stored by this client, never by Core.
public final class MagpieRunner: @unchecked Sendable {
    /// The Core-side runner. A protocol rather than the generated type so the
    /// orchestration below can be tested without an xcframework.
    public protocol Core: AnyObject, Sendable {
        /// Expands a package archive into the file table `loadPackage` takes.
        /// Core owns extraction so the client does not reimplement the rules.
        func readPackageArchive(_ data: Data) throws -> String
        func loadPackage(filesJSON: String) throws
        func setAuth(provider: String, authJSON: String) throws
        func call(_ export: String, argJSON: String) throws -> String
        func savedAuthJSON() throws -> String
        func authJSON() throws -> String
        func authorize(methodIndex: Int, inputsJSON: String) throws -> String
        func poll(id: Int64) throws -> String
        func cancelSignIn(id: Int64) throws
        func usageJSON(provider: String) throws -> String
        func usageSummaryJSON(provider: String) throws -> String
        func modelsJSON() throws -> String
        func checkinJSON(provider: String) throws -> String
        func setPluginOptions(optionsJSON: String) throws
        func chatStart(model: String, messagesJSON: String, system: String, maxTokens: Int) throws -> String
        func chatNext(handle: Int64) throws -> String
        func chatCancel(handle: Int64)
        func close()
    }

    private let core: Core
    private let store: MagpieAuthStore
    private let lock = NSLock()
    private var closed = false

    public init(core: Core, store: MagpieAuthStore) {
        self.core = core
        self.store = store
    }

    deinit { close() }

    /// Ends the package's runtime. The runner must not be used afterwards.
    ///
    /// Idempotent on this side rather than relying on Core: a runner is closed
    /// when a package is removed and again when it is deallocated.
    public func close() {
        let already = lock.withLock { () -> Bool in
            let was = closed
            closed = true
            return was
        }
        if !already { core.close() }
    }

    /// Installs a package and hands it the account's stored sign-in.
    ///
    /// `files` are the package's own files, path to bytes. The caller has
    /// already unpacked any archive: this layer never trusts a path it did not
    /// see Core validate.
    public func install(provider: String, files: [String: Data]) throws {
        var encoded: [String: String] = [:]
        for (path, body) in files {
            encoded[path] = body.base64EncodedString()
        }
        let json = try Self.encode(encoded)
        try core.loadPackage(filesJSON: json)
        // Always, even with no account yet. Core installs the package's client
        // bridge while it builds the runtime, and it learns which provider it is
        // serving from this call: an install that waited for a stored sign-in
        // would leave the package unable to ask for one.
        let stored = try store.loadAuthJSON(provider: provider)
        try core.setAuth(provider: provider, authJSON: stored ?? "")
    }

    /// Stores the sign-in the package wrote back.
    ///
    /// Every path that can refresh a token ends here. Written as one function
    /// because the paths are easy to add and easy to forget: a refresh that only
    /// lands on the `call` path signs the user out on the next launch.
    private func persist(provider: String) {
        guard let saved = try? core.savedAuthJSON(), !saved.isEmpty, saved != "null" else { return }
        try? store.saveAuthJSON(provider: provider, json: saved)
    }

    /// Runs a hook exported by the package, returning its JSON answer.
    ///
    /// After the call the sign-in the package saved is stored again: a refresh
    /// happens inside a hook, and losing it would sign the user out on the next
    /// launch. The JSON text the package wrote is stored as it is.
    public func call(provider: String, export: String, argJSON: String = "") throws -> String {
        // `defer` because a hook that refreshed and then threw still refreshed.
        defer { persist(provider: provider) }
        return try core.call(export, argJSON: argJSON)
    }

    // MARK: Sign-in

    /// What the package's plugin offers.
    public func auth(provider: String) throws -> MagpieAuthSpec? {
        let json = try core.authJSON()
        if json.isEmpty || json == "null" { return nil }
        return try OrderedJSONDecoder.decode(MagpieAuthSpec.self, from: json)
    }

    /// The models the vendor serves. A vendor that does not list them throws
    /// Core's reason rather than answering an empty list.
    public func models(provider: String) throws -> [MagpieModel] {
        defer { persist(provider: provider) }
        let json = try core.modelsJSON()
        guard !json.isEmpty, json != "null" else { return [] }
        return try JSONDecoder().decode([MagpieModel].self, from: Data(json.utf8))
    }

    /// Hands the plugin its own switches. Keys are "provider|option", exactly as
    /// Core reads them, so a package's `input.magpie.option` answers the user's
    /// choice.
    public func setOptions(_ options: [String: Bool]) throws {
        let data = try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        try core.setPluginOptions(optionsJSON: String(decoding: data, as: UTF8.self))
    }

    /// Presses the account's check-in, when its plugin offers one.
    public func checkin(provider: String) throws -> MagpieCheckin {
        defer { persist(provider: provider) }
        let json = try core.checkinJSON(provider: provider)
        return try JSONDecoder().decode(MagpieCheckin.self, from: Data(json.utf8))
    }

    /// A conversation through this package.
    public func makeChat(provider: String, pollInterval: Duration = .milliseconds(40)) -> MagpieChat {
        // A turn can refresh the token mid-conversation; the chat has no store of
        // its own, so it hands the result back here.
        MagpieChat(core: core, pollInterval: pollInterval) { [weak self] in
            self?.persist(provider: provider)
        }
    }

    /// A sign-in for this package's account, driven by one object the UI can
    /// hold and cancel.
    public func makeSignIn(
        provider: String,
        inputs: [String: String] = [:],
        pollInterval: Duration = .milliseconds(500)
    ) -> MagpieSignIn {
        MagpieSignIn(core: core, store: store, provider: provider, inputs: inputs, pollInterval: pollInterval)
    }

    /// Runs the package's usage hook, as the package answered it.
    public func usage(provider: String) throws -> String {
        defer { persist(provider: provider) }
        return try core.usageJSON(provider: provider)
    }

    /// The account's usage in the shape every provider shares, or nil when the
    /// package reports none.
    public func usageReport(provider: String) throws -> MagpieUsage? {
        defer { persist(provider: provider) }
        let json = try core.usageSummaryJSON(provider: provider)
        guard !json.isEmpty, json != "null" else { return nil }
        return try JSONDecoder().decode(MagpieUsage.self, from: Data(json.utf8))
    }

    /// Forgets an account: the package is closed and its sign-in deleted.
    public func signOut(provider: String) throws {
        close()
        try store.remove(provider: provider)
    }

    private static func encode(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MagpieError("a package path is not valid UTF-8")
        }
        return text
    }
}
