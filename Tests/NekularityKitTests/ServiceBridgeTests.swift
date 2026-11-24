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
        let args = try JSONValue.parse(payload)
        calls.append(Call(id: record.id, method: method, args: args, grants: grants, secrets: secrets))
        let replyKey = method == "collection.get" && args["subjectId"] != nil ? "collection.get.one" : method
        guard let response = replies[replyKey] else { throw CoreServiceError.core("do not display this token: fake-secret") }
        if response == "unsupported" {
            return #"{"ok":false,"service":"\#(record.id)","method":"\#(method)","error":{"code":"UNSUPPORTED_METHOD"}}"#
        }
        return #"{"ok":true,"service":"\#(record.id)","method":"\#(method)","data":\#(response)}"#
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
            "metadata.search": #"{"items":[{"id":"12","type":"2","name":"Anime","nameCn":"番剧","score":8.5}]}"#,
            "metadata.detail": #"{"id":12,"name":"Anime","nameCn":"番剧","totalEpisodes":13,"episodes":[{"id":8,"sort":"1.5","nameCn":"番外"}]}"#,
            "collection.get": #"{"items":[{"subjectId":12,"type":3,"epStatus":2}]}"#,
            "collection.get.one": #"{"item":null}"#,
            "collection.update": #"{"updated":true}"#,
            "episode.update": #"{"updated":true}"#,
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.bangumi, key: "access_token", value: "bgm-fixture")
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
        let calls = await fixture.calls
        #expect(calls.count == 8)
        #expect(calls.allSatisfy { $0.id == KnownServiceID.bangumi && !$0.grants.contains("storage") })
        #expect(calls[0].secrets == ["access_token": "bgm-fixture"])
        #expect(calls[1].secrets.isEmpty)
        #expect(calls[1].args["keyword"] == .string("番剧"))
        #expect(calls[1].args["limit"] == .integer(5))
        #expect(calls[3].args["includeEpisodes"] == .bool(true))
        #expect(calls[6].args["epStatus"] == .integer(3))
        #expect(calls[7].args["episodeIds"] == .array([.integer(8)]))
        #expect(!calls.contains { $0.args.jsonText.contains("legacy") || $0.args.jsonText.contains("bgm-fixture") })
    }

    @Test func tmdbRoutesSearchDetailAndArtwork() async throws {
        let fixture = ServiceFixture([
            "metadata.search": #"{"items":[{"id":42,"title":"Show"}]}"#,
            "metadata.detail": #"{"id":42,"title":"Show","releaseDate":"2026-11-01","status":"Returning Series"}"#,
            "artwork.list": #"{"id":42,"posters":[{"filePath":"/p.jpg","url":"https://image.tmdb.org/t/p/w500/p.jpg"}],"backdrops":[],"logos":[]}"#,
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.tmdb, key: "api_key", value: "tmdb-fixture")
        var client = TMDBClient(apiKey: "legacy", language: "ja-JP") { _ in
            Issue.record("an installed TMDB package must take precedence")
            return .init(status: 500)
        }
        client.service = fixture.bridge(id: KnownServiceID.tmdb, accounts: accounts)
        #expect(try await client.search(query: "  Show ").first?.source == "tmdb")
        #expect(try await client.series(id: 42).firstAirDate == "2026-11-01")
        #expect(try await client.artwork(id: 42).posters.first?.filePath == "/p.jpg")
        let calls = await fixture.calls
        #expect(calls.map(\.method) == ["metadata.search", "metadata.detail", "artwork.list"])
        #expect(calls.allSatisfy { $0.id == KnownServiceID.tmdb && $0.secrets == ["api_key": "tmdb-fixture"] })
        #expect(calls[0].args["query"] == .string("Show"))
        #expect(calls[0].args["language"] == .string("ja-JP"))
        #expect(calls[0].args["mediaType"] == .string("tv"))
        #expect(calls[2].args["id"] == .integer(42))
    }

    @Test func traktRoutesReadsAndWrites() async throws {
        let item = #"{"type":"episode","ids":{"trakt":12},"title":"Episode","watchedAt":"2026-11-05T00:00:00Z"}"#
        let fixture = ServiceFixture([
            "account.me": #"{"username":"viewer"}"#,
            "metadata.search": #"{"items":[\#(item)]}"#, "watchlist.list": #"{"items":[\#(item)]}"#,
            "watchlist.set": "unsupported", "history.list": #"{"items":[\#(item)]}"#,
            "history.add": "unsupported", "scrobble.stop": #"{"action":"scrobble","progress":87.5}"#,
        ])
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: KnownServiceID.trakt, key: "client_id", value: "trakt-client")
        try accounts.set(service: KnownServiceID.trakt, key: "access_token", value: "trakt-token")
        let service = TraktService(bridge: fixture.bridge(id: KnownServiceID.trakt, accounts: accounts))
        #expect(try await service.account().username == "viewer")
        let found = try await service.search(query: "  Episode ")
        let episode = try #require(found.first)
        #expect(try await service.watchlist() == found)
        await #expect(throws: ServiceBridgeError.unsupportedMethod(service: KnownServiceID.trakt, method: "watchlist.set")) {
            try await service.setWatchlist(episode, included: false)
        }
        let history = try await service.history()
        let date = try #require(history.first?.watchedAt)
        #expect(history.first?.item == episode)
        await #expect(throws: ServiceBridgeError.unsupportedMethod(service: KnownServiceID.trakt, method: "history.add")) {
            try await service.record(episode, watchedAt: date)
        }
        try await service.scrobble(.stop, item: episode, progress: 87.5)
        let calls = await fixture.calls
        #expect(calls.map(\.method) == ["account.me", "metadata.search", "watchlist.list", "watchlist.set", "history.list", "history.add", "scrobble.stop"])
        #expect(calls[1].args["query"] == .string("Episode"))
        #expect(calls[1].secrets == ["client_id": "trakt-client"])
        #expect(calls[3].args["included"] == .bool(false))
        #expect(calls[5].args["watchedAt"] == .string(date))
        #expect(calls[6].args["episode"]?["ids"]?["trakt"] == .integer(12))
        #expect(calls[6].args["progress"] == .number("87.5"))
        #expect(calls[6].secrets == ["client_id": "trakt-client", "access_token": "trakt-token"])
        await #expect(throws: ServiceBridgeError.invalidPayload(service: KnownServiceID.trakt, method: "scrobble.stop")) {
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
        let fixture = ServiceFixture(["metadata.detail": #"{"wrong":true}"#, "episode.update": "unsupported"])
        let id = KnownServiceID.bangumi
        let accounts = MemoryServiceAccounts()
        try accounts.set(service: id, key: "access_token", value: "fake-secret")
        var client = BangumiClient { _ in
            Issue.record("a package failure must never trigger fallback")
            return .init(status: 500)
        }
        client.service = BangumiServiceAdapter(bridge: fixture.bridge(id: id, accounts: accounts))
        await #expect(throws: ServiceBridgeError.executionFailed(service: id, method: "account.me")) { try await client.me() }
        await #expect(throws: ServiceBridgeError.invalidResponse(service: id, method: "metadata.detail")) { try await client.subject(id: 1) }
        await #expect(throws: ServiceBridgeError.unsupportedMethod(service: id, method: "episode.update")) {
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
