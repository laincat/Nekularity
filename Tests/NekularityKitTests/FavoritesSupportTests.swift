import XCTest
@testable import NekularityKit

/// The three favorite shapes do not overlap: nhentai has one folder and no
/// folder list, ehentai has folders but no list function, wnacg has both. A
/// client that guesses calls a function the source does not define.
final class FavoritesSupportTests: XCTestCase {
    func testASourceWithoutFavoritesSupportsNothing() {
        let support = FavoritesSupport(supported: false, multiFolder: false, folders: false, canLoad: false)
        XCTAssertFalse(support.supported)
        XCTAssertFalse(support.hasList)
    }

    /// ehentai: folders and a toggle, but nothing to read — so no list.
    func testFoldersWithoutAListHaveNoList() {
        let support = FavoritesSupport(supported: true, multiFolder: true, folders: true, canLoad: false)
        XCTAssertTrue(support.supported)
        XCTAssertFalse(support.hasList)
    }

    /// nhentai: one folder and a list, but no folder list to choose from.
    func testSingleFolderSourceHasAList() {
        let support = FavoritesSupport(supported: true, multiFolder: false, folders: false, canLoad: true)
        XCTAssertTrue(support.hasList)
        XCTAssertFalse(support.folders)
    }

    /// wnacg: both.
    func testFullSourceHasBoth() {
        let support = FavoritesSupport(supported: true, multiFolder: true, folders: true, canLoad: true)
        XCTAssertTrue(support.hasList)
        XCTAssertTrue(support.folders)
    }
}
