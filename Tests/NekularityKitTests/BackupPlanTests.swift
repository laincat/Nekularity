import Foundation
import Testing
@testable import NekularityKit

/// The shape Core's `planBackup` returns, as `backup.Plan` marshals it.
@Suite struct BackupPlanTests {
    let json = """
    {
      "history": [
        {"sourceKey": "copy_manga", "id": "abc", "title": "标题", "subtitle": "作者",
         "cover": "https://x/1.jpg", "time": 1760000000000, "ep": 7, "page": 26},
        {"sourceKey": "", "id": "unresolved", "title": "未解析", "time": 1, "ep": 0, "page": 0}
      ],
      "folders": [
        {"name": "在看", "items": [
          {"sourceKey": "copy_manga", "id": "abc", "name": "标题", "author": "作者"}
        ]}
      ],
      "imageFavorites": [{"sourceKey": "copy_manga", "id": "abc", "url": "https://x/p8.jpg", "page": 8}],
      "searchHistory": ["海贼王", "one piece"],
      "sources": [{"key": "copy_manga", "script": "// js", "data": {"n": 12345678901234567890}}]
    }
    """

    @Test func decodesWhatCoreWrites() throws {
        let plan = try OrderedJSONDecoder.decode(BackupPlan.self, from: json)

        #expect(plan.history?.count == 2)
        let first = try #require(plan.history?.first)
        #expect(first.sourceKey == "copy_manga")
        #expect(first.ep == 7)
        #expect(first.page == 26)
        #expect(first.time == 1_760_000_000_000)

        // An unresolved row has no source key; the importer must skip it
        // rather than invent one.
        #expect(plan.history?.last?.sourceKey == "")

        #expect(plan.folders?.first?.name == "在看")
        #expect(plan.folders?.first?.items.first?.id == "abc")
        #expect(plan.searchHistory == ["海贼王", "one piece"])
        #expect(plan.sources?.first?.key == "copy_manga")
        #expect(plan.sources?.first?.script == "// js")
        // A big integer in source data is kept as written, not floated.
        #expect(plan.sources?.first?.data?["n"]?.stringValue == "12345678901234567890")
    }

    @Test func missingCollectionsAreEmptyNotFailures() throws {
        let plan = try OrderedJSONDecoder.decode(BackupPlan.self, from: "{}")
        #expect(plan.history == nil)
        #expect(plan.folders == nil)
        #expect(plan.searchHistory == nil)
        #expect(plan.sources == nil)
    }
}
