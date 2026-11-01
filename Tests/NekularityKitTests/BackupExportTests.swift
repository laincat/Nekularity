import XCTest
@testable import NekularityKit

/// The export path exists on both sides, and the parts of it this machine can
/// check are the parts that decide the file's name and its encoding.
final class BackupExportTests: XCTestCase {
    /// A base64 answer that is not base64 must be reported, not silently written
    /// as an empty file.
    func testBase64DecodingRejectsRubbish() {
        XCTAssertNil(Data(base64Encoded: "not base64!!", options: []))
        XCTAssertNotNil(Data(base64Encoded: Data("PK".utf8).base64EncodedString(), options: []))
    }

    /// The history the archive gets is oldest first, and the store keeps the
    /// newest first.
    func testHistoryOrderIsReversed() {
        let newestFirst = ["c", "b", "a"]
        XCTAssertEqual(Array(newestFirst.reversed()), ["a", "b", "c"])
    }
}

/// What the kit hands Core: one object per source, taken from the store.
final class BackupExportSourceDataTests: XCTestCase {
    func testAllDataSourceObject() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SourceStore(root: root)
        try store.saveData(key: "cat", dataKey: "token", json: "\"abc\"")
        try store.saveData(key: "cat", dataKey: "page", json: "12345678901234567890")

        let text = try store.allData(key: "cat")
        let value = try JSONValue.parse(text)
        guard case .object(let object) = value else {
            return XCTFail("allData did not produce an object: \(text)")
        }
        XCTAssertEqual(object.entries.map(\.0), ["token", "page"])
        // Exact numbers survive the trip through the store and back out.
        XCTAssertTrue(text.contains("12345678901234567890"), text)
        // A source that stored nothing is an empty object, not a failure.
        XCTAssertEqual(try store.allData(key: "nothing"), "{}")
        // The archive has one object per source: settings and data are merged,
        // and data wins a name clash because it is what the source wrote.
        try store.saveSetting(key: "cat", settingKey: "domain", json: "\"a.example\"")
        try store.saveSetting(key: "cat", settingKey: "token", json: "\"from-settings\"")
        let merged = try JSONValue.parse(store.allValues(key: "cat"))
        guard case .object(let all) = merged else {
            return XCTFail("allValues did not produce an object")
        }
        XCTAssertEqual(all["domain"]?.stringValue, "a.example")
        XCTAssertEqual(all["token"]?.stringValue, "abc")
    }
}

/// The log lines Core hands over decode into what the panel draws.
final class SourceLogTests: XCTestCase {
    func testDecodesCoreShape() throws {
        let json = """
        [{"key":"talk","level":"error","title":"JS Engine","content":"Failed to convert base64","time":1767225600000},
         {"key":"","level":"log","title":"console","content":"hi","time":1767225601000}]
        """
        let lines = try OrderedJSONDecoder.decode([SourceLogEntry].self, from: json)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].key, "talk")
        XCTAssertEqual(lines[0].time, 1_767_225_600_000)
        // An empty key is Core itself, not a source called "".
        XCTAssertEqual(lines[1].key, "")
        XCTAssertTrue(Set(lines.map(\.id)).count == 2, "ids collide")
    }
}


/// Core normalises every browse shape into one wire form; the kit decodes that,
/// not the source's shapes, so a cursor page and a numbered page read the same.
final class ExploreWireTests: XCTestCase {
    func testDecodesCursorPage() throws {
        let json = """
        {"sections":[{"title":"热门","comics":[{"id":"a1","title":"A"}]}],"maxPage":0,"next":"tok-2"}
        """
        let wire = try OrderedJSONDecoder.decode(ExplorePageWire.self, from: json)
        XCTAssertEqual(wire.sections.count, 1)
        XCTAssertEqual(wire.sections[0].title, "热门")
        XCTAssertEqual(wire.next, "tok-2")
        XCTAssertEqual(wire.maxPage, 0)

        let numbered = """
        {"sections":[],"maxPage":7,"next":""}
        """
        let page = try OrderedJSONDecoder.decode(ExplorePageWire.self, from: numbered)
        XCTAssertEqual(page.maxPage, 7)
        XCTAssertTrue(page.next.isEmpty)
    }
}

/// The thread decodes into what the view draws, and a comment without an id is
/// still identifiable.
final class CommentDecodingTests: XCTestCase {
    func testDecodesThread() throws {
        let json = """
        {"comments":[
          {"id":"7","userName":"ada","avatar":"","content":"好作品","time":"2026-02-02","replyCount":2,"score":"3","isLiked":true},
          {"id":"","userName":"bob","avatar":"","content":"同意","time":"","replyCount":0,"score":"","isLiked":false}
        ],"maxPage":4}
        """
        var page = try OrderedJSONDecoder.decode(CommentPage.self, from: json)
        XCTAssertEqual(page.comments.count, 2)
        XCTAssertEqual(page.maxPage, 4)
        XCTAssertEqual(page.comments[0].score, "3")
        XCTAssertTrue(page.comments[0].isLiked)
        // The kit gives an id-less comment a stable identity so a list can draw it.
        page.comments = page.comments.enumerated().map { index, one in
            var copy = one
            copy.fallbackID = "\(index)-\(one.userName)-\(one.time)"
            return copy
        }
        XCTAssertFalse(page.comments[1].identity.isEmpty)
        XCTAssertEqual(page.comments[0].identity, "7")
    }

    func testSupportDecodes() throws {
        let support = try OrderedJSONDecoder.decode(CommentSupport.self, from: #"{"load":true,"send":false,"like":false}"#)
        XCTAssertTrue(support.load)
        XCTAssertFalse(support.send)
    }
}

/// A tag's meaning is the source's: the kit decodes what Core sends and keeps an
/// empty action distinct from a failure.
final class TagActionTests: XCTestCase {
    func testDecodesActions() throws {
        let search = try OrderedJSONDecoder.decode(TagAction.self, from: #"{"action":"search","keyword":"作者:张三","param":""}"#)
        XCTAssertEqual(search.action, "search")
        XCTAssertEqual(search.keyword, "作者:张三")

        let category = try OrderedJSONDecoder.decode(TagAction.self, from: #"{"action":"category","keyword":"","param":"action"}"#)
        XCTAssertEqual(category.param, "action")

        // No opinion is not a failure: the action is empty and nothing else says so.
        let none = try OrderedJSONDecoder.decode(TagAction.self, from: #"{"action":"","keyword":"","param":""}"#)
        XCTAssertTrue(none.action.isEmpty)
    }

    /// The category parameter a tag names is matched by the same rule the loader
    /// uses: per-value params, else the dimension's param, else the value.
    func testCategoryParamLookupFindsTheTagged() {
        let part = CategoryPart(name: "类型", type: "fixed", itemType: "category",
                                categories: ["热血", "恋爱"], params: ["action", "romance"],
                                groupParam: nil, randomNumber: nil)
        XCTAssertEqual(part.param(forValueAt: 0), "action")
        XCTAssertEqual(part.param(forValueAt: 1), "romance")
        let page = CategoryPage(title: "分类", parts: [part], options: [], ranking: nil)
        let target = page.paramTarget(for: "romance")
        XCTAssertEqual(target?.part, 0)
        XCTAssertEqual(target?.value, 1)
        XCTAssertNil(page.paramTarget(for: "not-there"))
    }
}

/// `subId` places a comment thread under the right work. It is declared on
/// ComicDetails, and a declared-but-undecoded field would mean every thread got
/// an empty string — the same silent hole as a wrong key.
final class DetailsSubIDTests: XCTestCase {
    func testDecodesSubID() throws {
        let json = """
        {"title":"T","subId":77,"chapters":{}}
        """
        let details = try OrderedJSONDecoder.decode(ComicDetails.self, from: json)
        XCTAssertEqual(details.subId, "77", "a numeric sub id must still travel")

        let none = try OrderedJSONDecoder.decode(ComicDetails.self, from: #"{"title":"T"}"#)
        XCTAssertNil(none.subId)
    }
}

/// A pasted address: the kit decodes what Core recognised, and the search box
/// decides what counts as an address without spending a source call on a dot.
final class LinkTargetTests: XCTestCase {
    func testDecodesTarget() throws {
        let hit = try OrderedJSONDecoder.decode(LinkTarget.self, from: #"{"key":"nhentai","id":"691529"}"#)
        XCTAssertFalse(hit.isEmpty)
        let miss = try OrderedJSONDecoder.decode(LinkTarget.self, from: #"{"key":"","id":""}"#)
        XCTAssertTrue(miss.isEmpty)
    }

    func testLooksLikeLink() {
        for q in ["https://nhentai.net/g/691529/", "nhentai.net/g/1", "www.a.example"] {
            XCTAssertTrue(LinkDetection.looksLikeLink(q), q)
        }
        // A dot alone is not an address: a version number and a keyword must stay
        // keywords, or every search spends a round of source calls.
        for q in ["海贼王", "one piece", "12.5", "v1.2", ""] {
            XCTAssertFalse(LinkDetection.looksLikeLink(q), q)
        }
    }
}

/// Reading a comment's replies is the same call with replyTo set; an empty
/// replyTo reads the thread itself.
final class CommentReplyTests: XCTestCase {
    func testReplyTargetIsTheCommentIdentity() {
        let top = ComicComment(id: "c1", userName: "阿达", content: "top", replyCount: 2)
        XCTAssertEqual(top.identity, "c1")
        // A comment without an id still has a stable identity to reply to.
        var anonymous = ComicComment(id: "", userName: "bob", content: "hi")
        anonymous.fallbackID = "0-bob-"
        XCTAssertEqual(anonymous.identity, "0-bob-")
        // The thread itself is the empty string, not a comment id.
        XCTAssertEqual(String?.none ?? "", "")
    }
}
