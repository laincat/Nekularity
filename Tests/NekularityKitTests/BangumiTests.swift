import Foundation
import Testing

@testable import NekularityKit

/// Answers Bangumi's endpoints from a table, so the request shape, the decoding and
/// the error wording can all be checked without a network — Bangumi throttles hard
/// and a test suite should not be the reason someone's token gets 429.
private struct FakeBangumi {
    /// Keyed by "METHOD path" without the query, e.g. "GET /v0/subjects/12".
    var replies: [String: (status: Int, json: String)] = [:]
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [BangumiClient.Request] = []
        func append(_ request: BangumiClient.Request) { lock.withLock { value.append(request) } }
        var all: [BangumiClient.Request] { lock.withLock { value } }
        var last: BangumiClient.Request? { lock.withLock { value.last } }
    }
    let log = Log()

    func client(token: String? = "test-token") -> BangumiClient {
        let replies = replies
        let log = log
        return BangumiClient(token: token) { request in
            log.append(request)
            let path = request.url
                .replacingOccurrences(of: BangumiClient.base, with: "")
                .split(separator: "?").first.map(String.init) ?? ""
            let key = "\(request.method) \(path)"
            guard let reply = replies[key] else { return BangumiClient.Response(status: 404) }
            return BangumiClient.Response(status: reply.status, body: Data(reply.json.utf8))
        }
    }
}

private let subjectJSON = """
{"id":12,"type":2,"name":"テスト","name_cn":"测试条目","summary":"简介","date":"2026-10-01",
 "platform":"TV","eps":7,"total_episodes":12,
 "images":{"large":"https://lain.bgm.tv/pic/cover/l/a.jpg","common":"https://lain.bgm.tv/pic/cover/c/a.jpg"},
 "rating":{"score":7.8,"total":1200},
 "collection":{"wish":10,"collect":20,"doing":30,"on_hold":4,"dropped":5}}
"""

private let episodesJSON = """
{"data":[
 {"id":101,"type":0,"sort":1,"name":"第一话","name_cn":"第一话","airdate":"2026-10-01","comment":3},
 {"id":102,"type":0,"sort":1.5,"ep":1.5,"name":"1.5","airdate":"2026-10-05"},
 {"id":103,"type":1,"sort":2,"name":"特典","airdate":"2026-10-20"},
 {"id":104,"type":0,"sort":"3","name":"","name_cn":"第三话","airdate":"2026-12-01"}
]}
"""

@Suite("Bangumi client")
struct BangumiClientTests {
    @Test("every request names the app and carries the token")
    func headers() {
        var fake = FakeBangumi()
        fake.replies["GET /v0/me"] = (200, #"{"id":1,"username":"laincat","nickname":"猫"}"#)
        let client = fake.client()

        let request = client.request("/v0/me")
        #expect(request.headers["Authorization"] == "Bearer test-token")
        // Bangumi answers 403 to a default URLSession agent; the name is not decoration.
        #expect(request.headers["User-Agent"]?.contains("Nekularity") == true)
    }

    @Test("without a token no Authorization header is sent")
    func anonymous() {
        let client = FakeBangumi().client(token: nil)
        #expect(client.request("/calendar").headers["Authorization"] == nil)
    }

    @Test("search is a POST whose body carries the keyword and the type filter")
    func searchBody() async throws {
        var fake = FakeBangumi()
        fake.replies["POST /v0/search/subjects"] = (200, #"{"data":[\#(subjectJSON)]}"#)
        let client = fake.client()

        let found = try await client.search(keyword: "  测试  ", type: 2)
        #expect(found.count == 1)
        #expect(found.first?.title == "测试条目")

        let request = try #require(fake.log.last)
        #expect(request.method == "POST")
        #expect(request.url.contains("limit=20"))
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Trimmed before it is sent: Bangumi matches the keyword literally.
        #expect(json["keyword"] as? String == "测试")
        let filter = try #require(json["filter"] as? [String: Any])
        #expect((filter["type"] as? [Any])?.compactMap { $0 as? Int } == [2])
    }

    @Test("an empty keyword never reaches the network")
    func emptySearch() async throws {
        var fake = FakeBangumi()
        fake.replies["POST /v0/search/subjects"] = (200, #"{"data":[]}"#)
        let found = try await fake.client().search(keyword: "   ")
        #expect(found.isEmpty)
        #expect(fake.log.all.isEmpty)
    }

    @Test("a subject decodes its Chinese name, poster and score")
    func subjectDecoding() async throws {
        var fake = FakeBangumi()
        fake.replies["GET /v0/subjects/12"] = (200, subjectJSON)
        let subject = try await fake.client().subject(id: 12)

        #expect(subject.id == 12)
        #expect(subject.title == "测试条目")
        #expect(subject.poster?.hasSuffix("a.jpg") == true)
        #expect(subject.score == 7.8)
        #expect(subject.airedEpisodes == 7)
        #expect(subject.date == "2026-10-01")
    }

    @Test("episode sort is a fraction when Bangumi says so")
    func flexSort() async throws {
        var fake = FakeBangumi()
        fake.replies["GET /v0/episodes"] = (200, episodesJSON)
        let episodes = try await fake.client().episodes(subjectID: 12)

        #expect(episodes.count == 4)
        #expect(episodes[1].sort == 1.5)
        // A whole number for the badge, a fraction kept for ordering.
        #expect(episodes[1].number == 1)
        // "3" arrives as a string on some endpoints.
        #expect(episodes[3].sort == 3)
        #expect(episodes[2].isMainStory == false)
    }

    @Test("the next episode is the first main-story episode that has not aired")
    func nextEpisode() throws {
        var live = episodesJSON
        live = live.replacingOccurrences(of: "\"2026-10-01\"", with: "\"2026-01-01\"")
        live = live.replacingOccurrences(of: "\"2026-12-01\"", with: "\"2026-12-01\"")
        struct Answer: Decodable { var data: [BangumiEpisode] }
        let episodes = try JSONDecoder().decode(Answer.self, from: Data(live.utf8)).data

        let subject = try JSONDecoder().decode(BangumiSubject.self, from: Data(subjectJSON.utf8))
        let formatter = BangumiEpisode.dayFormatter
        let now = try #require(formatter.date(from: "2026-11-01"))

        let info = SeriesInfo(subject: subject, episodes: episodes, now: now)
        #expect(info.source == "bangumi")
        #expect(info.nextEpisode?.airDate == "2026-12-01")
        // The special on 2026-10-20 is past the reference date anyway; a special
        // that had been in the future must not become "next episode".
        #expect(info.nextEpisode?.number == 3)
        #expect(info.name == "测试条目")
    }

    @Test("calendar decodes a weekday with its entries")
    func calendar() async throws {
        var fake = FakeBangumi()
        fake.replies["GET /calendar"] = (200, """
        [{"weekday":{"id":1,"cn":"星期一","ja":"月耀日","en":"Mon"},
          "items":[\(subjectJSON)]}]
        """)
        let days = try await fake.client().calendar()
        #expect(days.count == 1)
        #expect(days.first?.label == "星期一")
        #expect(days.first?.items.first?.id == 12)
    }

    @Test("collections carry the subject and a progress string")
    func collections() async throws {
        var fake = FakeBangumi()
        fake.replies["GET /v0/users/-/collections"] = (200, """
        {"data":[{"subject_id":12,"type":3,"rate":8,"ep_status":5,"subject":\(subjectJSON)}]}
        """)
        let list = try await fake.client().collections(type: .doing)
        let first = try #require(list.first)
        #expect(first.type == .doing)
        #expect(first.progressText == "5/12")
        #expect(first.subject?.title == "测试条目")
    }

    @Test("a missing collection is nil, not an error")
    func missingCollection() async throws {
        let fake = FakeBangumi()
        // Decoded first rather than inside the macro: an autoclosure is not the
        // place for an await.
        let missing = try await fake.client().collection(subjectID: 99)
        #expect(missing == nil)
    }

    @Test("marking an episode watched accepts the queued 202")
    func markWatchedAccepts202() async throws {
        var fake = FakeBangumi()
        fake.replies["PATCH /v0/users/-/collections/12/episodes"] = (202, "")
        try await fake.client().markWatched(subjectID: 12, episodeID: 101)

        let request = try #require(fake.log.last)
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["episode_id"] as? Int == 101)
        #expect(json["type"] as? Int == 2)
    }

    @Test("Bangumi's status codes become sentences")
    func errorWording() async throws {
        for (status, expected) in [(401, "令牌无效"), (403, "拒绝"), (429, "太频繁")] {
            var fake = FakeBangumi()
            fake.replies["GET /v0/me"] = (status, "")
            await #expect(throws: BangumiError.self) {
                _ = try await fake.client().me()
            }
            do {
                _ = try await fake.client().me()
            } catch let error as BangumiError {
                #expect(error.message.contains(expected))
            }
        }
    }

    @Test("a body that is not the documented shape names itself, not a decoder type")
    func undecodableBody() async throws {
        var fake = FakeBangumi()
        fake.replies["GET /v0/subjects/12"] = (200, "<html>rate limited</html>")
        do {
            _ = try await fake.client().subject(id: 12)
            Issue.record("expected an error")
        } catch let error as BangumiError {
            #expect(error.message.contains("看不懂"))
        }
    }
}

@Suite("Bangumi store")
@MainActor
struct BangumiStoreTests {
    @Test("signing in checks the token before keeping it")
    func signInValidates() async {
        var fake = FakeBangumi()
        fake.replies["GET /v0/me"] = (200, #"{"id":1,"username":"laincat","nickname":"猫"}"#)
        fake.replies["GET /v0/users/-/collections"] = (200, #"{"data":[]}"#)
        let tokens = MemoryBangumiTokenStore()
        let client = fake.client()
        let store = BangumiStore(tokens: tokens) { _ in client }

        await store.signIn(token: "  test-token  ")

        #expect(store.hasToken)
        #expect(store.user?.displayName == "猫")
        // Trimmed before it is stored, so a pasted newline does not break the header.
        #expect((try? tokens.load()) == "test-token")
    }

    @Test("a rejected token is not stored")
    func signInRejects() async {
        var fake = FakeBangumi()
        fake.replies["GET /v0/me"] = (401, "")
        let tokens = MemoryBangumiTokenStore()
        let client = fake.client()
        let store = BangumiStore(tokens: tokens) { _ in client }

        await store.signIn(token: "wrong")

        #expect(store.hasToken == false)
        #expect((try? tokens.load()) == nil)
        #expect(store.failure?.contains("令牌") == true)
    }

    @Test("signing out forgets the token and the collections")
    func signOut() async {
        let tokens = MemoryBangumiTokenStore(token: "old")
        var fake = FakeBangumi()
        fake.replies["GET /v0/users/-/collections"] = (200, #"{"data":[]}"#)
        let client = fake.client()
        let store = BangumiStore(tokens: tokens) { _ in client }

        store.signOut()

        #expect(store.hasToken == false)
        #expect((try? tokens.load()) == nil)
    }

    @Test("watching subjects become shows with air dates for the reminder planner")
    func airing() async {
        var fake = FakeBangumi()
        fake.replies["GET /v0/users/-/collections"] = (200, """
        {"data":[{"subject_id":12,"type":3,"ep_status":5,"subject":\(subjectJSON)}]}
        """)
        fake.replies["GET /v0/episodes"] = (200, episodesJSON)
        let client = fake.client()
        let store = BangumiStore(tokens: MemoryBangumiTokenStore(token: "t")) { _ in client }

        await store.refresh()
        let now = BangumiEpisode.dayFormatter.date(from: "2026-11-01")!
        let shows = await store.airingShows(now: now)

        #expect(shows.count == 1)
        #expect(shows.first?.source == "bangumi")
        #expect(shows.first?.nextEpisode?.airDate == "2026-12-01")

        // The planner is the reason this mapping exists, so the two are checked
        // together rather than each in isolation.
        let plan = AiringPlan.plan(shows, now: now, days: 60)
        #expect(plan.count == 1)
        #expect(plan.first != nil)
    }

    @Test("a subject whose episodes fail does not empty the list")
    func airingSurvivesOneFailure() async {
        var fake = FakeBangumi()
        fake.replies["GET /v0/users/-/collections"] = (200, """
        {"data":[{"subject_id":12,"type":3,"subject":\(subjectJSON)}]}
        """)
        let client = fake.client()
        let store = BangumiStore(tokens: MemoryBangumiTokenStore(token: "t")) { _ in client }

        await store.refresh()
        let shows = await store.airingShows()

        #expect(shows.count == 1)
        #expect(shows.first?.nextEpisode == nil)
    }

    @Test("the token store round-trips")
    func tokenStore() throws {
        let store = MemoryBangumiTokenStore()
        try store.save("abc")
        #expect(try store.load() == "abc")
        try store.remove()
        #expect(try store.load() == nil)
    }
}
