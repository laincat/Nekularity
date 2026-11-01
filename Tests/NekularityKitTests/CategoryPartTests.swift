import XCTest
@testable import NekularityKit

/// The category page crosses the bridge as JSON, and what a value maps to is
/// decided on this side, so both are worth pinning down without a source.
final class CategoryPartTests: XCTestCase {
    private func decode(_ json: String) throws -> CategoryPage {
        try JSONDecoder().decode(CategoryPage.self, from: Data(json.utf8))
    }

    /// nhentai's Language part has no per-value parameters, so the dimension's
    /// own name is what its loader switches on.
    func testGroupParameterIsUsedWhenValuesCarryNone() throws {
        let page = try decode("""
        {"title":"nhentai","parts":[{"name":"Language","type":"fixed","itemType":"category",
        "categories":["Chinese","English"],"groupParam":"language"}]}
        """)
        let part = try XCTUnwrap(page.parts.first)
        XCTAssertEqual(part.param(for: "Chinese"), "language")
        XCTAssertFalse(part.isRandom)
    }

    /// copy_manga maps each value onto its own parameter, which wins over the
    /// dimension's name.
    func testPerValueParameterWins() throws {
        let page = try decode("""
        {"parts":[{"name":"拷贝漫画","type":"fixed","categories":["排行","主题"],
        "params":["ranking","theme"],"groupParam":"ignored"}]}
        """)
        let part = try XCTUnwrap(page.parts.first)
        XCTAssertEqual(part.param(for: "排行"), "ranking")
        XCTAssertEqual(part.param(for: "主题"), "theme")
    }

    /// With neither, the value itself is the parameter.
    func testValueItselfIsTheLastChoice() throws {
        let page = try decode("""
        {"parts":[{"name":"类型","categories":["全部"]}]}
        """)
        let part = try XCTUnwrap(page.parts.first)
        XCTAssertEqual(part.param(for: "全部"), "全部")
    }

    /// A random part is searched, not loaded: nhentai's Tags declares twenty.
    func testRandomPartDeclaresHowManyToTake() throws {
        let page = try decode("""
        {"parts":[{"name":"Tags","type":"random","itemType":"search","randomNumber":20,
        "categories":["a","b","c"]}]}
        """)
        let part = try XCTUnwrap(page.parts.first)
        XCTAssertTrue(part.isRandom)
        XCTAssertTrue(part.searchesInsteadOfLoading)
        XCTAssertEqual(part.randomNumber, 20)
    }

    /// A ranking page is a separate surface: a flat option list, not a
    /// dimension, so nine official sources' rankings were unreachable while the
    /// page decoded without it.
    func testRankingPageDecodes() throws {
        let page = try decode("""
        {"parts":[],"ranking":{"options":[
        {"value":"date","label":"Recent"},{"value":"week","label":"Popular Week"}]}}
        """)
        let ranking = try XCTUnwrap(page.ranking)
        XCTAssertEqual(ranking.options.map(\.value), ["date", "week"])
        XCTAssertEqual(ranking.options.first?.label, "Recent")
        XCTAssertEqual(ranking.options.first?.id, "date")
    }

    /// A page that declares no ranking reports none rather than an empty one.
    func testNoRankingIsNil() throws {
        let page = try decode("""
        {"parts":[{"name":"类型","categories":["全部"]}]}
        """)
        XCTAssertNil(page.ranking)
    }

    /// A source that declares a title but no dimensions has nothing to show.
    func testAPageWithoutPartsIsEmpty() throws {
        let page = try decode("""
        {"title":"空","parts":[]}
        """)
        XCTAssertTrue(page.parts.isEmpty)
        XCTAssertTrue((page.options ?? []).isEmpty)
    }
}
