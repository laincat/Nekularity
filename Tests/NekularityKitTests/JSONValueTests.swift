import Foundation
import Testing
@testable import NekularityKit

@Suite struct JSONValueTests {
    @Test func keepsKeyOrderAndNumberText() throws {
        let text = #"{"10":"第十话","2":"第二话","big":12345678901234567890,"f":1.50,"e":"\u00e9\ud83d\ude00"}"#
        let v = try JSONValue.parse(text)
        guard case .object(let o) = v else { Issue.record("not an object"); return }
        #expect(o.entries.map(\.0) == ["10", "2", "big", "f", "e"])
        #expect(o["big"] == .number("12345678901234567890"))
        #expect(o["e"]?.stringValue == "é😀")
        #expect(v.jsonText == #"{"10":"第十话","2":"第二话","big":12345678901234567890,"f":1.50,"e":"é😀"}"#)
    }

    @Test func rejectsBadJSON() {
        for bad in ["", "{", #"{"a" 1}"#, "[1,]", "01x", #""\x""#, "nul", "[1] 2"] {
            #expect(throws: JSONParseError.self) { try JSONValue.parse(bad) }
        }
    }

    @Test func loneSurrogateBecomesReplacement() throws {
        #expect(try JSONValue.parse(#""\ud800x""#) == .string("\u{FFFD}x"))
    }

    @Test func escapesControlCharacters() {
        #expect(JSONValue.string("a\"b\\n\u{1}").jsonText == #""a\"b\\n\u0001""#)
    }
}

@Suite struct ModelDecodingTests {
    @Test func detailsKeepChapterOrderAndGroups() throws {
        let flat = try OrderedJSONDecoder.decode(ComicDetails.self, from:
            #"{"title":"x","tags":{"作者":["甲"],"标签":["b","a"],"bad":"skip"},"chapters":{"10":"第十话","2":"第二话"}}"#)
        #expect(flat.chapters.map(\.id) == ["10", "2"])
        #expect(flat.tags.map(\.group) == ["作者", "标签"])
        #expect(flat.tags[1].values == ["b", "a"])

        let grouped = try OrderedJSONDecoder.decode(ComicDetails.self, from:
            #"{"title":"x","chapters":{"正篇":{"c2":"二","c1":"一"},"番外":{"s1":"外"}}}"#)
        #expect(grouped.chapters.map(\.id) == ["c2", "c1", "s1"])
        #expect(grouped.chapters.map(\.group) == ["正篇", "正篇", "番外"])
    }

    @Test func pageSkipsBrokenComicsAndReadsNumberIDs() throws {
        let page = try OrderedJSONDecoder.decode(ComicPage.self, from:
            #"{"comics":[{"id":1,"title":"A"},{"title":"no id"},{"id":"b","title":"B","subTitle":"s","tags":"oops"}],"maxPage":"3"}"#)
        #expect(page.comics.map(\.id) == ["1", "b"])
        #expect(page.comics[1].subtitle == "s")
        #expect(page.comics[1].tags.isEmpty)
        #expect(page.maxPage == 3)
    }

    @Test func integersAreExact() throws {
        struct N: Decodable { var n: Int64; var u: UInt64 }
        let v = try OrderedJSONDecoder.decode(N.self, from: #"{"n":-9223372036854775808,"u":18446744073709551615}"#)
        #expect(v.n == .min)
        #expect(v.u == .max)
        #expect(throws: CoreError.self) { try OrderedJSONDecoder.decode(N.self, from: #"{"n":1.5,"u":1}"#) }
    }
}
