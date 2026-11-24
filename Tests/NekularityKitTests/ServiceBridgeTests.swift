import Foundation
import Testing
@testable import NekularityKit

private actor ServiceFixture {
    struct Call: Sendable {
        var id: String
        var method: String
        var args: JSONValue
        var grants: [String]
        var secrets: [String: String]
    }

    var calls: [Call] = []
    let replies: [String: String]

    init(_ replies: [String: String] = [:]) { self.replies = replies }

    func answer(_ record: ServiceRecord, _ method: String, _ payload: String,
                _ grants: [String], _ secrets: [String: String]) throws -> String {
        calls.append(Call(id: record.id, method: method, args: try JSONValue.parse(payload), grants: grants, secrets: secrets))
        guard let response = replies[method] else { throw CoreServiceError.core("do not display this token: fake-secret") }
        return response
    }

    nonisolated func bridge(id: String?, accounts: any ServiceAccounts = MemoryServiceAccounts(),
                            requested: [String] = ["network", "secrets", "storage"],
                            allowed: Set<String> = ["network", "secrets", "storage"]) -> ServicePackageBridge {
        ServicePackageBridge(accounts: accounts, find: { name in
            guard let id, name == id else { return nil }
            return ServiceRecord(id: id, name: id, version: "1", origin: "fixture", sha256: nil,
                                 installed: "fixture", dir: "", permissions: requested)
        }, grants: { _ in allowed }, run: { try await self.answer($0, $1, $2, $3, $4) })
    }
}

struct ServiceBridgeTests {
    @Test func bangumiRoutesAccountSearchDetailAndProgress() async throws {
        let fixture = ServiceFixture([
            "account.me": #"{"id":1,"username":"reader"}"#,
            "subject.search": #"[{"id":12,"name":"番剧"}]"#,
            "subject.detail": #"{"id":12,"name":"番剧"}"#,
            "subject.episodes": #"[{"id":8,"sort":"1.5"}]"#,
            "collection.list": #"[{"subject_id":12,"type":3,"ep_status":2}]"#,
            "collection.get": "null",
            "collection.update": #"{"ok":true}"#,
            "episode.markWatched": "null",
            "calendar.list": "[]",
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.bangumi, key: "token", value: "bgm-fixture")
        try accounts.set(service: KnownServiceID.bangumi, key: "other", value: "never needed")
        try accounts.set(service: KnownServiceID.trakt, key: "token", value: "other-account")
        var client = BangumiClient(token: "legacy") { _ in
            Issue.record("a present package must handle this call")
            return .init(status: 500)
        }
        client.service = BangumiServiceAdapter(bridge: fixture.bridge(id: KnownServiceID.bangumi, accounts: accounts))
        #expect(try await client.me().username == "reader")
        #expect(try await client.search(keyword: "  番剧 ", type: 2, limit: 5).first?.id == 12)
        #expect(try await client.subject(id: 12).title == "番剧")
        #expect(try await client.episodes(subjectID: 12).first?.sort == 1.5)
        #expect(try await client.collections(type: .doing).first?.epStatus == 2)
        #expect(try await client.collection(subjectID: 12) == nil)
        try await client.setCollection(subjectID: 12, type: .doing, epStatus: 3)
        try await client.markWatched(subjectID: 12, episodeID: 8)
        #expect(try await client.calendar().isEmpty)
        let calls = await fixture.calls
        #expect(calls.count == 9)
        #expect(calls.allSatisfy { $0.id == KnownServiceID.bangumi && !$0.grants.contains("storage") })
        #expect(calls[0].secrets == ["token": "bgm-fixture"])
        #expect(calls[1].secrets.isEmpty)
        #expect(calls[1].args["keyword"] == .string("番剧"))
        #expect(calls[1].args["limit"] == .integer(5))
        #expect(calls[6].args["ep_status"] == .integer(3))
        #expect(calls[7].args["episode_id"] == .integer(8))
        #expect(!calls.contains { $0.args.jsonText.contains("legacy") || $0.args.jsonText.contains("bgm-fixture") })
    }

    @Test func tmdbRoutesSearchDetailAndArtwork() async throws {
        let fixture = ServiceFixture([
            "series.search": #"[{"id":42,"name":"Show"}]"#,
            "series.detail": #"{"id":42,"name":"Show","nextEpisode":{"airDate":"2026-11-01","season":2,"number":3,"name":"New"}}"#,
            "series.artwork": #"{"seriesID":42,"posters":[{"filePath":"/p.jpg","url":"https://image.tmdb.org/t/p/w500/p.jpg"}],"backdrops":[],"logos":[]}"#,
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.tmdb, key: "api_key", value: "tmdb-fixture")
        var client = TMDBClient(apiKey: "legacy", language: "ja-JP") { _ in
            Issue.record("an installed TMDB package must take precedence")
            return .init(status: 500)
        }
        client.service = fixture.bridge(id: KnownServiceID.tmdb, accounts: accounts)
        #expect(try await client.search(query: "  Show ").first?.source == "tmdb")
        #expect(try await client.series(id: 42).nextEpisode?.number == 3)
        #expect(try await client.artwork(id: 42).posters.first?.filePath == "/p.jpg")
        let calls = await fixture.calls
        #expect(calls.map(\.method) == ["series.search", "series.detail", "series.artwork"])
        #expect(calls.allSatisfy { $0.id == KnownServiceID.tmdb && $0.secrets == ["api_key": "tmdb-fixture"] })
        #expect(calls[0].args["query"] == .string("Show"))
        #expect(calls[0].args["language"] == .string("ja-JP"))
        #expect(calls[2].args["id"] == .integer(42))
    }

    @Test func traktRoutesReadsAndWrites() async throws {
        let item = #"{"kind":"episode","id":12,"title":"Episode"}"#
        let fixture = ServiceFixture([
            "account.me": #"{"username":"viewer"}"#,
            "search": "[\(item)]", "watchlist.list": "[\(item)]", "watchlist.set": "null",
            "history.list": #"[{"item":\#(item),"watchedAt":"2026-11-05T00:00:00Z"}]"#,
            "history.add": #"{"ok":true}"#, "scrobble": "null",
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.trakt, key: "client_id", value: "trakt-client")
        try accounts.set(service: KnownServiceID.trakt, key: "access_token", value: "trakt-token")
        let service = TraktService(bridge: fixture.bridge(id: KnownServiceID.trakt, accounts: accounts))
        #expect(try await service.account().username == "viewer")
        let found = try await service.search(query: "  Episode ")
        let episode = try #require(found.first)
        #expect(try await service.watchlist() == found)
        try await service.setWatchlist(episode, included: false)
        let history = try await service.history()
        let date = try #require(history.first?.watchedAt)
        #expect(history.first?.item == episode)
        try await service.record(episode, watchedAt: date)
        try await service.scrobble(.stop, item: episode, progress: 87.5)
        let calls = await fixture.calls
        #expect(calls.map(\.method) == ["account.me", "search", "watchlist.list", "watchlist.set", "history.list", "history.add", "scrobble"])
        #expect(calls[1].args["query"] == .string("Episode"))
        #expect(calls[1].secrets == ["client_id": "trakt-client"])
        #expect(calls[3].args["included"] == .bool(false))
        #expect(calls[5].args["watchedAt"] == .string(date))
        #expect(calls[6].args["item"]?["id"] == .integer(12))
        #expect(calls[6].args["action"] == .string("stop"))
        #expect(calls[6].args["progress"] == .number("87.5"))
        #expect(calls[6].secrets == ["client_id": "trakt-client", "access_token": "trakt-token"])
        await #expect(throws: ServiceBridgeError.invalidPayload(service: KnownServiceID.trakt, method: "scrobble")) {
            try await service.scrobble(.stop, item: episode, progress: .nan)
        }
    }

    @Test(arguments: [KnownServiceID.bangumi, KnownServiceID.tmdb, KnownServiceID.trakt])
    func permissionsAndMissingSecretsAreErrorsBeforeRuntime(_ id: String) async throws {
        let fixture = ServiceFixture()
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: "other", key: "test", value: "different profile account")
        let denied = fixture.bridge(id: id, accounts: accounts, allowed: ["network"])
        await #expect(throws: ServiceBridgeError.permissionDenied(service: id, missing: ["secrets"])) {
            try await denied.invokeIfInstalled(id, method: "account.me", secretKeys: ["test"], as: String.self)
        }
        let notDeclared = fixture.bridge(id: id, accounts: accounts, requested: ["secrets"])
        await #expect(throws: ServiceBridgeError.permissionDenied(service: id, missing: ["network"])) {
            try await notDeclared.invokeIfInstalled(id, method: "account.me", secretKeys: ["test"], as: String.self)
        }
        let allowed = fixture.bridge(id: id, accounts: accounts)
        await #expect(throws: ServiceBridgeError.missingSecret(service: id, key: "test")) {
            try await allowed.invokeIfInstalled(id, method: "account.me", secretKeys: ["test"], as: String.self)
        }
        #expect(await fixture.calls.isEmpty)
    }

    @Test func packageFailuresAreSanitizedAndNeverTriggerFallback() async throws {
        let fixture = ServiceFixture(["subject.detail": #"{"wrong":true}"#, "episode.markWatched": #"{"ok":false}"#])
        let id = KnownServiceID.bangumi
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: id, key: "token", value: "fake-secret")
        var client = BangumiClient { _ in
            Issue.record("a package failure must never trigger fallback")
            return .init(status: 500)
        }
        client.service = BangumiServiceAdapter(bridge: fixture.bridge(id: id, accounts: accounts))
        await #expect(throws: ServiceBridgeError.executionFailed(service: id, method: "account.me")) { try await client.me() }
        await #expect(throws: ServiceBridgeError.invalidResponse(service: id, method: "subject.detail")) { try await client.subject(id: 1) }
        await #expect(throws: ServiceBridgeError.invalidResponse(service: id, method: "episode.markWatched")) {
            try await client.markWatched(subjectID: 1, episodeID: 2)
        }
    }

    @Test func absencePreservesLegacyRoutes() async throws {
        let fixture = ServiceFixture()
        let bridge = fixture.bridge(id: nil)
        var bangumi = BangumiClient(token: "old-bangumi") { request in
            #expect(request.headers["Authorization"] == "Bearer old-bangumi")
            return .init(status: 200, body: Data(#"{"id":1,"username":"legacy"}"#.utf8))
        }
        bangumi.service = BangumiServiceAdapter(bridge: bridge)
        #expect(try await bangumi.me().username == "legacy")
        var tmdb = TMDBClient(apiKey: "old-tmdb") { request in
            #expect(request.url.contains("api_key=old-tmdb"))
            if request.url.contains("/images") {
                return .init(status: 200, body: Data(#"{"id":42,"posters":[{"file_path":"/legacy.jpg"}]}"#.utf8))
            }
            return .init(status: 200, body: Data(#"{"id":42,"name":"Legacy"}"#.utf8))
        }
        tmdb.service = bridge
        #expect(try await tmdb.series(id: 42).name == "Legacy")
        #expect(try await tmdb.artwork(id: 42).posters.first?.filePath == "/legacy.jpg")
        #expect(try await TraktService(bridge: bridge, fallback: FallbackTrakt()).account().username == "legacy")
        await #expect(throws: ServiceBridgeError.notInstalled(KnownServiceID.trakt)) {
            try await TraktService(bridge: bridge).account()
        }
        #expect(await fixture.calls.isEmpty)
    }
}

private struct FallbackTrakt: TraktProvider {
    func account() async throws -> TraktAccount { TraktAccount(username: "legacy") }
    func search(query: String) async throws -> [TraktItem] { [] }
    func watchlist() async throws -> [TraktItem] { [] }
    func setWatchlist(_ item: TraktItem, included: Bool) async throws {}
    func history() async throws -> [TraktHistoryEntry] { [] }
    func record(_ item: TraktItem, watchedAt: String) async throws {}
    func scrobble(_ action: TraktScrobbleAction, item: TraktItem, progress: Double) async throws {}
}
