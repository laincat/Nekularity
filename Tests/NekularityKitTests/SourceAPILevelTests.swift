import Foundation
import Testing
@testable import NekularityKit

/// What the client reports as its source API level decides whether a source
/// installs at all.
///
/// This is not hypothetical: the app reported its own version 0.1.0, every official
/// source declares `minAppVersion = "1.0.0"`, and Core refused all of them with
/// "minAppVersion 1.0.0 is required" — an empty source list, with nothing in the
/// client saying why.
@MainActor
@Suite("Source API level")
struct SourceAPILevelTests {
    private func gated(_ minVersion: String) -> String {
        """
        class Gated extends ComicSource {
            name = "Gated"; key = "gated"; version = "1.0.0"
            minAppVersion = "\(minVersion)"
            search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) }
        }
        """
    }

    private func library(_ version: String) throws -> SourceLibrary {
        let jars = CookieJars(file: nil)
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1")
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: version, locale: "zh_CN",
                                                     defaultUserAgent: "nk-test/1"), host: host)
        return SourceLibrary(core: core, fetch: { _ in Data() })
    }

    /// The level the app reports satisfies the official sources' floor.
    @Test func theReportedLevelInstallsOfficialSources() async throws {
        let lib = try library(SourceAPI.level)
        _ = try await lib.install(script: gated("1.0.0"), origin: "test")
        await lib.refresh()
        #expect(lib.comicSources.map(\.key) == ["gated"])
    }

    /// The app's own version is below every official source's floor, which is why
    /// it must not be what the client reports.
    @Test func theAppVersionIsBelowTheFloor() async throws {
        let lib = try library("0.1.0")
        await #expect(throws: (any Error).self) {
            _ = try await lib.install(script: gated("1.0.0"), origin: "test")
        }
    }

    /// A source that needs more than this client implements still refuses, so the
    /// level is a claim with an edge rather than a bypass.
    @Test func aSourceBeyondTheLevelIsRefused() async throws {
        let lib = try library(SourceAPI.level)
        await #expect(throws: (any Error).self) {
            _ = try await lib.install(script: gated("9.0.0"), origin: "test")
        }
    }
}
