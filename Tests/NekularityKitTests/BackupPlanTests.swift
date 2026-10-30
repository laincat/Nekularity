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
      "imageFavorites": [
        {"sourceKey": "copy_manga", "id": "abc", "title": "标题", "author": "作者",
         "time": 1750000000000, "maxPage": 209,
         "episodes": [
           {"eid": "ch-1", "ep": 3, "maxPage": 209, "epName": "第03话",
            "imageFavorites": [
              {"page": 7, "imageKey": "https://x/p7.jpg", "eid": "ch-1", "ep": 3},
              {"page": 8, "imageKey": "https://x/p8.jpg", "eid": "ch-1", "ep": 3}
            ]}
         ],
         "other": {}}
      ],
      "searchHistory": ["海贼王", "one piece"],
      "sources": [{"key": "copy_manga", "script": "// js", "data": {"n": 12345678901234567890}}],
      "pending": {"history": [{"sourceKey": "", "id": "gone", "title": "缺源",
                               "time": 2, "ep": 0, "page": 0}]}
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

        // Kept pictures nest their pages one level down; the count is what the
        // import report shows, so it has to come from the real shape.
        let picture = try #require(plan.imageFavorites?.first)
        #expect(picture.title == "标题")
        #expect(picture.episodes?.array?.count == 1)
        #expect(picture.keptPages == 2)

        #expect(plan.pending?.rowCount == 1)
    }

    @Test func missingCollectionsAreEmptyNotFailures() throws {
        let plan = try OrderedJSONDecoder.decode(BackupPlan.self, from: "{}")
        #expect(plan.history == nil)
        #expect(plan.folders == nil)
        #expect(plan.searchHistory == nil)
        #expect(plan.sources == nil)
        #expect(plan.pending == nil)
    }
}

/// The kept pages a backup carries, mapped onto the shelf's own type.
@Suite struct BackupPictureMappingTests {
    /// The real shape Core passes through from the official app.
    let json = """
    {
      "imageFavorites": [
        {"sourceKey": "copy_manga", "id": "abc", "title": "标题", "author": "作者",
         "time": 1750000000000, "maxPage": 209,
         "episodes": [
           {"eid": "ch-1", "ep": 3, "maxPage": 209, "epName": "第03话",
            "imageFavorites": [
              {"page": 7, "imageKey": "https://x/p7.jpg", "eid": "ch-1", "ep": 3},
              {"page": 8, "imageKey": "https://x/p8.jpg", "eid": "ch-1", "ep": 3}
            ]},
           {"eid": "ch-2", "ep": 4, "imageFavorites": [
              {"page": 1, "imageKey": "https://x/q1.jpg", "eid": "ch-2", "ep": 4}
           ]}
         ], "other": {}},
        {"id": "gone", "title": "缺源", "episodes": [{"eid": "c", "ep": 0,
          "imageFavorites": [{"page": 1, "imageKey": "https://x/z.jpg"}]}]}
      ]
    }
    """

    @Test func mapsEveryKeptPageAndCountsTheOnesItCannot() throws {
        let plan = try OrderedJSONDecoder.decode(BackupPlan.self, from: json)
        let mapped = BackupImporter.keptPages(from: plan)

        #expect(mapped.pages.count == 3)
        let first = try #require(mapped.pages.first)
        #expect(first.source == "copy_manga")
        #expect(first.comicID == "abc")
        #expect(first.comicTitle == "标题")
        #expect(first.chapterID == "ch-1")
        #expect(first.chapterIndex == 3)
        #expect(first.chapterName == "第03话")
        #expect(first.page == 7)
        #expect(first.url == "https://x/p7.jpg")
        // Milliseconds on disk, seconds in the shelf file.
        #expect(first.time == 1_750_000_000)

        // The second episode has no name; the shelf stores what it has.
        #expect(mapped.pages.last?.chapterName == nil)
        #expect(mapped.pages.last?.chapterIndex == 4)

        // A picture with no source cannot land here, and says so by count.
        #expect(mapped.picturesSkipped == 1)
        #expect(mapped.pagesSkipped == 1)
    }
}
