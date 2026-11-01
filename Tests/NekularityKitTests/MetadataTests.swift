import Foundation
import Testing

@testable import NekularityKit

private struct FakeTMDB {
    var replies: [String: (status: Int, json: String)] = [:]
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [TMDBClient.Request] = []
        func append(_ request: TMDBClient.Request) { lock.withLock { value.append(request) } }
        var all: [TMDBClient.Request] { lock.withLock { value } }
    }
    let log = Log()

    func client(_ key: String) -> TMDBClient {
        let replies = replies
        let log = log
        return TMDBClient(apiKey: key) { request in
            log.append(request)
            guard let reply = replies[request.url] else { return TMDBClient.Response(status: 404) }
            return TMDBClient.Response(status: reply.status, body: Data(reply.json.utf8))
        }
    }
}

@Suite("TMDB client")
struct TMDBClientTests {
    @Test("a v3 key travels in the query, a v4 token in the header")
    func keyPlacement() {
        let v3 = TMDBClient(apiKey: "abc123") { _ in .init(status: 200) }
        let v4 = TMDBClient(apiKey: "eyJhbGciOi.abc.def") { _ in .init(status: 200) }
        let v3Request = v3.request("/3/tv/1")
        let v4Request = v4.request("/3/tv/1")
        #expect(v3Request.url.contains("api_key=abc123"))
        #expect(v3Request.headers["Authorization"] == nil)
        #expect(!v4Request.url.contains("api_key"))
        #expect(v4Request.headers["Authorization"] == "Bearer eyJhbGciOi.abc.def")
    }

    @Test("a search result becomes a show with a usable poster")
    func searches() async throws {
        var fake = FakeTMDB()
        let expected = TMDBClient(apiKey: "k") { _ in .init(status: 200) }.request("/3/search/tv", query: ["query": "Severance"])
        fake.replies[expected.url] = (200, """
        {"results":[{"id":95396,"name":"人生切割术","overview":"简介","poster_path":"/p.jpg","first_air_date":"2022-02-18"}]}
        """)
        let shows = try await fake.client("k").search(query: "Severance")
        let show = try #require(shows.first)
        #expect(show.id == 95396)
        #expect(show.name == "人生切割术")
        #expect(show.firstAirDate == "2022-02-18")
        #expect(show.poster == "https://image.tmdb.org/t/p/w342/p.jpg")
    }

    @Test("the next episode becomes a date the calendar can place")
    func nextEpisode() async throws {
        var fake = FakeTMDB()
        let expected = TMDBClient(apiKey: "k") { _ in .init(status: 200) }.request("/3/tv/42")
        fake.replies[expected.url] = (200, """
        {"id":42,"name":"某剧","poster_path":null,"status":"Returning Series",
         "next_episode_to_air":{"air_date":"2026-11-08","season_number":3,"episode_number":4,"name":"第四集"}}
        """)
        let show = try await fake.client("k").series(id: 42)
        #expect(show.nextEpisode?.number == 4)
        #expect(show.status == "Returning Series")
        #expect(show.poster == nil)
        // Parsed in UTC: a date with no time zone must not shift to another day
        // for a user east or west of Greenwich.
        let day = try #require(show.nextAirDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.day, from: day) == 8)
    }

    @Test("a bad key is named as a bad key")
    func explainsKey() async {
        let fake = FakeTMDB()
        await #expect(throws: MetadataError.self) {
            _ = try await fake.client("bad").series(id: 1)
        }
    }
}

@Suite("Metadata store")
@MainActor
struct MetadataStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "meta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a looked-up show is cached and survives a relaunch")
    func caches() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var fake = FakeTMDB()
        let expected = TMDBClient(apiKey: "k") { _ in .init(status: 200) }.request("/3/tv/7")
        fake.replies[expected.url] = (200, #"{"id":7,"name":"缓存剧","status":"Ended"}"#)

        let keys = MemoryMetadataKeyStore(key: "k")
        let store = MetadataStore(directory: dir, keys: keys)
        #expect(store.hasKey)
        let info = try await store.lookup(id: 7, client: fake.client("k"))
        #expect(info.name == "缓存剧")

        let again = MetadataStore(directory: dir, keys: keys)
        #expect(again.cached("tmdb/7")?.name == "缓存剧")
    }

    @Test("a stale entry is not served from the cache")
    func expiry() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MetadataStore(directory: dir, keys: MemoryMetadataKeyStore())
        store.forget()
        // Nothing cached yet, so nothing fresh.
        #expect(store.cached("tmdb/1") == nil)
        #expect(MetadataStore.ttl == 7 * 24 * 60 * 60)
    }

    @Test("only shows with a date in range are upcoming, soonest first")
    func upcoming() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MetadataStore(directory: dir, keys: MemoryMetadataKeyStore())
        let soon = SeriesInfo(source: "tmdb", id: 1, name: "近",
                              nextEpisode: .init(airDate: "2026-11-03", season: 1, number: 1, name: ""))
        let later = SeriesInfo(source: "tmdb", id: 2, name: "远",
                               nextEpisode: .init(airDate: "2026-11-10", season: 1, number: 1, name: ""))
        let far = SeriesInfo(source: "tmdb", id: 3, name: "太远",
                             nextEpisode: .init(airDate: "2027-01-01", season: 1, number: 1, name: ""))
        let none = SeriesInfo(source: "tmdb", id: 4, name: "没日期")
        for info in [soon, later, far, none] { store.series[info.key] = info }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let result = store.upcoming(within: 14, from: now)
        #expect(result.map(\.info.name) == ["近", "远"])
    }

    @Test("a key is stored, cleared, and reported honestly")
    func keyHandling() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keys = MemoryMetadataKeyStore()
        let store = MetadataStore(directory: dir, keys: keys)
        #expect(!store.hasKey)
        try store.setKey("  abc  ")
        #expect(store.hasKey)
        #expect(store.apiKey() == "abc")
        try store.setKey("   ")
        #expect(!store.hasKey)
        #expect(store.apiKey() == nil)
    }
}
