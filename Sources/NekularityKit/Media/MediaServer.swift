import Foundation
import Observation

/// A media server the user owns: Jellyfin, Emby or Plex.
///
/// The server is *not* a comic source. A source is a script that keeps no
/// account; a media server is an account with a token and a library the user
/// already curated. Mixing them would put a personal library behind a plugin
/// record that any source backup could carry away.
public struct MediaServer: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case jellyfin
        case emby
        case plex

        public var title: String {
            switch self {
            case .jellyfin: "Jellyfin"
            case .emby: "Emby"
            case .plex: "Plex"
            }
        }

        /// Plex answers XML and authenticates with a header, so it is a separate
        /// code path rather than a flag.
        public var speaksEmbyAPI: Bool {
            switch self {
            case .jellyfin, .emby: true
            case .plex: false
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var name: String
    /// No trailing slash. Kept as text because the user types it.
    public var baseURL: String
    /// The account the token belongs to; empty until a sign-in succeeds.
    public var userID: String

    public init(id: String = UUID().uuidString, kind: Kind, name: String = "",
                baseURL: String, userID: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.userID = userID
    }

    public var displayName: String { name.isEmpty ? kind.title : name }
}

/// One thing a server holds, reduced to what a list and a player need.
public struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// Series name for an episode, empty for a film.
    public var series: String
    public var year: Int?
    public var overview: String?
    /// Absolute URL of the poster; nil when the server has none.
    public var poster: String?
    /// Seconds, 0 when the server did not say.
    public var runtime: Int
    /// How far in the user already is, seconds, 0 when unwatched or unknown.
    public var position: Int

    public init(id: String, title: String, series: String = "", year: Int? = nil,
                overview: String? = nil, poster: String? = nil, runtime: Int = 0, position: Int = 0) {
        self.id = id
        self.title = title
        self.series = series
        self.year = year
        self.overview = overview
        self.poster = poster
        self.runtime = runtime
        self.position = position
    }

    public var progress: Double { runtime > 0 ? min(1, max(0, Double(position) / Double(runtime))) : 0 }
}

/// A library on a server: films, series, or something else worth listing.
public struct MediaLibrary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// `movies`, `tvshows`, or whatever the server called it.
    public var kind: String

    public init(id: String, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct MediaServerError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Talks to one server, with the sending injected.
///
/// The injection is not ceremony: a media server is the one thing in this app
/// that cannot be exercised in a simulator, so the client's mapping and error
/// handling have to be testable without one.
public struct MediaServerClient: Sendable {
    public struct Request: Sendable {
        public var url: String
        public var method: String = "GET"
        public var headers: [String: String] = [:]
        public var body: Data?
    }

    public struct Response: Sendable {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    /// A device id the server uses to recognise "this app"; stable per install.
    public var deviceID: String
    public var send: @Sendable (Request) async throws -> Response

    public init(deviceID: String, send: @escaping @Sendable (Request) async throws -> Response) {
        self.deviceID = deviceID
        self.send = send
    }

    /// A client that speaks HTTP for real.
    public static func live(deviceID: String) -> MediaServerClient {
        MediaServerClient(deviceID: deviceID) { request in
            guard let url = URL(string: request.url) else {
                throw MediaServerError("地址不是有效的网址:\(request.url)")
            }
            var req = URLRequest(url: url)
            req.httpMethod = request.method
            req.httpBody = request.body
            for (name, value) in request.headers { req.setValue(value, forHTTPHeaderField: name) }
            let config = URLSessionConfiguration.ephemeral
            // A media server is usually on the local network over plain http and
            // with a certificate nobody signed; refusing it would make the feature
            // unusable for exactly the case it exists for.
            let session = URLSession(configuration: config, delegate: InsecureIfLocalDelegate(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
            }
            return Response(status: http?.statusCode ?? 0, headers: headers, body: data)
        }
    }

    // MARK: Signing in

    /// Signs in and returns the token plus the user id it belongs to.
    public func signIn(server: MediaServer, username: String, password: String) async throws -> (token: String, userID: String) {
        guard server.kind.speaksEmbyAPI else {
            throw MediaServerError("\(server.kind.title) 用的是另一套接口,客户端还没有接上")
        }
        let base = try normalizedBase(server.baseURL)
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        var request = Request(url: base + "/Users/AuthenticateByName", method: "POST")
        request.body = body
        request.headers["Content-Type"] = "application/json"
        request.headers["X-Emby-Authorization"] = authorization(device: deviceID, token: nil)
        let response = try await send(request)
        guard response.status == 200 else {
            throw MediaServerError(signInFailure(status: response.status))
        }
        struct Answer: Decodable {
            struct User: Decodable { var Id: String }
            var AccessToken: String
            var User: User
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body) else {
            throw MediaServerError("服务器回了一个看不懂的登录结果,可能不是 Jellyfin / Emby")
        }
        guard !answer.AccessToken.isEmpty else { throw MediaServerError("服务器没有给出访问令牌") }
        return (answer.AccessToken, answer.User.Id)
    }

    /// Turns a status into something a person can act on. "401" tells nobody what
    /// to change; "wrong password" does.
    public func signInFailure(status: Int) -> String {
        switch status {
        case 401, 403: "用户名或密码不对"
        case 404: "这个地址上没有登录接口,确认是 Jellyfin / Emby 的根地址"
        case 500...599: "服务器出错了(\(status))"
        default: "登录失败(HTTP \(status))"
        }
    }

    // MARK: Browsing

    public func libraries(server: MediaServer, token: String) async throws -> [MediaLibrary] {
        guard server.kind.speaksEmbyAPI else {
            throw MediaServerError("\(server.kind.title) 用的是另一套接口,客户端还没有接上")
        }
        let base = try normalizedBase(server.baseURL)
        let url = base + "/Users/" + (server.userID.isEmpty ? "" : server.userID) + "/Views"
        let response = try await send(authorized(url: url, token: token, device: deviceID))
        try expectOK(response, what: "读取媒体库")
        struct Answer: Decodable {
            struct Item: Decodable {
                var Id: String
                var Name: String
                var CollectionType: String?
            }
            var Items: [Item]
        }
        let answer = try decode(Answer.self, from: response, what: "媒体库")
        return answer.Items.map {
            MediaLibrary(id: $0.Id, name: $0.Name, kind: $0.CollectionType ?? "")
        }
    }

    public func items(server: MediaServer, token: String, library: MediaLibrary?) async throws -> [MediaItem] {
        guard server.kind.speaksEmbyAPI else {
            throw MediaServerError("\(server.kind.title) 用的是另一套接口,客户端还没有接上")
        }
        let base = try normalizedBase(server.baseURL)
        var url = base + "/Users/" + (server.userID.isEmpty ? "" : server.userID) + "/Items"
        url += "?Recursive=true&IncludeItemTypes=Movie,Episode&Fields=Overview,RunTimeTicks,PrimaryImageTag"
        if let library { url += "&ParentId=" + library.id }
        let response = try await send(authorized(url: url, token: token, device: deviceID))
        try expectOK(response, what: "读取影片")
        struct Answer: Decodable {
            struct Item: Decodable {
                var Id: String
                var Name: String
                var SeriesName: String?
                var ProductionYear: Int?
                var Overview: String?
                var RunTimeTicks: Int64?
                var PrimaryImageTag: String?
                struct UserData: Decodable { var PlaybackPositionTicks: Int64? }
                var UserData: UserData?
            }
            var Items: [Item]
        }
        let answer = try decode(Answer.self, from: response, what: "影片")
        return answer.Items.map { item in
            MediaItem(
                id: item.Id,
                title: item.Name,
                series: item.SeriesName ?? "",
                year: item.ProductionYear,
                overview: item.Overview,
                poster: item.PrimaryImageTag == nil ? nil : imageURL(base: base, id: item.Id, token: token),
                // Ticks are 100ns each; a rounded second is all this app shows.
                runtime: Int((item.RunTimeTicks ?? 0) / 10_000_000),
                position: Int((item.UserData?.PlaybackPositionTicks ?? 0) / 10_000_000)
            )
        }
    }

    /// Where the bytes are, for the player.
    public func playURL(server: MediaServer, token: String, item: MediaItem) throws -> String {
        guard server.kind.speaksEmbyAPI else {
            throw MediaServerError("\(server.kind.title) 用的是另一套接口,客户端还没有接上")
        }
        let base = try normalizedBase(server.baseURL)
        return base + "/Videos/" + item.id + "/stream?static=true&api_key="
            + (token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)
    }

    public func imageURL(base: String, id: String, token: String) -> String {
        base + "/Items/" + id + "/Images/Primary?maxHeight=480&api_key="
            + (token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)
    }

    // MARK: Plumbing

    private func normalizedBase(_ text: String) throws -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MediaServerError("先填服务器的地址") }
        if !value.lowercased().hasPrefix("http") { value = "http://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard URL(string: value)?.host != nil else {
            throw MediaServerError("地址不是有效的网址:\(text)")
        }
        return value
    }

    private func authorized(url: String, token: String, device: String) -> Request {
        var request = Request(url: url)
        request.headers["X-Emby-Authorization"] = authorization(device: device, token: token)
        return request
    }

    /// The header Jellyfin and Emby accept. The token goes in the header, not the
    /// query string, so it does not end up in a server log line.
    private func authorization(device: String, token: String?) -> String {
        var value = "MediaBrowser Client=\"Nekularity\", Device=\"iPhone\", DeviceId=\"\(device)\", Version=\"1\""
        if let token, !token.isEmpty { value += ", Token=\"\(token)\"" }
        return value
    }

    private func expectOK(_ response: Response, what: String) throws {
        switch response.status {
        case 200...299: return
        case 401, 403: throw MediaServerError("\(what)被拒绝,登录可能已失效")
        case 404: throw MediaServerError("\(what)失败:服务器没有这个接口")
        default: throw MediaServerError("\(what)失败(HTTP \(response.status))")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: Response, what: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw MediaServerError("\(what)的返回看不懂,确认地址指向 Jellyfin / Emby")
        }
    }
}

/// Accepts a self-signed certificate, but only for a host that is plainly local.
///
/// A NAS on 192.168.x.x with a self-signed certificate is the common case; a
/// public host with a broken certificate is not something to wave through.
final class InsecureIfLocalDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              Self.isLocal(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        return host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || (parts[0] == "172" && (16...31).contains(UInt8(parts[1]) ?? 0))
            || host.hasPrefix("127.")
    }
}
