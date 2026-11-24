import Foundation
import Testing
@testable import NekularityKit

@Suite("Novel HTML text extraction")
struct NovelTextExtractorTests {
    @Test func extractsParagraphsAndStripsDangerousSubtrees() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Ignored Title</title><style>.hidden{display:none}</style></head>
        <body>
          <!-- editorial note -->
          <div class="content" data-chapter="ch1">
            <h1>第一章 星塔</h1>
            <p>第一段 &amp; <em>强调文字</em></p>
            <script>window.location = "https://evil.invalid"; alert("xss")</script>
            <style>p { color: red; }</style>
            <noscript>请启用脚本</noscript>
            <svg><text>SVG Noise</text></svg>
            <iframe src="https://evil.invalid">Frame Text</iframe>
            <template><p>Template Hidden</p></template>
            <p>第二段<br>第三段<br/>第四段<br />第五段</p>
            <img src="https://novel.test/p1.png" alt="ignore" />
          </div>
        </body>
        </html>
        """
        let doc = NovelTextExtractor.extract(html: html)
        #expect(doc.paragraphs == [
            "第一章 星塔",
            "第一段 & 强调文字",
            "第二段",
            "第三段",
            "第四段",
            "第五段",
        ])
        #expect(!doc.plainText.contains("alert"))
        #expect(!doc.plainText.contains("Ignored Title"))
        #expect(!doc.plainText.contains("SVG Noise"))
        #expect(!doc.plainText.contains("Frame Text"))
        #expect(!doc.plainText.contains("Template Hidden"))
        #expect(!doc.plainText.contains("editorial note"))
    }

    @Test func decodesEntitiesOnceAndNormalisesSpaces() {
        let html = "<p>\u{3000}\u{3000}Hello&nbsp;&nbsp;World&#33; &#x1F4D6; &amp;lt;script&amp;gt; &ldquo;引文&rdquo;</p>"
        let doc = NovelTextExtractor.extract(html: html)
        #expect(doc.paragraphs == ["Hello World! \u{1F4D6} &lt;script&gt; \u{201C}引文\u{201D}"])
    }

    @Test func preservesLiteralAngleBracketsAndQuotedAttributes() {
        let html = #"<p data-expr="a > b">x < y 且 a > b</p><svg /><p>Self-closing SVG kept tail</p>"#
        let doc = NovelTextExtractor.extract(html: html)
        #expect(doc.paragraphs == ["x < y 且 a > b", "Self-closing SVG kept tail"])
    }

    @Test func handlesPlainTextAndUnclosedScriptSafely() {
        let plain = NovelTextExtractor.extract(html: "段落一\r\n\r\n段落二\n段落三")
        #expect(plain.paragraphs == ["段落一", "段落二", "段落三"])
        #expect(plain.plainText == "段落一\n\n段落二\n\n段落三")
        #expect(plain.characterCount == 9)

        let unclosed = NovelTextExtractor.extract(html: "<p>前文</p><script>neverClosed()")
        #expect(unclosed.paragraphs == ["前文"])

        let empty = NovelTextExtractor.extract(html: "   \n\t <p>&nbsp;</p> ")
        #expect(empty.isEmpty)
        #expect(empty.plainText.isEmpty)
    }
}
