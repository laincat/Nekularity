import Testing
@testable import NekularityKit

/// The reader's movement rules. Each case here was a way to jump when the
/// reader should have stayed put.
@Suite struct ReaderNavigationTests {
    @Test func previousExistsOnlyAfterTheFirstChapter() {
        #expect(ReaderNavigation.canGoPrevious(index: 0) == false)
        #expect(ReaderNavigation.canGoPrevious(index: 1))
    }

    @Test func nextExistsUntilTheLastChapter() {
        #expect(ReaderNavigation.canGoNext(index: 0, chapterCount: 3))
        #expect(ReaderNavigation.canGoNext(index: 2, chapterCount: 3) == false)
        // A comic with no chapters cannot offer a next one.
        #expect(ReaderNavigation.canGoNext(index: 0, chapterCount: 0) == false)
    }

    @Test func autoContinueMovesOnAtTheEndOfAChapter() {
        #expect(ReaderNavigation.autoNextIndex(autoNext: true, pageCount: 20, lastPage: 20,
                                               index: 0, chapterCount: 3) == 1)
    }

    @Test func autoContinueStaysPutWhenItIsOff() {
        #expect(ReaderNavigation.autoNextIndex(autoNext: false, pageCount: 20, lastPage: 20,
                                               index: 0, chapterCount: 3) == nil)
    }

    @Test func aSinglePageChapterIsNotAScroll() {
        #expect(ReaderNavigation.autoNextIndex(autoNext: true, pageCount: 1, lastPage: 1,
                                               index: 0, chapterCount: 3) == nil)
    }

    @Test func pageOneHasNotBeenScrolledYet() {
        // Opening a chapter puts the reader on page one; that alone must not
        // carry it into the next chapter.
        #expect(ReaderNavigation.autoNextIndex(autoNext: true, pageCount: 20, lastPage: 1,
                                               index: 0, chapterCount: 3) == nil)
    }

    @Test func theLastChapterHasNowhereToGo() {
        #expect(ReaderNavigation.autoNextIndex(autoNext: true, pageCount: 20, lastPage: 20,
                                               index: 2, chapterCount: 3) == nil)
    }
}
