import XCTest
@testable import NekularityKit

/// Six official sources take the source's own handle as the fourth argument of
/// favorites.addOrDelFavorite, and wnacg builds its delete URL from it: without
/// one the removal asks for "del-id-undefined" and quietly does nothing.
final class FavoriteHandleTests: XCTestCase {
    private func decode(_ json: String) throws -> Comic {
        try JSONDecoder().decode(Comic.self, from: Data(json.utf8))
    }

    func testAComicKeepsTheHandleItWasListedWith() throws {
        let comic = try decode(#"{"id":"c1","title":"t","favoriteId":"fav-9"}"#)
        XCTAssertEqual(comic.favoriteId, "fav-9")
    }

    /// A source that does not provide one leaves it nil rather than guessing.
    func testAComicWithoutAHandle() throws {
        XCTAssertNil(try decode(#"{"id":"c2","title":"t"}"#).favoriteId)
    }

    /// loadInfo may carry it too, so the details screen works even when the
    /// comic came from a page that did not.
    func testDetailsCarryTheHandle() throws {
        let details = try JSONDecoder().decode(ComicDetails.self,
                                               from: Data(#"{"title":"t","favoriteId":"fav-5"}"#.utf8))
        XCTAssertEqual(details.favoriteId, "fav-5")
    }
}
