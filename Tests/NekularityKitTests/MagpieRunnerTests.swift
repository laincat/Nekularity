import Foundation
import Testing
@testable import NekularityKit

/// Records what the runner asked Core to do.
final class StubMagpieCore: MagpieRunner.Core, @unchecked Sendable {
    var loads: [String] = []
    var auths: [String] = []
    var calls: [(String, String)] = []
    var closes = 0
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

    var savedToReturn = ""
    var authToReturn = ""
    var authorizeToReturn = #"{"id":7,"url":"https://github.com/login/device","userCode":"ABCD-1234","instructions":"Enter code: ABCD-1234","expiresIn":900}"#
    var polls: [String] = [#"{"type":"success","refresh":"gho_new"}"#]
    var polledIDs: [Int64] = []
    var cancelledIDs: [Int64] = []
    var usageToReturn = ""

    func savedAuthJSON() throws -> String { savedToReturn }
    func authJSON() throws -> String { authToReturn }
    func authorize(methodIndex: Int, inputsJSON: String) throws -> String {
        authorizedInputs = inputsJSON
        return authorizeToReturn
    }
    func poll(id: Int64) throws -> String {
        polledIDs.append(id)
        return polls.isEmpty ? "null" : polls.removeFirst()
    }
    func cancelSignIn(id: Int64) throws { cancelledIDs.append(id) }
    func usageJSON(provider: String) throws -> String { usageToReturn }
    func close() { closes += 1 }

    var authorizedInputs = ""
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

@Suite struct MagpieSignInTests {
    private func runner(_ core: StubMagpieCore, store: MagpieAuthStore) -> MagpieRunner {
        MagpieRunner(core: core, store: store)
    }

    @Test func startReportsThePageAndTheCode() async throws {
        let core = StubMagpieCore()
        let signIn = MagpieSignIn(core: core, store: MemoryMagpieAuthStore(), provider: "p",
                                  inputs: ["deploymentType": "github.com"])
        let start = try signIn.start()
        #expect(start.id == 7)
        #expect(start.url == URL(string: "https://github.com/login/device"))
        #expect(start.userCode == "ABCD-1234")
        #expect(start.instructions.contains("ABCD-1234"))
        #expect(core.authorizedInputs == #"{"deploymentType":"github.com"}"#)
    }

    /// The package answered with its refresh token; what gets stored is
    /// Magpie's own oauth shape, not the package's answer verbatim.
    @Test func successIsStoredInMagpiesShape() async throws {
        let core = StubMagpieCore()
        let store = MemoryMagpieAuthStore()
        let signIn = MagpieSignIn(core: core, store: store, provider: "p")
        _ = try signIn.start()
        let outcome = await signIn.waitForResult()
        guard case .success(let stored) = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(stored == #"{"refresh":"gho_new","type":"oauth"}"#)
        #expect(try store.loadAuthJSON(provider: "p") == stored)
        #expect(core.polledIDs == [7])
    }

    /// A package may answer before the user has done anything; the loop waits
    /// for a real token instead of treating that as failure.
    @Test func aPendingAnswerKeepsWaiting() async throws {
        let core = StubMagpieCore()
        core.polls = ["null", #"{"type":"pending"}"#, #"{"type":"success","refresh":"gho_late"}"#]
        let signIn = MagpieSignIn(core: core, store: MemoryMagpieAuthStore(), provider: "p",
                                  pollInterval: .milliseconds(1))
        _ = try signIn.start()
        let outcome = await signIn.waitForResult()
        guard case .success = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(core.polledIDs.count == 3)
    }

    @Test func aRefusedSignInSaysSo() async throws {
        let core = StubMagpieCore()
        core.polls = [#"{"type":"failed","message":"user cancelled"}"#]
        let signIn = MagpieSignIn(core: core, store: MemoryMagpieAuthStore(), provider: "p")
        _ = try signIn.start()
        let outcome = await signIn.waitForResult()
        guard case .failed(let reason) = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(reason == "user cancelled")
    }

    /// Cancelling stops both the wait and the package's own callback.
    @Test func cancelStopsTheWaitAndThePackage() async throws {
        let core = StubMagpieCore()
        core.polls = []
        let signIn = MagpieSignIn(core: core, store: MemoryMagpieAuthStore(), provider: "p",
                                  pollInterval: .milliseconds(1))
        _ = try signIn.start()
        signIn.cancel()
        let outcome = await signIn.waitForResult()
        guard case .cancelled = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(core.cancelledIDs == [7])
    }

    @Test func aKeyedMethodStoresAnAPIKey() throws {
        // A package that collects the key itself hands it back through the
        // method's inputs rather than a refresh token.
        let stored = try MagpieAuthShape.stored(from: #"{"type":"success"}"#, inputs: ["key": "sk-1"])
        #expect(stored == #"{"key":"sk-1","type":"api"}"#)
        #expect(try MagpieAuthShape.stored(from: #"{"type":"failed"}"#, inputs: [:]) == nil)
    }

    @Test func theAuthSpecIsDecodedFromCore() throws {
        let core = StubMagpieCore()
        core.authToReturn = #"{"provider":"github-copilot","methods":[{"index":0,"label":"Sign in with GitHub","kind":"device","hint":""}],"options":[],"hasUsage":true,"hasLoader":true}"#
        let spec = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).auth(provider: "github-copilot")
        #expect(spec?.provider == "github-copilot")
        #expect(spec?.defaultMethod?.label == "Sign in with GitHub")
        #expect(spec?.hasUsage == true)

        core.authToReturn = ""
        #expect(try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).auth(provider: "p") == nil)
    }
}

@Suite struct MagpiePackageStoreTests {
    private func store() throws -> (MagpiePackageStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-packages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (MagpiePackageStore(directory: dir), dir)
    }

    private let files: [String: Data] = [
        "package.json": Data(#"{"name":"@magpie-community/copilot","version":"0.2.1","main":"./index.mjs"}"#.utf8),
        "index.mjs": Data("export async function CopilotAuthPlugin() { return {} }".utf8),
        "endpoints.mjs": Data("export const url = 1".utf8),
    ]

    @Test func installKeepsTheFilesAndDescribesThem() throws {
        let (store, _) = try store()
        let package = try store.install(provider: "github-copilot", files: files)
        #expect(package.name == "@magpie-community/copilot")
        #expect(package.version == "0.2.1")
        #expect(try store.list().count == 1)

        let back = try #require(try store.files(provider: "github-copilot"))
        #expect(back == files)
    }

    /// A package without a manifest is not a package; storing it would only move
    /// the failure to load time, where the reason is less obvious.
    @Test func aPackageWithoutAManifestIsRefused() throws {
        let (store, _) = try store()
        #expect(throws: MagpieError.self) {
            try store.install(provider: "x", files: ["index.mjs": Data("export default 1".utf8)])
        }
    }

    @Test func installingAgainReplacesTheOldCopy() throws {
        let (store, _) = try store()
        _ = try store.install(provider: "p", files: files)
        var newer = files
        newer["package.json"] = Data(#"{"name":"p","version":"0.3.0"}"#.utf8)
        let package = try store.install(provider: "p", files: newer)
        #expect(package.version == "0.3.0")
        #expect(try store.list().count == 1)
        #expect(try store.files(provider: "p")?["package.json"] == newer["package.json"])
    }

    @Test func removeForgetsIt() throws {
        let (store, _) = try store()
        _ = try store.install(provider: "p", files: files)
        try store.remove(provider: "p")
        #expect(try store.list().isEmpty)
        #expect(try store.files(provider: "p") == nil)
    }

    /// The list survives a new store instance: it is a file, not memory.
    @Test func theListIsOnDisk() throws {
        let (store, dir) = try store()
        _ = try store.install(provider: "p", files: files)
        let reopened = MagpiePackageStore(directory: dir)
        #expect(try reopened.list().map(\.provider) == ["p"])
    }
}

@Suite struct MagpiePackageReaderTests {
    private func folder(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-read-\(UUID().uuidString)")
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return dir
    }

    @Test func readsEveryFileWithPackageRelativePaths() throws {
        let dir = try folder([
            "package.json": #"{"name":"p","version":"1.0.0","main":"./index.mjs"}"#,
            "index.mjs": "export default async () => ({})",
            "lib/endpoints.mjs": "export const url = 1",
        ])
        let files = try MagpiePackageReader.files(from: dir)
        #expect(Set(files.keys) == ["package.json", "index.mjs", "lib/endpoints.mjs"])
        #expect(MagpiePackageReader.looksLikePackage(files: files))
        #expect(String(decoding: files["lib/endpoints.mjs"] ?? Data(), as: UTF8.self)
            .contains("export const url"))
    }

    /// A folder of random documents is not a plugin; saying so here is clearer
    /// than a load failure later.
    @Test func aFolderWithoutAManifestIsRejected() throws {
        let dir = try folder(["notes.txt": "hello"])
        #expect(throws: MagpiePackageReader.Rejection.self) {
            _ = try MagpiePackageReader.files(from: dir)
        }
    }

    /// A manifest with nothing to load is not a plugin either: Magpie itself
    /// refuses a package that names no entry.
    @Test func aManifestWithNoEntryIsNotAPackage() throws {
        let files = ["package.json": Data(#"{"name":"x","bin":{"x":"cli.js"}}"#.utf8)]
        #expect(!MagpiePackageReader.looksLikePackage(files: files))
    }

    @Test func aPackageNamingAFileInMainCounts() throws {
        let files = ["package.json": Data(#"{"name":"x","main":"./dist/index.cjs"}"#.utf8)]
        #expect(MagpiePackageReader.looksLikePackage(files: files))
    }

    /// The per-file limit is checked before the bytes are read, so a stray video
    /// in the folder is refused rather than swallowed.
    @Test func aHugeFileIsRefused() throws {
        let dir = try folder(["package.json": "{}", "big.bin": ""])
        let big = dir.appendingPathComponent("big.bin")
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(MagpiePackageReader.maxFileBytes + 1))
        try handle.close()
        #expect(throws: MagpiePackageReader.Rejection.self) {
            _ = try MagpiePackageReader.files(from: dir)
        }
    }
}
