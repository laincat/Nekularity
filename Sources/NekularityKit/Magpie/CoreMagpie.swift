import Foundation

/// The real bridge: `MagpieRunner.Core` over the generated `MobileMagpie`.
///
/// Core keeps the package, its runtime and its requests; this type only moves
/// JSON across, and the client keeps the sign-in.
public final class CoreMagpie: MagpieRunner.Core, @unchecked Sendable {
    private let magpie: MobileMagpie

    /// `host` is the client's Core host, which supplies HTTP. It may be nil for
    /// a package that never touches the network, which is what the tests use.
    public init(host: (any MobileHostProtocol)? = nil) throws {
        guard let magpie = MobileNewMagpie(host) else {
            throw MagpieError("Core did not create a Magpie runner")
        }
        self.magpie = magpie
    }

    public func loadPackage(filesJSON: String) throws {
        _ = try magpie.loadPackage(filesJSON)
    }

    public func setAuth(provider: String, authJSON: String) throws {
        _ = try magpie.setAuth(provider, authJSON: authJSON)
    }

    public func call(_ export: String, argJSON: String) throws -> String {
        try magpie.call(export, argJSON: argJSON)
    }

    public func savedAuthJSON() throws -> String {
        try magpie.savedAuth()
    }

    public func authJSON() throws -> String {
        try magpie.auth()
    }

    public func authorize(methodIndex: Int, inputsJSON: String) throws -> String {
        try magpie.authorize(methodIndex, inputsJSON: inputsJSON)
    }

    public func poll(id: Int64) throws -> String {
        try magpie.poll(id)
    }

    public func cancelSignIn(id: Int64) throws {
        _ = try magpie.cancelSignIn(id)
    }

    public func usageJSON(provider: String) throws -> String {
        try magpie.usage(provider)
    }

    public func usageSummaryJSON(provider: String) throws -> String {
        try magpie.usageSummary(provider)
    }

    public func modelsJSON() throws -> String {
        try magpie.models()
    }

    public func checkinJSON(provider: String) throws -> String {
        try magpie.checkin(provider)
    }

    public func chatStart(model: String, messagesJSON: String, system: String, maxTokens: Int) throws -> String {
        try magpie.chatStart(model, messagesJSON: messagesJSON, system: system, maxTokens: maxTokens)
    }

    public func chatNext(handle: Int64) throws -> String {
        try magpie.chatNext(handle)
    }

    public func chatCancel(handle: Int64) {
        magpie.chatCancel(handle)
    }

    public func close() {
        magpie.close()
    }
}
