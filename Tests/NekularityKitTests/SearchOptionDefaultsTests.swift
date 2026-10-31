import Foundation
import Testing
@testable import NekularityKit

@Suite("Search filter defaults")
struct SearchOptionDefaultsTests {
    @Test func multiSelectDefaultsAreAJSONStringArray() throws {
        let json = #"{"label":"Category","type":"multi-select","values":["0","1","2"],"labels":["A","B","C"],"defaultValues":["0","2"]}"#
        let group = try JSONDecoder().decode(SearchOptionGroup.self, from: Data(json.utf8))
        #expect(SearchOptionGroup.decodeSelections(group.defaultSearchValue) == ["0", "2"])
        #expect(SearchOptionGroup.decodeSelections(SearchOptionGroup.encodeSelections(["a\"b", "汉字"])) == ["a\"b", "汉字"])
    }

    @Test func emptyDefaultsRemainEmpty() throws {
        let json = #"[{"label":"Multiple","type":"multi-select","values":["a"],"labels":["A"]},{"label":"Optional","type":"dropdown","values":["","1"],"labels":["None","One"],"default":""}]"#
        let groups = try JSONDecoder().decode([SearchOptionGroup].self, from: Data(json.utf8))
        #expect(groups[0].defaultSearchValue == "[]")
        #expect(groups[1].defaultSearchValue == "")
    }
}
