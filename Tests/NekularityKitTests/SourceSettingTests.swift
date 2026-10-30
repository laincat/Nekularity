import Foundation
import Testing
@testable import NekularityKit

@Suite struct SourceSettingTests {
    /// Core answers a source's settings declaration as JSON; the client has to
    /// keep values that are not strings as they were written.
    @Test func decodesADeclaration() throws {
        let json = #"""
        [{"key":"region","title":"CDN线路","type":"select",
          "default":"1","options":[{"value":"1","text":"大陆线路"},{"value":"0","text":"海外线路"}]},
         {"key":"autoLogin","title":"自动登录","type":"switch","default":true},
         {"key":"limits","title":"上限","type":"input","default":20,"validator":"^[0-9]+$"},
         {"key":"refresh","title":"刷新","type":"callback"}]
        """#
        let list = try JSONDecoder().decode([SourceSetting].self, from: Data(json.utf8))
        #expect(list.count == 4)
        #expect(list[0].key == "region")
        #expect(list[0].kind == .choice)
        #expect(list[0].options?.count == 2)
        #expect(list[0].options?[1].text == "海外线路")
        #expect(list[0].default?.stringValue == "1")
        // A boolean and a number keep their shape.
        #expect(list[1].kind == .toggle)
        #expect(list[1].default?.stringValue == "true")
        #expect(list[2].kind == .text)
        #expect(list[2].default?.stringValue == "20")
        #expect(list[2].validator == "^[0-9]+$")
        #expect(list[3].kind == .action)
    }

    @Test func anEmptyAnswerIsAnEmptyList() throws {
        let list = try JSONDecoder().decode([SourceSetting].self, from: Data("[]".utf8))
        #expect(list.isEmpty)
    }
}
