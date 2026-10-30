import Foundation
import Testing
@testable import NekularityKit

/// Records what the runner asked Core to do.
final class StubMagpieCore: MagpieRunner.Core, @unchecked Sendable {
    var loads: [String] = []
    var auths: [String] = []
    var calls: [(String, String)] = []
    var closes = 0
    var savedToReturn = ""
    var loadError: Error?
    var callError: Error?

    func loadPackage(filesJSON: String) throws {
        if let loadError { throw loadError }
        loads.append(filesJSON)
    }

    func setAuth(provider: String, authJSON: String) throws {
        auths.append("\(provider):\(authJSON)")
    }

    func call(_ export: String, argJSON: String) throws -> String {
        if let callError { throw callError }
        calls.append((export, argJSON))
        return "{\"ok\":true}"
    }

    func savedAuthJSON() throws -> String { savedToReturn }
    func close() { closes += 1 }
}

@Suite struct MagpieRunnerTests {
    private let files: [String: Data] = [
        "package.json": Data(#"{"name":"demo","version":"0.1.0","main":"./index.mjs"}"#.utf8),
        "index.mjs": Data("export async function Plugin() { return {} }".utf8),
    ]

    @Test func installPassesBase64FilesAndTheStoredSignIn() throws {
        let core = StubMagpieCore()
        let store = MemoryMagpieAuthStore()
        try store.saveAuthJSON(provider: "demo", json: #"{"type":"api","key":"k"}"#)
        let runner = MagpieRunner(core: core, store: store)

        try runner.install(provider: "demo", files: files)

        let package = try #require(core.loads.first)
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: Data(package.utf8)) as? [String: String]
        )
        #expect(decoded.keys.sorted() == ["index.mjs", "package.json"])
        let source = try #require(decoded["index.mjs"]?.data(using: .utf8))
        #expect(String(decoding: Data(base64Encoded: source) ?? Data(), as: UTF8.self)
            .hasPrefix("export async function Plugin"))
        #expect(core.auths == [#"demo:{"type":"api","key":"k"}"#])
    }

    @Test func installWithoutAStoredSignInSendsNone() throws {
        let core = StubMagpieCore()
        let runner = MagpieRunner(core: core, store: MemoryMagpieAuthStore())
        try runner.install(provider: "demo", files: files)
        #expect(core.auths.isEmpty)
    }

    /// A refresh happens inside a hook; losing what the package saved would
    /// sign the user out on the next launch.
    @Test func callStoresWhatThePackageSaved() throws {
        let core = StubMagpieCore()
        core.savedToReturn = #"{"type":"oauth","access":"new","refresh":"r"}"#
        let store = MemoryMagpieAuthStore()
        let runner = MagpieRunner(core: core, store: store)

        let answer = try runner.call(provider: "demo", export: "Plugin", argJSON: "{}")

        #expect(answer == #"{"ok":true}"#)
        #expect(core.calls.count == 1)
        #expect(core.calls.first?.0 == "Plugin")
        #expect(try store.loadAuthJSON(provider: "demo") == core.savedToReturn)
    }

    @Test func callIgnoresAnEmptySave() throws {
        let core = StubMagpieCore()
        let store = MemoryMagpieAuthStore()
        try store.saveAuthJSON(provider: "demo", json: #"{"type":"api","key":"old"}"#)
        let runner = MagpieRunner(core: core, store: store)

        _ = try runner.call(provider: "demo", export: "Plugin")
        #expect(try store.loadAuthJSON(provider: "demo") == #"{"type":"api","key":"old"}"#)

        core.savedToReturn = "null"
        _ = try runner.call(provider: "demo", export: "Plugin")
        #expect(try store.loadAuthJSON(provider: "demo") == #"{"type":"api","key":"old"}"#)
    }

    @Test func signOutClosesAndForgets() throws {
        let core = StubMagpieCore()
        let store = MemoryMagpieAuthStore()
        try store.saveAuthJSON(provider: "demo", json: "{}")
        let runner = MagpieRunner(core: core, store: store)

        try runner.signOut(provider: "demo")

        #expect(core.closes == 1)
        #expect(try store.loadAuthJSON(provider: "demo") == nil)
    }

    @Test func aFailedLoadIsReported() throws {
        let core = StubMagpieCore()
        core.loadError = MagpieError("not a package")
        let runner = MagpieRunner(core: core, store: MemoryMagpieAuthStore())
        #expect(throws: MagpieError.self) {
            try runner.install(provider: "demo", files: files)
        }
    }
}

@Suite struct MagpieAuthStoreTests {
    @Test func memoryStoreRoundTripsExactText() throws {
        let store = MemoryMagpieAuthStore()
        // Number text and key order must survive: the package reads its own
        // JSON back, and 9007199254740993 would round as a double.
        let json = #"{"expires":9007199254740993,"access":"a","refresh":"r"}"#
        try store.saveAuthJSON(provider: "p", json: json)
        #expect(try store.loadAuthJSON(provider: "p") == json)
        try store.remove(provider: "p")
        #expect(try store.loadAuthJSON(provider: "p") == nil)
    }
}
