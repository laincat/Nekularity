import Foundation
import Testing
@testable import NekularityKit

/// Importing a backup that carries cookies: the plan comes from Core, the sources
/// are installed here, and the cookies have to end up in the partition of the
/// source that will use them.
///
/// This is the end-to-end path a user sees. The pieces are tested separately too,
/// but the order matters: install first, then write, or a cookie lands in a
/// partition no source reads.
@MainActor
@Suite("Backup cookies end to end")
struct BackupCookieImportTests {
    private let script = """
    class Mini extends ComicSource {
        name = "Mini"; key = "mini"; version = "1.0.0"
        search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) }
    }
    """

    private func makeJars() -> CookieJars { CookieJars(file: nil) }

    private func library(_ root: URL, jars: CookieJars) throws -> SourceLibrary {
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1")
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "nk-test/1"), host: host)
        return SourceLibrary(core: core, fetch: { _ in Data() }, cookieJars: jars)
    }

    private func plan(script: String?, targets: [String]?) -> BackupPlan {
        var plan = BackupPlan()
        plan.sources = script.map { [BackupSource(key: "mini", script: $0, data: nil)] } ?? []
        plan.cookies = [BackupCookie(name: "sid", value: "secret", domain: ".wnacg.com")]
        plan.cookieTargets = targets
        return plan
    }

    @Test func aRestoredBackupLandsItsCookiesInTheSourceItInstalled() async throws {
        let jars = makeJars()
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let lib = try library(root, jars: jars)
        let shelf = ShelfStore(directory: root)

        let result = await BackupImporter().apply(plan(script: script, targets: ["mini"]),
                                                  library: lib, shelf: shelf,
                                                  searches: SearchHistoryStore(directory: root), jars: jars)

        #expect(result.sourcesInstalled == 1)
        #expect(result.cookiesAdded == 1)
        let header = jars.header(partition: "mini", url: URL(string: "https://wnacg.com/")!)
        #expect(header == "sid=secret")
    }

    @Test func aSourceThatFailedToInstallGetsNoCookies() async throws {
        // The script is not a comic source, so the install fails. Writing the cookie
        // anyway would leave a row in a partition with no source behind it.
        let jars = makeJars()
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let lib = try library(root, jars: jars)
        let shelf = ShelfStore(directory: root)

        let result = await BackupImporter().apply(plan(script: "this is not a source", targets: ["mini"]),
                                                  library: lib, shelf: shelf,
                                                  searches: SearchHistoryStore(directory: root), jars: jars)

        #expect(result.sourcesInstalled == 0)
        #expect(result.cookiesAdded == 0)
        #expect(jars.header(partition: "mini", url: URL(string: "https://wnacg.com/")!) == nil)
    }

    @Test func withoutJarsNothingIsWritten() async throws {
        // The default import has no jars to write into, which is the off switch.
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let jars = makeJars()
        let lib = try library(root, jars: jars)

        let result = await BackupImporter().apply(plan(script: script, targets: ["mini"]),
                                                  library: lib, shelf: ShelfStore(directory: root),
                                                  searches: SearchHistoryStore(directory: root), jars: nil)

        #expect(result.sourcesInstalled == 1)
        #expect(result.cookiesAdded == 0)
        #expect(jars.header(partition: "mini", url: URL(string: "https://wnacg.com/")!) == nil)
    }
}
