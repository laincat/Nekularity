import Foundation
import Testing

@testable import NekularityKit

/// Answers the client from a table, so the mapping and the error wording can be
/// checked without a server: a media server is the one thing a simulator cannot
/// provide.
private struct FakeServer {
    var replies: [String: (status: Int, json: String)] = [:]
    /// Every request the client made, so a test can assert what was asked.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [MediaServerClient.Request] = []
        func append(_ request: MediaServerClient.Request) { lock.withLock { value.append(request) } }
        var all: [MediaServerClient.Request] { lock.withLock { value } }
    }
    let log = Log()

    func client() -> MediaServerClient {
        let replies = replies
        let log = log
        return MediaServerClient(deviceID: "test-device") { request in
            log.append(request)
            guard let reply = replies[request.url] else {
                return MediaServerClient.Response(status: 404)
            }
            return MediaServerClient.Response(status: reply.status,
                                              headers: ["content-type": "application/json"],
                                              body: Data(reply.json.utf8))
        }
    }
}

private let jellyfin = MediaServer(kind: .jellyfin, name: "", baseURL: "192.168.1.9:8096")

@Suite("Media server client")
struct MediaServerClientTests {
    @Test("signing in keeps the token and the user id the server reported")
    func signsIn() async throws {
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (200, """
        {"AccessToken":"tok-1","User":{"Id":"user-7"}}
        """)
        let answer = try await fake.client().signIn(server: jellyfin, username: "lain", password: "pw")
        #expect(answer.token == "tok-1")
        #expect(answer.userID == "user-7")
        // The device header is what makes the server show a session it can revoke.
        let header = try #require(fake.log.all.first?.headers["X-Emby-Authorization"])
        #expect(header.contains("DeviceId=\"test-device\""))
    }

    @Test("a wrong password is described, not numbered")
    func explainsRefusal() async throws {
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (401, "{}")
        await #expect(throws: MediaServerError.self) {
            _ = try await fake.client().signIn(server: jellyfin, username: "lain", password: "wrong")
        }
        #expect(MediaServerClient(deviceID: "d") { _ in .init(status: 401) }.signInFailure(status: 401)
                == "用户名或密码不对")
    }

    @Test("libraries and items map to what a list and a player need")
    func browses() async throws {
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/user-7/Views"] = (200, """
        {"Items":[{"Id":"lib-1","Name":"电影","CollectionType":"movies"}]}
        """)
        fake.replies["http://192.168.1.9:8096/Users/user-7/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Fields=Overview,RunTimeTicks,PrimaryImageTag&ParentId=lib-1"] = (200, """
        {"Items":[{"Id":"v-1","Name":"第一集","SeriesName":"某剧","ProductionYear":2024,
                   "Overview":"简介","RunTimeTicks":6000000000,"PrimaryImageTag":"tag-1",
                   "UserData":{"PlaybackPositionTicks":1500000000}}]}
        """)
        let client = fake.client()
        let server = MediaServer(kind: .jellyfin, baseURL: "192.168.1.9:8096", userID: "user-7")
        let libraries = try await client.libraries(server: server, token: "tok-1")
        #expect(libraries == [MediaLibrary(id: "lib-1", name: "电影", kind: "movies")])

        let items = try await client.items(server: server, token: "tok-1", library: libraries.first)
        let item = try #require(items.first)
        #expect(item.title == "第一集")
        #expect(item.series == "某剧")
        #expect(item.year == 2024)
        // Ticks are 100ns each: a runtime that looks like 6 000 000 seconds is the
        // classic off-by-ten-million in this API.
        #expect(item.runtime == 600)
        #expect(item.position == 150)
        #expect(item.progress == 0.25)
        #expect(item.poster?.contains("/Items/v-1/Images/Primary") == true)
    }

    @Test("an address without a scheme is taken as http, and a trailing slash is dropped")
    func normalizesAddress() async throws {
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (200, """
        {"AccessToken":"tok-1","User":{"Id":"user-7"}}
        """)
        let answer = try await fake.client().signIn(
            server: MediaServer(kind: .jellyfin, baseURL: "  http://192.168.1.9:8096/  "),
            username: "lain", password: "pw")
        #expect(answer.token == "tok-1")
    }

    @Test("the play address carries the token as a query the player can use")
    func playAddress() throws {
        let client = MediaServerClient(deviceID: "d") { _ in .init(status: 200) }
        let url = try client.playURL(server: jellyfin, token: "tok-1", item: MediaItem(id: "v-1", title: "x"))
        #expect(url == "http://192.168.1.9:8096/Videos/v-1/stream?static=true&api_key=tok-1")
    }

    @Test("an empty address is refused before a request is made")
    func emptyAddress() async throws {
        let client = MediaServerClient(deviceID: "d") { _ in .init(status: 200) }
        await #expect(throws: MediaServerError.self) {
            _ = try await client.signIn(server: MediaServer(kind: .jellyfin, baseURL: "   "),
                                        username: "a", password: "b")
        }
    }

    @Test("Plex is refused with a reason instead of a broken request")
    func plexIsHonest() async throws {
        let client = MediaServerClient(deviceID: "d") { _ in .init(status: 200) }
        await #expect(throws: MediaServerError.self) {
            _ = try await client.signIn(server: MediaServer(kind: .plex, baseURL: "http://plex.lan:32400"),
                                        username: "a", password: "b")
        }
    }

    @Test("a self-signed certificate is waved through only for a local host")
    func localOnly() {
        #expect(InsecureIfLocalDelegate.isLocal("192.168.1.9"))
        #expect(InsecureIfLocalDelegate.isLocal("10.0.0.5"))
        #expect(InsecureIfLocalDelegate.isLocal("172.20.1.1"))
        #expect(InsecureIfLocalDelegate.isLocal("nas.local"))
        #expect(!InsecureIfLocalDelegate.isLocal("example.com"))
        #expect(!InsecureIfLocalDelegate.isLocal("172.40.1.1"))
    }
}

@Suite("Media server store")
@MainActor
struct MediaServerStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a connected server is kept with its token, and survives a relaunch")
    func keepsServer() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (200, """
        {"AccessToken":"tok-1","User":{"Id":"user-7"}}
        """)
        fake.replies["http://192.168.1.9:8096/Users/user-7/Views"] = (200, """
        {"Items":[{"Id":"lib-1","Name":"电影","CollectionType":"movies"}]}
        """)
        let tokens = MemoryMediaTokenStore()
        let store = MediaServerStore(directory: dir, tokens: tokens)
        let added = try await store.add(client: fake.client(), server: jellyfin, username: "lain", password: "pw")
        #expect(added.name == "Jellyfin")
        #expect(store.servers.count == 1)
        #expect(store.status[added.id] == "已连接 · 1 个媒体库")

        let again = MediaServerStore(directory: dir, tokens: tokens)
        #expect(again.servers.first?.id == added.id)
        #expect(again.token(for: added) == "tok-1")
    }

    @Test("a server whose sign-in fails is not stored")
    func doesNotStoreFailure() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (401, "{}")
        let store = MediaServerStore(directory: dir, tokens: MemoryMediaTokenStore())
        await #expect(throws: MediaServerError.self) {
            _ = try await store.add(client: fake.client(), server: jellyfin, username: "lain", password: "no")
        }
        #expect(store.servers.isEmpty)
    }

    @Test("removing a server removes its token too")
    func removingDropsToken() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var fake = FakeServer()
        fake.replies["http://192.168.1.9:8096/Users/AuthenticateByName"] = (200, """
        {"AccessToken":"tok-1","User":{"Id":"user-7"}}
        """)
        fake.replies["http://192.168.1.9:8096/Users/user-7/Views"] = (200, """
        {"Items":[]}
        """)
        let tokens = MemoryMediaTokenStore()
        let store = MediaServerStore(directory: dir, tokens: tokens)
        let added = try await store.add(client: fake.client(), server: jellyfin, username: "lain", password: "pw")
        store.remove(added)
        #expect(store.servers.isEmpty)
        // A removed server that leaves a working token on the device is the thing
        // "remove" is supposed to prevent.
        #expect(try tokens.load(id: added.id) == nil)
    }
}
