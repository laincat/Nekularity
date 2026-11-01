import Foundation
import Testing

@testable import NekularityKit

@Suite("Danmaku")
struct DanmakuTests {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <i><chatserver>chat.bilibili.com</chatserver>
    <d p="12.345,1,25,16777215,1550000000,0,abc,123">第一条</d>
    <d p="3.5,4,25,16711680,1550000000,0,def,456">底部 &amp; 转义</d>
    <d p="20.0,5,18,255,1550000000,0,ghi,789">顶部</d>
    </i>
    """

    @Test("bilibili xml becomes sorted comments with their own modes and colours")
    func parsesXML() {
        let comments = DanmakuParser.parse(xml: xml)
        #expect(comments.count == 3)
        // Sorted by time, so the renderer can walk the array once.
        #expect(comments.map(\.time) == [3.5, 12.345, 20.0])
        #expect(comments[0].text == "底部 & 转义")
        #expect(comments[0].color == 0xFF0000)
        #expect(comments[0].placement == .bottom)
        #expect(comments[2].placement == .top)
        #expect(comments[1].placement == .scroll)
    }

    @Test("a danmaku json file reads too")
    func parsesJSON() {
        let json = """
        {"comments":[{"p":"5.0,1,16777215","m":"甲"},{"p":"1.0,5,255","m":"乙"}]}
        """
        let comments = DanmakuParser.parse(json: json)
        #expect(comments.map(\.text) == ["乙", "甲"])
        #expect(comments[0].color == 255)
    }

    @Test("only the recent window is drawn, capped")
    func activeWindow() {
        let comments = (0..<100).map { DanmakuComment(time: Double($0), text: "\($0)") }
        let shown = DanmakuParser.active(comments, at: 50, window: 4)
        #expect(shown.map(\.text) == ["47", "48", "49", "50"])
        // A huge list still yields at most the cap, so a busy minute cannot draw
        // thousands of lines.
        let crowded = (0..<200).map { DanmakuComment(time: 50, text: "\($0)") }
        #expect(DanmakuParser.active(crowded, at: 50, limit: 10).count == 10)
        #expect(DanmakuParser.active(comments, at: 0).isEmpty)
    }

    @Test("a broken file yields nothing instead of failing the player")
    func toleratesGarbage() {
        #expect(DanmakuParser.parse(xml: "not xml at all").isEmpty)
        #expect(DanmakuParser.parse(json: "{").isEmpty)
        #expect(DanmakuParser.parse(xml: "<i><d p=\"x,1,25,0\">坏</d></i>").isEmpty)
    }
}

@Suite("Intro marks")
@MainActor
struct IntroStoreTests {
    private func store() throws -> IntroStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "intro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return IntroStore(directory: root)
    }

    @Test("a mark is per show and survives a relaunch")
    func persists() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "intro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IntroStore(directory: root)
        store.mark(provider: "probe", title: "某剧", start: 8, end: 98)
        #expect(store.mark(provider: "probe", title: "某剧")?.end == 98)
        #expect(store.mark(provider: "probe", title: "另一部") == nil)

        let again = IntroStore(directory: root)
        #expect(again.mark(provider: "PROBE", title: "某剧")?.start == 8)
    }

    @Test("the opening contains the opening, not the episode")
    func contains() {
        let mark = IntroMark(start: 8, end: 98)
        #expect(mark.contains(10))
        // A second of slack at the end: pressing skip at 97.5 s still works.
        #expect(mark.contains(97.5))
        #expect(!mark.contains(98))
        #expect(!mark.contains(5))
    }

    @Test("an impossible mark is refused rather than stored")
    func rejectsNonsense() throws {
        let store = try store()
        store.mark(provider: "probe", title: "某剧", start: 90, end: 10)
        #expect(store.mark(provider: "probe", title: "某剧") == nil)
        #expect(store.failure != nil)
    }
}
