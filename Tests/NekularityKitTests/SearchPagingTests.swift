import Foundation
import Testing
@testable import NekularityKit

@Suite("Search paging")
struct SearchPagingTests {
    private func page(maxPage: Int? = nil, next: String? = nil, comics: Int = 1) throws -> ComicPage {
        let items = (0..<comics).map { #"{"id":"\#($0)","title":"t","cover":""}"# }.joined(separator: ",")
        let cap = maxPage.map { #","maxPage":\#($0)"# } ?? ""
        let token = next.map { #","next":"\#($0)""# } ?? ""
        let json = #"{"comics":[\#(items)]\#(cap)\#(token)}"#
        return try JSONDecoder().decode(ComicPage.self, from: Data(json.utf8))
    }

    @Test func pageNumbersStopAtReportedMaximum() throws {
        var paging = SearchPaging()
        #expect(paging.next?.page == 1)
        paging.record(try page(maxPage: 2), declaresCursor: false)
        #expect(paging.next?.page == 2)
        paging.record(try page(maxPage: 2), declaresCursor: false)
        #expect(paging.next == nil)
    }

    @Test func anEmptyPageEndsAFixedPageSource() throws {
        var paging = SearchPaging()
        paging.record(try page(comics: 0), declaresCursor: false)
        #expect(paging.next == nil)
    }

    @Test func cursorsTravelUntouchedAndTheEndIsAnEmptyToken() throws {
        var paging = SearchPaging()
        #expect(paging.next?.cursor == nil)
        paging.record(try page(next: "https://e-hentai.org/?page=1"), declaresCursor: true)
        #expect(paging.next?.cursor == "https://e-hentai.org/?page=1")
        paging.record(try page(next: ""), declaresCursor: true)
        #expect(paging.next == nil)
    }

    @Test func theFirstAnswerDecidesHowTheSearchPages() throws {
        var paging = SearchPaging()
        paging.record(try page(next: "c1"), declaresCursor: true)
        // A later answer must not switch a cursor search to page numbers.
        paging.record(try page(maxPage: 9, next: "c2"), declaresCursor: false)
        #expect(paging.mode == .cursor)
        #expect(paging.next?.cursor == "c2")
    }

    @Test func aFailureStopsPaging() throws {
        var paging = SearchPaging()
        paging.record(try page(maxPage: 5), declaresCursor: false)
        paging.fail()
        #expect(paging.next == nil)
        #expect(paging.maxPage == 1)
    }
}
