import Foundation
import Testing

@testable import NekularityKit

/// The shapes here are copied from Core's `video` package, field name for field
/// name, because that is the contract the client decodes. A `title` where Core
/// says `name` does not fail loudly: the whole payload stops decoding and the
/// screen spins for ever, which is what the interface test saw as "the detail page
/// lists no episode".
@Suite("Video models")
struct VideoModelsTests {
    @Test func detailsDecodeCoreShape() throws {
        let json = """
        {"id":"clip","title":"Probe Clip","description":"a clip","tags":["t"],
         "cover":"https://example.invalid/c.jpg",
         "lines":[{"id":"line1","name":"Line 1",
                   "episodes":[{"id":"ep1","title":"Episode 1"},{"id":"ep2","title":"Episode 2"}]}]}
        """
        let details = try JSONDecoder().decode(VideoDetails.self, from: Data(json.utf8))
        #expect(details.id == "clip")
        #expect(details.lines.count == 1)
        // Core spells the line's label `name`.
        #expect(details.lines.first?.title == "Line 1")
        #expect(details.lines.first?.episodes.map(\.title) == ["Episode 1", "Episode 2"])
    }

    @Test func aLineWithNoEpisodesStillDecodes() throws {
        let json = #"{"id":"v","title":"V","lines":[{"id":"l","name":"L","episodes":[]}]}"#
        let details = try JSONDecoder().decode(VideoDetails.self, from: Data(json.utf8))
        #expect(details.lines.first?.episodes.isEmpty == true)
    }

    @Test func pageDecodeCoreShape() throws {
        let json = """
        {"items":[{"id":"clip","title":"Probe Clip","subtitle":"loopback",
                   "cover":"https://example.invalid/c.jpg","extra":{"episodes":"1"}}],
         "next":"2"}
        """
        let page = try JSONDecoder().decode(VideoPage.self, from: Data(json.utf8))
        #expect(page.items.first?.title == "Probe Clip")
        #expect(page.items.first?.extra?["episodes"] == "1")
        #expect(page.next == "2")
    }

    @Test func playDecode() throws {
        // Core sends `http.Header`, which is a map of lists. The string form below
        // is what the source fixture writes; Core normalises it, and decoding the
        // normalised shape as a map of strings failed the whole answer — the detail
        // page then said the source gave no playable address.
        let json = """
        {"url":"http://127.0.0.1:18731/clip.mp4","format":"mp4",
         "headers":{"Referer":["http://127.0.0.1:18731/"]}}
        """
        let play = try JSONDecoder().decode(VideoPlay.self, from: Data(json.utf8))
        #expect(play.isPlayable)
        // The headers are the reason a source that checks Referer can play at all.
        #expect(play.headers?["Referer"] == ["http://127.0.0.1:18731/"])
        #expect(play.requestHeaders["Referer"] == "http://127.0.0.1:18731/")
    }

    @Test func repeatedHeaderTakesTheFirstValue() throws {
        let json = """
        {"url":"http://x/y","headers":{"Accept":["a","b"],"Empty":[]}}
        """
        let play = try JSONDecoder().decode(VideoPlay.self, from: Data(json.utf8))
        #expect(play.requestHeaders["Accept"] == "a")
        // A header with no values is left out rather than sent empty.
        #expect(play.requestHeaders["Empty"] == nil)
    }

    @Test func encryptedAndSniffOnlyAreNotPlayable() throws {
        let encrypted = try JSONDecoder().decode(
            VideoPlay.self, from: Data(#"{"url":"http://x/y","encrypted":true}"#.utf8))
        #expect(encrypted.isPlayable == false)

        let sniff = try JSONDecoder().decode(
            VideoPlay.self, from: Data(#"{"sniff":{"page":"http://x/page"}}"#.utf8))
        #expect(sniff.isPlayable == false)
        #expect(sniff.sniff?.page == "http://x/page")
    }
}
