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
        func loadPackage(filesJSON: String) throws
        func setAuth(provider: String, authJSON: String) throws
        func call(_ export: String, argJSON: String) throws -> String
        func savedAuthJSON() throws -> String
        func authJSON() throws -> String
        func authorize(methodIndex: Int, inputsJSON: String) throws -> String
        func poll(id: Int64) throws -> String
        func cancelSignIn(id: Int64) throws
        func usageJSON(provider: String) throws -> String
        func close()
    }

    private let core: Core
    private let store: MagpieAuthStore
    private let lock = NSLock()

    public init(core: Core, store: MagpieAuthStore) {
        self.core = core
        self.store = store
    }

    deinit { core.close() }

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
        if let stored = try store.loadAuthJSON(provider: provider) {
            try core.setAuth(provider: provider, authJSON: stored)
        }
    }

    /// Runs a hook exported by the package, returning its JSON answer.
    ///
    /// After the call the sign-in the package saved is stored again: a refresh
    /// happens inside a hook, and losing it would sign the user out on the next
    /// launch. The JSON text the package wrote is stored as it is.
    public func call(provider: String, export: String, argJSON: String = "") throws -> String {
        let answer = try core.call(export, argJSON: argJSON)
        if let saved = try? core.savedAuthJSON(), !saved.isEmpty, saved != "null" {
            try store.saveAuthJSON(provider: provider, json: saved)
        }
        return answer
    }

    // MARK: Sign-in

    /// What the package's plugin offers.
    public func auth(provider: String) throws -> MagpieAuthSpec? {
        let json = try core.authJSON()
        if json.isEmpty || json == "null" { return nil }
        return try OrderedJSONDecoder.decode(MagpieAuthSpec.self, from: json)
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
        try core.usageJSON(provider: provider)
    }

    /// Forgets an account: the package is closed and its sign-in deleted.
    public func signOut(provider: String) throws {
        core.close()
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
