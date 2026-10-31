import Foundation
import Testing
@testable import NekularityKit

/// These run the Go runtime inside the xcframework: a package of two files, the
/// real loader, the real call path. No host is needed, because a package that
/// never touches the network must also work — that is the case a client sees
/// first, right after installing.
@Suite struct CoreMagpieTests {
    private func package(files: [String: String]) throws -> String {
        var encoded: [String: String] = [:]
        for (path, text) in files {
            encoded[path] = Data(text.utf8).base64EncodedString()
        }
        let data = try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private let echo = [
        "package.json": #"{"name":"echo","version":"0.1.0","main":"./index.mjs"}"#,
        "index.mjs": "export async function Plugin(input) { return { echo: input } }",
    ]

    @Test func aPackageLoadsAndItsExportAnswers() throws {
        let magpie = try CoreMagpie()
        defer { magpie.close() }
        try magpie.loadPackage(filesJSON: try package(files: echo))

        let answer = try magpie.call("Plugin", argJSON: #"{"model":"m","n":9007199254740993}"#)

        // The large number survives the trip out: Core keeps json.Number rather
        // than rounding through a double.
        #expect(answer.contains("9007199254740993"))
        #expect(answer.contains(#""model":"m""#))
    }

    @Test func anUnknownExportIsAnError() throws {
        let magpie = try CoreMagpie()
        defer { magpie.close() }
        try magpie.loadPackage(filesJSON: try package(files: echo))
        #expect(throws: (any Error).self) {
            _ = try magpie.call("Missing", argJSON: "")
        }
    }

    @Test func aBrokenPackageIsRefused() throws {
        let magpie = try CoreMagpie()
        defer { magpie.close() }
        #expect(throws: (any Error).self) {
            try magpie.loadPackage(filesJSON: "{not json")
        }
        #expect(throws: (any Error).self) {
            try magpie.loadPackage(filesJSON: #"{"index.mjs":"!!!"}"#)
        }
    }

    /// Nothing saved means empty, not an error: the runner treats both alike.
    @Test func nothingSavedIsEmpty() throws {
        let magpie = try CoreMagpie()
        defer { magpie.close() }
        try magpie.loadPackage(filesJSON: try package(files: echo))
        _ = try magpie.call("Plugin", argJSON: "{}")
        #expect(try magpie.savedAuthJSON() == "")
    }

    /// After close, Core refuses work instead of running in a half-dead runtime.
    @Test func aClosedRunnerRefusesWork() throws {
        let magpie = try CoreMagpie()
        try magpie.loadPackage(filesJSON: try package(files: echo))
        magpie.close()
        #expect(throws: (any Error).self) {
            _ = try magpie.call("Plugin", argJSON: "{}")
        }
    }

    /// A downloaded package that is TypeScript is refused as TypeScript, and the user
    /// is told what to do instead of being handed Go error text.
    @Test func aTypeScriptPackageSaysWhatToDo() {
        let detail = "magpieplugin: unsupported source language: index.ts is TypeScript, which this runtime does not parse"
        let message = MagpieErrorText.message(for: detail)
        #expect(message.contains("TypeScript"))
        #expect(message.contains("编译后的包"))
        // Core's own words stay available for a bug report.
        #expect(message.contains("(Core: "))
    }

    /// A package that needs Node says so; the runtime does not pretend to have one.
    @Test func aPackageNeedingNodeSaysSo() {
        let detail = #"magpieplugin: module requires a host adapter or bundled dependency: "node:fs""#
        let message = MagpieErrorText.message(for: detail)
        #expect(message.contains("Node"))
        #expect(message.contains("(Core: "))
    }

    /// Anything else is reported as Core said it: inventing a vague sentence would
    /// hide the cause.
    @Test func anUnknownRefusalIsNotRewritten() {
        let detail = "magpieplugin: package.json has no main entry"
        #expect(MagpieErrorText.explain(detail) == nil)
        #expect(MagpieErrorText.message(for: detail) == detail)
    }

    /// End to end through Core, not just the mapping: a TypeScript entry is refused,
    /// and what reaches the screen already explains it while keeping Core's words.
    @Test func aTypeScriptPackageArrivesExplained() throws {
        let magpie = try CoreMagpie()
        defer { magpie.close() }
        let typed = [
            "package.json": #"{"name":"typed","version":"0.1.0","main":"./index.ts"}"#,
            "index.ts": "export async function Plugin() { return {} }",
        ]

        do {
            try magpie.loadPackage(filesJSON: try package(files: typed))
            Issue.record("a TypeScript package was accepted")
        } catch let error as MagpieError {
            let text = error.description
            #expect(text.contains("TypeScript"))
            #expect(text.contains("编译后的包"))
            #expect(text.contains("(Core: "))
        }
    }

    /// Core says these in English now; the screens still explain them in Chinese.
    @Test func missingFeaturesOfAPackageAreExplained() {
        #expect(MagpieErrorText.explain("magpieplugin: checkin threw: Error: this package declares no check-in")?
            .contains("签到") == true)
        #expect(MagpieErrorText.explain("magpieplugin: chatPrepare threw: Error: this package declares no loader")?
            .contains("请求入口") == true)
        #expect(MagpieErrorText.explain("magpieplugin: Error: chat is not prepared yet")?
            .contains("模型") == true)
    }

    /// The footer names a Core; the check script guarantees it is the one that
    /// gets built, and this keeps the short form useful rather than empty.
    @Test func theCoreVersionIsShortButIdentifiable() {
        #expect(CoreVersion.pinned.count >= 12)
        #expect(CoreVersion.short.count == 12)
        #expect(CoreVersion.pinned.hasPrefix(CoreVersion.short))
    }
}
