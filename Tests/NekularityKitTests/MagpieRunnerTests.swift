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
    /// What `readPackageArchive` answers, and how often it was asked.
    var archiveTable: String?
    var archiveRequests: [Int] = []

    func readPackageArchive(_ data: Data) throws -> String {
        archiveRequests.append(data.count)
        return archiveTable ?? "{}"
    }

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
    /// What `authorize` answers, when a test needs something other than the
    /// device-flow default.
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
    func usageSummaryJSON(provider: String) throws -> String { usageSummaryToReturn }
    var usageSummaryToReturn = ""
    func modelsJSON() throws -> String { modelsToReturn }
    var modelsToReturn = "[]"
    func checkinJSON(provider: String) throws -> String { checkinToReturn }
    func setPluginOptions(optionsJSON: String) throws { optionsSeen = optionsJSON }
    var optionsSeen = ""
    var checkinToReturn = #"{"outcome":"claimed","credit":"10 积分","streak":3,"message":"","until":""}"#

    var chatStarts: [(String, String)] = []
    var chatEvents: [String] = []
    var cancelledChats: [Int64] = []
    var chatStartError: Error?

    func chatStart(model: String, messagesJSON: String, system: String, maxTokens: Int) throws -> String {
        if let chatStartError { throw chatStartError }
        chatStarts.append((model, messagesJSON))
        return #"{"id":11}"#
    }

    func chatNext(handle: Int64) throws -> String {
        chatEvents.isEmpty ? "" : chatEvents.removeFirst()
    }

    func chatCancel(handle: Int64) {
        cancelledChats.append(handle)
    }
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

@Suite struct MagpieRunnerLifecycleTests {
    /// A runner is closed when its package is removed and again when it is
    /// deallocated; Core should hear about it once.
    @Test func closingTwiceClosesOnce() {
        let core = StubMagpieCore()
        let runner = MagpieRunner(core: core, store: MemoryMagpieAuthStore())
        runner.close()
        runner.close()
        #expect(core.closes == 1)
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

    /// An API key has no callback to wait for. Core answers an immediate key
    /// inside `authorize`, and the client must store it without polling — the
    /// alternative is a screen that spins on a callback that will never exist.
    @Test func anAPIKeyIsStoredWithoutPolling() async throws {
        let core = StubMagpieCore()
        core.authorizeToReturn = #"{"id":0,"url":"","userCode":"","instructions":"","expiresIn":0,"immediate":{"type":"success","key":"sk-immediate"}}"#
        let store = MemoryMagpieAuthStore()
        let signIn = MagpieSignIn(core: core, store: store, provider: "p", pollInterval: .milliseconds(1))
        let start = try signIn.start()
        #expect(start.immediateAuthJSON != nil)
        let outcome = await signIn.waitForResult()
        guard case .success(let authJSON) = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(authJSON.contains("sk-immediate"))
        #expect(try store.loadAuthJSON(provider: "p")?.contains("sk-immediate") == true)
        #expect(core.polls == 0)
    }

    /// A package that only ever says "nothing yet" must not hold the screen
    /// forever: the device code expires, and so does this wait.
    @Test func aPackageThatNeverAnswersTimesOut() async throws {
        let core = StubMagpieCore()
        core.polls = []
        let signIn = MagpieSignIn(core: core, store: MemoryMagpieAuthStore(), provider: "p",
                                  pollInterval: .milliseconds(1), timeout: .milliseconds(30))
        _ = try signIn.start()
        let outcome = await signIn.waitForResult()
        guard case .failed(let reason) = outcome else {
            Issue.record("outcome = \(outcome)")
            return
        }
        #expect(reason.contains("超时"))
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

@Suite struct MagpieAccountsTests {
    private func tempFolder(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-accounts-\(UUID().uuidString)")
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return dir
    }

    private func accounts(_ core: StubMagpieCore) throws -> (MagpieAccounts, MagpiePackageStore, MemoryMagpieAuthStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let packages = MagpiePackageStore(directory: dir)
        let auth = MemoryMagpieAuthStore()
        core.authToReturn = #"{"provider":"p","methods":[{"index":0,"label":"Sign in","kind":"device","hint":""}],"options":[],"hasUsage":true,"hasLoader":true}"#
        let accounts = MagpieAccounts(packages: packages, auth: auth, makeRunner: { _, _ in
            MagpieRunner(core: core, store: auth)
        }, makeCore: { core })
        return (accounts, packages, auth, dir)
    }

    @Test func installingLoadsThePackageBeforeStoringIt() throws {
        let core = StubMagpieCore()
        let (accounts, packages, _, _) = try accounts(core)
        let folder = try tempFolder([
            "package.json": #"{"name":"@magpie-community/copilot","version":"0.2.1","main":"./index.mjs"}"#,
            "index.mjs": "export async function CopilotAuthPlugin() { return {} }",
        ])
        // The id has to be the one the plugin declares ("p" in this stub), or the
        // install is refused: a package stored under another id would send its
        // sign-in to the wrong account.
        let row = try accounts.install(provider: "p", folder: folder)
        #expect(row.name == "@magpie-community/copilot")
        #expect(row.version == "0.2.1")
        #expect(row.hasSignIn)
        #expect(row.methods == ["Sign in"])
        #expect(try packages.files(provider: "p") != nil)
    }

    /// An archive install has to end up as the same file table a folder install
    /// produces, because it is the same install from then on: Core expands, the
    /// client stores what Core produced.
    @Test func anArchiveInstallsLikeAFolder() throws {
        let core = StubMagpieCore()
        let (accounts, packages, _, _) = try accounts(core)
        let json = #"{"package.json":"eyJuYW1lIjoiQC9kZW1vIiwidmVyc2lvbiI6IjAuMC4xIiwibWFpbiI6Ii4vaW5kZXgubWpzIn0=","index.mjs":"ZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIFBsdWdpbigpIHt9"}"#
        core.archiveTable = json
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-\(UUID().uuidString).zip")
        try Data("PK-not-really-a-zip".utf8).write(to: archive)
        let row = try accounts.install(provider: "p", archive: archive)
        #expect(core.archiveRequests == [Data("PK-not-really-a-zip".utf8).count])
        #expect(row.provider == "p")
        #expect(row.name == "@demo")
        #expect(row.version == "0.0.1")
        #expect(try packages.files(provider: "p") != nil)
    }

    /// Without a Core to expand with, the install says what to do instead of
    /// failing somewhere deeper.
    @Test func anArchiveNeedsACoreToExpandWith() throws {
        let core = StubMagpieCore()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-nocore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let packages = MagpiePackageStore(directory: dir)
        let auth = MemoryMagpieAuthStore()
        let accounts = MagpieAccounts(packages: packages, auth: auth) { _, _ in
            MagpieRunner(core: core, store: auth)
        }
        let archive = dir.appendingPathComponent("demo.zip")
        try Data("PK".utf8).write(to: archive)
        #expect(throws: (any Error).self) {
            _ = try accounts.install(provider: "p", archive: archive)
        }
        #expect(try packages.files(provider: "p") == nil)
    }

    /// A package Core refuses must not leave a row behind: an installed-looking
    /// entry that never works is worse than a clear failure now.
    @Test func aPackageCoreRefusesIsNotStored() throws {
        let core = StubMagpieCore()
        // A plugin that declares no provider is refused, and nothing is stored.
        core.authToReturn = ""
        let (accounts, packages, _, _) = try accounts(core)
        let folder = try tempFolder([
            "package.json": #"{"name":"x","version":"1.0.0","main":"./index.mjs"}"#,
            "index.mjs": "export const nothing = 1",
        ])
        #expect(throws: (any Error).self) {
            _ = try accounts.install(provider: "x", folder: folder)
        }
        #expect(try packages.files(provider: "x") == nil)
    }

    @Test func rowsSayWhoIsSignedIn() throws {
        let core = StubMagpieCore()
        let (accounts, _, auth, _) = try accounts(core)
        let folder = try tempFolder([
            "package.json": #"{"name":"p","version":"1.0.0","main":"./index.mjs"}"#,
            "index.mjs": "export async function Plugin() { return {} }",
        ])
        _ = try accounts.install(provider: "p", folder: folder)
        #expect(try accounts.rows().first?.signedIn == false)
        try auth.saveAuthJSON(provider: "p", json: #"{"type":"api","key":"k"}"#)
        #expect(try accounts.rows().first?.signedIn == true)
    }

    /// Removing forgets the package, its sign-in, and the runner holding its
    /// runtime.
    @Test func removingClosesTheRunnerAndForgetsTheSignIn() throws {
        let core = StubMagpieCore()
        let (accounts, packages, auth, _) = try accounts(core)
        let folder = try tempFolder([
            "package.json": #"{"name":"p","version":"1.0.0","main":"./index.mjs"}"#,
            "index.mjs": "export async function Plugin() { return {} }",
        ])
        _ = try accounts.install(provider: "p", folder: folder)
        try auth.saveAuthJSON(provider: "p", json: #"{"type":"api","key":"k"}"#)
        try accounts.remove(provider: "p")
        #expect(try packages.files(provider: "p") == nil)
        #expect(try auth.loadAuthJSON(provider: "p") == nil)
        #expect(core.closes >= 1)
    }

    @Test func theRunnerIsCachedPerProvider() throws {
        let core = StubMagpieCore()
        let (accounts, _, _, _) = try accounts(core)
        let folder = try tempFolder([
            "package.json": #"{"name":"p","version":"1.0.0","main":"./index.mjs"}"#,
            "index.mjs": "export async function Plugin() { return {} }",
        ])
        _ = try accounts.install(provider: "p", folder: folder)
        let first = try accounts.runner(for: "p")
        let second = try accounts.runner(for: "p")
        #expect(ObjectIdentifier(first) == ObjectIdentifier(second))
    }

    @Test func aProviderThatIsNotInstalledIsRefused() throws {
        let core = StubMagpieCore()
        let (accounts, _, _, _) = try accounts(core)
        #expect(throws: MagpieError.self) {
            _ = try accounts.runner(for: "absent")
        }
    }
}

@Suite struct MagpieInstallByNameTests {
    @Test func thePackageNamesItsOwnProvider() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-named-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"whatever-folder","version":"1.0.0","main":"./index.mjs"}"#.utf8)
            .write(to: dir.appendingPathComponent("package.json"))
        try Data("export async function Plugin() { return {} }".utf8)
            .write(to: dir.appendingPathComponent("index.mjs"))

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-named-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let packages = MagpiePackageStore(directory: storeDir)
        let auth = MemoryMagpieAuthStore()
        let core = StubMagpieCore()
        core.authToReturn = #"{"provider":"github-copilot","methods":[{"index":0,"label":"Sign in","kind":"device","hint":""}],"options":[],"hasUsage":true,"hasLoader":true}"#
        let accounts = MagpieAccounts(packages: packages, auth: auth) { _, _ in
            MagpieRunner(core: core, store: auth)
        }

        let row = try accounts.install(folder: dir)
        #expect(row.provider == "github-copilot")
        #expect(try packages.files(provider: "github-copilot") != nil)
        #expect(try accounts.rows().map(\.provider) == ["github-copilot"])
    }

    /// A plugin that never says which provider it serves cannot be an account:
    /// refusing now is clearer than a row no sign-in can ever fill.
    @Test func aPluginWithoutAProviderIsRefused() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-unnamed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"x","version":"1.0.0","main":"./index.mjs"}"#.utf8)
            .write(to: dir.appendingPathComponent("package.json"))
        try Data("export async function Plugin() { return {} }".utf8)
            .write(to: dir.appendingPathComponent("index.mjs"))

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-unnamed-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let core = StubMagpieCore()
        core.authToReturn = #"{"provider":"","methods":[],"options":[],"hasUsage":false,"hasLoader":false}"#
        let accounts = MagpieAccounts(packages: MagpiePackageStore(directory: storeDir),
                                      auth: MemoryMagpieAuthStore()) { _, _ in
            MagpieRunner(core: core, store: MemoryMagpieAuthStore())
        }
        #expect(throws: MagpieError.self) {
            _ = try accounts.install(folder: dir)
        }
        #expect(core.closes >= 1)
    }
}

@Suite struct MagpieChatTests {
    private func chat(_ core: StubMagpieCore) -> MagpieChat {
        MagpieChat(core: core, pollInterval: .milliseconds(1))
    }

    @Test func eventsArriveInOrderAndEnd() async throws {
        let core = StubMagpieCore()
        core.chatEvents = [
            #"{"kind":"text","text":"Hel"}"#,
            #"{"kind":"text","text":"lo"}"#,
            #"{"kind":"done","finish":"stop","usage":{"input":3,"output":2}}"#,
            #"{"kind":"end"}"#,
        ]
        var text = ""
        var kinds: [MagpieChatEvent.Kind] = []
        for try await event in chat(core).send(model: "m", messages: [MagpieMessage(role: "user", content: "hi")]) {
            kinds.append(event.kind)
            if event.kind == .text { text += event.text }
        }
        #expect(text == "Hello")
        #expect(kinds == [.text, .text, .done])
        #expect(core.chatStarts.first?.0 == "m")
        #expect(core.chatStarts.first?.1.contains(#""content":"hi""#) == true)
        #expect(core.cancelledChats == [11])
    }

    /// Leaving the screen stops the request: the handle is cancelled rather than
    /// left running against the vendor.
    @Test func stoppingEarlyCancelsTheRequest() async throws {
        let core = StubMagpieCore()
        core.chatEvents = [#"{"kind":"text","text":"a"}"#, #"{"kind":"text","text":"b"}"#]
        for try await event in chat(core).send(model: "m", messages: []) {
            if event.kind == .text { break }
        }
        // The task notices cancellation after the next await; give it one.
        try await Task.sleep(for: .milliseconds(20))
        #expect(core.cancelledChats == [11])
    }

    @Test func aVendorErrorIsReported() async throws {
        let core = StubMagpieCore()
        core.chatEvents = [#"{"kind":"error","text":"quota exhausted"}"#, #"{"kind":"end"}"#]
        var message: String?
        for try await event in chat(core).send(model: "m", messages: []) {
            if event.kind == .error { message = event.text }
        }
        #expect(message == "quota exhausted")
    }

    /// Core ends every conversation with an end event, but a package whose
    /// request never settles would leave the reader waiting for one that cannot
    /// arrive; the turn is bounded.
    @Test func aReplyThatNeverEndsTimesOut() async throws {
        let core = StubMagpieCore()
        core.chatEvents = []
        var threw = false
        do {
            for try await _ in chat(core).send(model: "m", messages: [], timeout: .milliseconds(30)) {}
        } catch {
            threw = true
        }
        #expect(threw)
        #expect(core.cancelledChats == [11])
    }

    @Test func aFailedStartThrows() async throws {
        let core = StubMagpieCore()
        core.chatStartError = MagpieError("没有登录")
        var threw = false
        do {
            for try await _ in chat(core).send(model: "m", messages: []) {}
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test func eventsParseIntoTheModel() {
        let event = MagpieChat.event(from: #"{"kind":"text","text":"x","finish":""}"#)
        #expect(event.kind == .text)
        #expect(event.text == "x")
        #expect(MagpieChat.handle(from: #"{"id":42}"#) == 42)
        #expect(MagpieChat.handle(from: "{}") == nil)
        #expect(MagpieChat.event(from: "not json").kind == .error)
    }
}

@Suite struct MagpieUsageTests {
    private let summary = """
    {"plan":"individual","until":"","renew":"","balance":"","error":"","user":"","signIn":"kept",
     "resets":null,
     "windows":[{"name":"Premium requests","used":50,"resetsAt":"2026-01-01T00:00:00Z","resetSecs":0,
                 "display":"","amount":150,"limit":300,"unit":"requests","span":0,"model":"",
                 "models":[],"notModels":[],"aside":false,"runsOutAt":"","runsOut":0,"balance":null},
                {"name":"Unknown","used":null,"resetsAt":"","resetSecs":0,"display":"No allowance reported",
                 "amount":0,"limit":0,"unit":"","span":0,"model":"","models":[],"notModels":[],
                 "aside":true,"runsOutAt":"","runsOut":0,"balance":null}]}
    """

    @Test func theReportIsDecodedAndExplained() throws {
        let core = StubMagpieCore()
        core.usageSummaryToReturn = summary
        let usage = try #require(try MagpieRunner(core: core, store: MemoryMagpieAuthStore())
            .usageReport(provider: "p"))
        #expect(usage.plan == "individual")
        #expect(usage.signIn == "kept")
        #expect(usage.windows.count == 2)
        #expect(usage.windows[0].summary == "150 / 300 requests")
        // No share was given, so the vendor's own words stand rather than "0%".
        #expect(usage.windows[1].used == nil)
        #expect(usage.windows[1].summary == "No allowance reported")
        #expect(usage.windows[1].aside)
    }

    @Test func anEmptyAnswerIsNoReport() throws {
        let core = StubMagpieCore()
        core.usageSummaryToReturn = ""
        #expect(try MagpieRunner(core: core, store: MemoryMagpieAuthStore())
            .usageReport(provider: "p") == nil)
        core.usageSummaryToReturn = "null"
        #expect(try MagpieRunner(core: core, store: MemoryMagpieAuthStore())
            .usageReport(provider: "p") == nil)
    }

    @Test func aPercentageIsShownWithoutADecimal() throws {
        var window = MagpieUsage.Window(name: "Weekly", used: 37, resetsAt: "", resetSecs: 0,
                                        display: "", amount: 0, limit: 0, unit: "", span: 0,
                                        model: "", models: [], notModels: [], aside: false,
                                        runsOutAt: "", runsOut: 0, balance: nil)
        #expect(window.summary == "37%")
        window.used = 137.5
        #expect(window.summary == "137.5%")
        window.used = nil
        #expect(window.summary == "没有报告用量")
    }

    /// A wallet has a figure and no share; the figure is what to show.
    @Test func aWalletShowsItsBalance() {
        let window = MagpieUsage.Window(name: "积分", used: nil, resetsAt: "", resetSecs: 0,
                                        display: "", amount: 0, limit: 0, unit: "积分", span: 0,
                                        model: "", models: [], notModels: [], aside: false,
                                        runsOutAt: "", runsOut: 0, balance: 6291)
        #expect(window.summary == "6291 积分")
    }
}

@Suite struct MagpieModelTests {
    @Test func theListIsDecodedWithItsLimits() throws {
        let core = StubMagpieCore()
        core.modelsToReturn = """
        [{"id":"gpt-4o","name":"GPT-4o","context":128000,"output":16384,"modalities":["text","image"],"vendor":"openai"},
         {"id":"o3","name":"o3","context":0,"output":0,"modalities":null,"vendor":""}]
        """
        let models = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).models()
        #expect(models.count == 2)
        #expect(models[0].id == "gpt-4o")
        #expect(models[0].context == 128000)
        #expect(models[0].detail == "128K 上下文")
        // No size was given, so nothing is claimed about it.
        #expect(models[1].context == 0)
        #expect(models[1].detail == "")
    }

    @Test func anEmptyAnswerIsAnEmptyList() throws {
        let core = StubMagpieCore()
        core.modelsToReturn = "null"
        #expect(try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).models().isEmpty)
    }

    /// A vendor that refuses the list must surface as an error, not as "no
    /// models": the two mean different things to a user picking one.
    @Test func aRefusedListThrows() throws {
        final class RefusingCore: MagpieRunner.Core, @unchecked Sendable {
            func loadPackage(filesJSON: String) throws {}
            func setAuth(provider: String, authJSON: String) throws {}
            func call(_ export: String, argJSON: String) throws -> String { "{}" }
            func savedAuthJSON() throws -> String { "" }
            func authJSON() throws -> String { "" }
            func authorize(methodIndex: Int, inputsJSON: String) throws -> String { "{}" }
            func poll(id: Int64) throws -> String { "{}" }
            func cancelSignIn(id: Int64) throws {}
            func usageJSON(provider: String) throws -> String { "" }
            func usageSummaryJSON(provider: String) throws -> String { "" }
            func modelsJSON() throws -> String { throw MagpieError("供应商不提供模型列表") }
            func checkinJSON(provider: String) throws -> String { "" }
            func setPluginOptions(optionsJSON: String) throws {}
            func chatStart(model: String, messagesJSON: String, system: String, maxTokens: Int) throws -> String { "{}" }
            func chatNext(handle: Int64) throws -> String { "" }
            func chatCancel(handle: Int64) {}
            func close() {}
        }
        #expect(throws: MagpieError.self) {
            _ = try MagpieRunner(core: RefusingCore(), store: MemoryMagpieAuthStore()).models()
        }
    }
}

@Suite struct MagpieCheckinTests {
    @Test func aClaimSaysWhatItGave() throws {
        let core = StubMagpieCore()
        let result = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).checkin(provider: "p")
        #expect(result.outcome == .claimed)
        #expect(result.succeeded)
        #expect(result.summary == "已签到,获得 10 积分")
    }

    /// A captcha is not a success and not a failure to retry: the user has to
    /// finish it where the vendor expects.
    @Test func aCaptchaSendsTheUserElsewhere() throws {
        let core = StubMagpieCore()
        core.checkinToReturn = #"{"outcome":"captcha","credit":"","streak":0,"message":"","until":""}"#
        let result = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).checkin(provider: "p")
        #expect(!result.succeeded)
        #expect(result.summary.contains("它自己的 App"))
    }

    @Test func anAlreadyDoneDayIsNotAFailure() throws {
        let core = StubMagpieCore()
        core.checkinToReturn = #"{"outcome":"done","credit":"","streak":0,"message":"","until":""}"#
        let result = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).checkin(provider: "p")
        #expect(result.succeeded)
        #expect(result.summary == "今天已经签过了")
    }

    @Test func aFailedCheckinShowsTheVendorsReason() throws {
        let core = StubMagpieCore()
        core.checkinToReturn = #"{"outcome":"failed","credit":"","streak":0,"message":"服务不可用","until":""}"#
        let result = try MagpieRunner(core: core, store: MemoryMagpieAuthStore()).checkin(provider: "p")
        #expect(!result.succeeded)
        #expect(result.summary == "服务不可用")
    }
}

@Suite struct MagpieOptionTests {
    /// The keys carry the provider, because Core keeps one table for every
    /// plugin and a switch must not leak to another provider's account.
    @Test func optionsAreSentWithTheProviderInTheKey() throws {
        let core = StubMagpieCore()
        try MagpieRunner(core: core, store: MemoryMagpieAuthStore())
            .setOptions(["demo|freeOnly": true, "demo|vision": false])
        #expect(core.optionsSeen.contains(#""demo|freeOnly":true"#))
        #expect(core.optionsSeen.contains(#""demo|vision":false"#))
    }
}

@Suite struct MagpieOptionStoreTests {
    private func store() throws -> MagpieOptionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return MagpieOptionStore(directory: dir)
    }

    @Test func valuesArePerProvider() throws {
        let store = try store()
        try store.set(provider: "a", key: "freeOnly", value: true)
        #expect(try store.values(provider: "a") == ["freeOnly": true])
        #expect(try store.values(provider: "b").isEmpty)
        #expect(try store.optionsJSON(provider: "a") == ["a|freeOnly": true])
    }

    /// A switch nobody touched keeps the plugin's own default: a package written
    /// as `option(...) ?? default` should see the default, not a false we made up.
    @Test func untouchedSwitchesKeepThePluginsDefault() throws {
        let store = try store()
        let declared = [
            MagpieAuthSpec.Option(key: "freeOnly", label: "只用免费模型", description: "", confirm: "", default: true),
            MagpieAuthSpec.Option(key: "vision", label: "", description: "", confirm: "", default: false),
        ]
        var resolved = try store.resolve(declared, provider: "p")
        #expect(resolved.map(\.value) == [true, false])
        // An empty label falls back to the key so the row is still readable.
        #expect(resolved[1].label == "vision")

        try store.set(provider: "p", key: "freeOnly", value: false)
        resolved = try store.resolve(declared, provider: "p")
        #expect(resolved[0].value == false)
    }

    @Test func theFileSurvivesANewInstance() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = MagpieOptionStore(directory: dir)
        try first.set(provider: "p", key: "k", value: true)
        let second = MagpieOptionStore(directory: dir)
        #expect(try second.values(provider: "p") == ["k": true])
    }
}

@Suite struct MagpieSpecCacheTests {
    /// Listing providers must not start a JavaScript runtime per package on
    /// every refresh; the declared spec is asked for once.
    @Test func theListLoadsAPackagesSpecOnce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let packages = MagpiePackageStore(directory: dir)
        try packages.install(provider: "p", files: [
            "package.json": Data(#"{"name":"p","version":"1.0.0","main":"./index.mjs"}"#.utf8),
            "index.mjs": Data("export async function Plugin() { return {} }".utf8),
        ])
        let auth = MemoryMagpieAuthStore()
        let core = StubMagpieCore()
        core.authToReturn = #"{"provider":"p","methods":[{"index":0,"label":"Sign in","kind":"device","hint":""}],"options":[],"hasUsage":true,"hasLoader":true}"#
        final class Counter: @unchecked Sendable { var made = 0 }
        let counter = Counter()
        let accounts = MagpieAccounts(packages: packages, auth: auth) { _, _ in
            counter.made += 1
            return MagpieRunner(core: core, store: auth)
        }

        _ = try accounts.rows()
        _ = try accounts.rows()
        _ = try accounts.rows()

        #expect(counter.made == 1)
        #expect(try accounts.rows().first?.methods == ["Sign in"])
    }
}
