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

    /// The footer names a Core; the check script guarantees it is the one that
    /// gets built, and this keeps the short form useful rather than empty.
    @Test func theCoreVersionIsShortButIdentifiable() {
        #expect(CoreVersion.pinned.count >= 12)
        #expect(CoreVersion.short.count == 12)
        #expect(CoreVersion.pinned.hasPrefix(CoreVersion.short))
    }
}
