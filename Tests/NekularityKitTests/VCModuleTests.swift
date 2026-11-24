import Foundation
import Testing
@testable import NekularityKit

@MainActor
struct VCModuleTests {
    private static let header = """
    #!name=阅读偏好示例
    #!desc=阅读配置覆盖
    #!version=0.1.0
    #!format=veneracat-module/1-draft
    """

    private func body(_ settings: String) -> Data {
        Data((Self.header + "\n[Reader]\n" + settings).utf8)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "nk-modules-\(UUID())")
    }

    @Test func parsesTemplateWithBOMAndCRLF() throws {
        let text = Self.header + "\n\n[Reader]\npage-gap = 8\nkeep-screen-on = true\n\n; comment\n"
        let document = try VCModuleDocument.parse("\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(document.name == "阅读偏好示例")
        #expect(document.description == "阅读配置覆盖")
        #expect(document.version == "0.1.0")
        #expect(document.settings == [.readerPageGap: .int(8), .readerKeepScreenOn: .bool(true)])
    }

    @Test func rejectsUnknownSectionsKeysAndInvalidValues() {
        for text in [
            "[Proxy]\nserver = example.test", "[MITM]\nhostname = *", "[Script]\nhook = x", "[Rule]\nFINAL,DIRECT",
            "[Reader]\naccess-token = x", "[Reader]\nkeep-screen-on = yes", "[Reader]\npage-gap = -1",
            "[Reader]\npage-gap = 129", "[Reader]\npage-gap = 8\npage-gap = 9", "[Reader]\nlayout = arbitrary",
            "[Reader]\n#!name=x", "page-gap = 1", "#!include=outside.ini\n[Reader]\npage-gap = 8",
        ] {
            #expect(throws: VCModuleError.self) { try VCModuleDocument.parse(Self.header + "\n" + text) }
        }
        #expect(throws: VCModuleError.unsupportedFormat) {
            try VCModuleDocument.parse(Self.header.replacingOccurrences(of: "1-draft", with: "2") + "\n[Reader]\npage-gap=8")
        }
        #expect(throws: VCModuleError.invalidUTF8) { try VCModuleDocument.parse(Data([0xff])) }
        #expect(throws: VCModuleError.tooLarge) {
            try VCModuleDocument.parse(Data(repeating: 65, count: VCModuleDocument.maximumBytes + 1))
        }
    }

    @Test func orderedOverlaysRestoreTheCurrentBaseAndSurviveReload() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = VCModuleStore(directory: dir)
        var base = VCModuleBaseSettings(readerPageGap: 3, readerRightToLeft: true)
        try store.install(data: body("page-gap=8\nkeep-screen-on=true"), id: "publisher.reader")
        try store.install(data: body("page-gap=16\nlayout=paged"), id: "publisher.paged")
        #expect(store.effectiveSettings(over: base) == base)
        try store.setEnabled(true, id: "publisher.paged")
        try store.setEnabled(true, id: "publisher.reader")
        let reopened = VCModuleStore(directory: dir)
        #expect(reopened.failure == nil)
        #expect(reopened.effectiveSettings(over: base) == VCModuleBaseSettings(
            readerPageGap: 16, readerKeepScreenOn: true, readerLayout: "paged", readerRightToLeft: true))
        try reopened.setEnabled(false, id: "publisher.paged")
        #expect(reopened.effectiveSettings(over: base).readerPageGap == 8)
        try reopened.install(data: body("page-gap=12"), id: "publisher.reader")
        #expect(reopened.effectiveSettings(over: base).readerPageGap == 12)
        base.readerPageGap = 4
        try reopened.remove("publisher.reader")
        #expect(reopened.effectiveSettings(over: base) == base)
        #expect(VCModuleStore(directory: dir).effectiveSettings(over: base) == base)
    }

    @Test func badIndexAndSymlinkArePreserved() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "modules.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: file)
        let store = VCModuleStore(directory: dir)
        #expect(store.failure != nil)
        #expect(throws: VCModuleError.self) { try store.install(data: body("page-gap=8"), id: "reader") }
        #expect(try Data(contentsOf: file) == broken)
        #expect(!StoreRescue.copies(of: file).isEmpty)
        let target = dir.appending(path: "other.json")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: VCModuleError.self) { try store.install(data: body("page-gap=8"), id: "reader") }
        #expect(try Data(contentsOf: target) == broken)
    }

    @Test func badModuleDoesNotOverrideOrEraseOtherModules() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = VCModuleStore(directory: dir)
        #expect(throws: VCModuleError.invalidIdentifier("../escape")) {
            try store.install(data: body("page-gap=8"), id: "../escape")
        }
        try store.install(data: body("page-gap=8"), id: "safe")
        try store.setEnabled(true, id: "safe")
        let file = dir.appending(path: "modules.json")
        let invalid = Data((Self.header + "\n[Script]\neval=true").utf8).base64EncodedString()
        let valid = body("page-gap=8").base64EncodedString()
        let index = """
        [{"id":"safe","origin":"test","enabled":true,"body":"\(valid)"},
         {"id":"bad","origin":"test","enabled":true,"body":"\(invalid)"}]
        """
        try Data(index.utf8).write(to: file)
        store.reload()
        #expect(store.invalidModuleIDs == ["bad"])
        #expect(store.effectiveSettings(over: .init()).readerPageGap == 8)
        try store.setEnabled(false, id: "safe")
        #expect(store.invalidModuleIDs == ["bad"])
        #expect(store.effectiveSettings(over: .init()).readerPageGap == 0)
    }
}
