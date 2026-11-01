import Foundation
import Testing
@testable import NekularityKit

/// What a source's answer looks like once the client has read it.
///
/// A source answers in JavaScript, so Core hands the answer back as JSON. Two
/// answers are easy to get wrong: a callback written without a return value comes
/// back as the literal `null`, and a string answer arrives quoted. Both would be
/// shown to a person verbatim if this layer passed them through, and the desktop
/// client had exactly that bug with a callback's `null`.
@Suite("Source answers")
struct SourceAnswerTests {
    @Test func aQuotedAnswerLosesItsQuotes() {
        #expect(CoreClient.plainText("\"ran\"") == "ran")
        #expect(CoreClient.plainText("  \"domains refreshed\"  ") == "domains refreshed")
    }

    /// Nothing said is nothing shown: the screen has its own wording for "done".
    @Test func nothingIsAnEmptyAnswer() {
        #expect(CoreClient.plainText("null") == "")
        #expect(CoreClient.plainText(" null ") == "")
        #expect(CoreClient.plainText("") == "")
    }

    /// An empty string from the source is different from no answer, but both are
    /// empty text, so neither may leak syntax to the screen.
    @Test func anEmptyStringIsEmptyToo() {
        #expect(CoreClient.plainText("\"\"") == "")
    }

    /// Numbers and objects are not messages, but dropping them would lose what the
    /// source said; they pass through as their JSON text.
    @Test func otherValuesKeepTheirText() {
        #expect(CoreClient.plainText("true") == "true")
        #expect(CoreClient.plainText("42") == "42")
    }
}
