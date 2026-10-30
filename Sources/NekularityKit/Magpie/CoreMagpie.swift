import Foundation
import VeneraCatCore

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

    // MARK: Plumbing

    /// gomobile keeps the `NSError**` parameter instead of importing it as
    /// `throws`, the same shape `CoreClient.call` handles, so every call that
    /// can fail goes through here.
    private static func call(_ body: (NSErrorPointer) -> String) throws -> String {
        var error: NSError?
        let out = body(&error)
        if let error { throw error }
        return out
    }

    // MARK: Package

    /// gomobile splits the two shapes: a method returning `NSString*` keeps its
    /// `NSError**` parameter, while one returning `BOOL` is imported as
    /// `throws` alone — the success flag becomes the throw, so there is no
    /// `error:` argument and no `Bool` to test.
    /// gomobile imports `readPackageArchive:error:` as a throwing call that
    /// returns the file table, so it goes through the same error plumbing.
    public func readPackageArchive(_ data: Data) throws -> String {
        try Self.call { magpie.readPackageArchive(data, error: $0) }
    }

    public func loadPackage(filesJSON: String) throws {
        do {
            try magpie.loadPackage(filesJSON)
        } catch {
            throw MagpieError("Core 拒绝了这个插件包: \(error.localizedDescription)")
        }
    }

    public func setAuth(provider: String, authJSON: String) throws {
        do {
            try magpie.setAuth(provider, authJSON: authJSON)
        } catch {
            throw MagpieError("Core 拒绝了这个登录信息: \(error.localizedDescription)")
        }
    }

    public func call(_ export: String, argJSON: String) throws -> String {
        try Self.call { magpie.call(export, argJSON: argJSON, error: $0) }
    }

    public func savedAuthJSON() throws -> String {
        try Self.call { magpie.savedAuth($0) }
    }

    public func close() {
        // gomobile imports `- (void)close` without an error at all: nothing is
        // left to report a failure to.
        magpie.close()
    }

    // MARK: Sign-in

    public func authJSON() throws -> String {
        try Self.call { magpie.auth($0) }
    }

    public func authorize(methodIndex: Int, inputsJSON: String) throws -> String {
        try Self.call { magpie.authorize(methodIndex, inputsJSON: inputsJSON, error: $0) }
    }

    public func poll(id: Int64) throws -> String {
        try Self.call { magpie.poll(id, error: $0) }
    }

    public func cancelSignIn(id: Int64) throws {
        do {
            // The importer splits the selector at its preposition:
            // `cancelSignIn:error:` becomes `cancelSign(in:)`.
            try magpie.cancelSign(in: id)
        } catch {
            throw MagpieError("Core 找不到这次登录: \(error.localizedDescription)")
        }
    }

    // MARK: Usage and models

    public func usageJSON(provider: String) throws -> String {
        try Self.call { magpie.usage(provider, error: $0) }
    }

    public func usageSummaryJSON(provider: String) throws -> String {
        try Self.call { magpie.usageSummary(provider, error: $0) }
    }

    public func modelsJSON() throws -> String {
        try Self.call { magpie.models($0) }
    }

    public func checkinJSON(provider: String) throws -> String {
        try Self.call { magpie.checkin(provider, error: $0) }
    }

    public func setPluginOptions(optionsJSON: String) throws {
        do {
            try magpie.setPluginOptions(optionsJSON)
        } catch {
            throw MagpieError("Core 拒绝了这个开关设置: \(error.localizedDescription)")
        }
    }

    // MARK: Chat

    public func chatStart(model: String, messagesJSON: String, system: String, maxTokens: Int) throws -> String {
        try Self.call {
            magpie.chatStart(model, messagesJSON: messagesJSON, system: system,
                             maxTokens: maxTokens, error: $0)
        }
    }

    public func chatNext(handle: Int64) throws -> String {
        try Self.call { magpie.chatNext(handle, error: $0) }
    }

    public func chatCancel(handle: Int64) {
        magpie.chatCancel(handle)
    }
}
