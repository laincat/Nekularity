import Foundation
import Testing

@testable import NekularityKit

/// The details Core sends already carried `stars`, `likesCount` and `isLiked`;
/// the client's model simply dropped them. These pin the reading, including the
/// shapes a source actually writes: a number, a string of a number, or nothing.
@Suite("Comic details rating")
struct ComicDetailsRatingTests {
    private func decode(_ json: String) throws -> ComicDetails {
        try JSONDecoder().decode(ComicDetails.self, from: Data(json.utf8))
    }

    @Test("a rating arrives as a number and is read")
    func readsNumber() throws {
        let details = try decode(#"{"title":"t","tags":[],"chapters":[],"stars":4.5,"likesCount":12,"isLiked":true}"#)
        #expect(details.stars == 4.5)
        #expect(details.likesCount == 12)
        #expect(details.isLiked == true)
    }

    @Test("a rating written as text is still a rating")
    func readsString() throws {
        // Sources that scrape a page get a string, and one of them will send it.
        let details = try decode(#"{"title":"t","tags":[],"chapters":[],"stars":"3.8","likesCount":"7"}"#)
        #expect(details.stars == 3.8)
        #expect(details.likesCount == 7)
    }

    @Test("a source with no rating says so instead of rating it zero")
    func absentIsNotZero() throws {
        let details = try decode(#"{"title":"t","tags":[],"chapters":[]}"#)
        #expect(details.stars == nil)
        #expect(details.likesCount == nil)
        #expect(details.isLiked == nil)
        // An integer rating is a valid rating, not a decode failure.
        #expect(try decode(#"{"title":"t","tags":[],"chapters":[],"stars":4}"#).stars == 4)
    }
}
