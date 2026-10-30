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

    public func close() {
        magpie.close()
    }
}
