import Foundation

public struct BangumiError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Bangumi (bgm.tv), as far as this app needs it.
///
/// Auth is a personal access token in the `Authorization` header, not OAuth. The
/// token page is next.bgm.tv; OAuth would mean shipping a client secret in an app
/// that anyone can unzip, which is not a secret.
///
/// Every request carries a User-Agent that says who is calling. Bangumi throttles
/// anonymous traffic hard and answers 403 to a default URLSession agent, so this is
/// not decoration.
public struct BangumiClient: Sendable {
    public struct Request: Sendable {
        public var url: String
        public var method: String
        public var headers: [String: String]
        public var body: Data?
    }

    public struct Response: Sendable {
        public var status: Int
        public var body: Data
        public init(status: Int, body: Data = Data()) {
            self.status = status
            self.body = body
        }
    }

    public static let base = "https://api.bgm.tv"
    public static let userAgent = "laincat/Nekularity (https://github.com/laincat/Nekularity)"

    public var token: String?
    public var send: @Sendable (Request) async throws -> Response

    public init(token: String? = nil, send: @escaping @Sendable (Request) async throws -> Response) {
        self.token = token
        self.send = send
    }

    public static func live(token: String? = nil) -> BangumiClient {
        BangumiClient(token: token) { request in
            guard let url = URL(string: request.url) else { throw BangumiError("改不了的地址") }
            var req = URLRequest(url: url)
            req.httpMethod = request.method
            for (name, value) in request.headers { req.setValue(value, forHTTPHeaderField: name) }
            req.httpBody = request.body
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: req)
            return Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }
    }

    /// The URL, headers and body for one endpoint. `path` starts with `/`.
    public func request(_ path: String, query: [String: String] = [:],
                        method: String = "GET", body: Data? = nil) -> Request {
        var components = URLComponents(string: Self.base + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var headers = [
            "Accept": "application/json",
            "User-Agent": Self.userAgent,
        ]
        if let token, !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        if body != nil { headers["Content-Type"] = "application/json" }
        return Request(url: components.string ?? "", method: method, headers: headers, body: body)
    }

    // MARK: - Account

    public func me() async throws -> BangumiUser {
        let response = try await send(request("/v0/me"))
        try expectOK(response, what: "读取账号")
        return try decode(BangumiUser.self, from: response, what: "账号")
    }

    // MARK: - Subjects

    /// Search is a POST with a JSON body; the query string is ignored there.
    public func search(keyword: String, type: Int = 2, limit: Int = 20) async throws -> [BangumiSubject] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        struct Body: Encodable {
            var keyword: String
            var filter: Filter
            struct Filter: Encodable { var type: [Int] }
        }
        let body = try JSONEncoder().encode(Body(keyword: trimmed, filter: .init(type: [type])))
        let response = try await send(request("/v0/search/subjects", query: ["limit": "\(limit)"],
                                             method: "POST", body: body))
        try expectOK(response, what: "搜索条目")
        struct Answer: Decodable { var data: [BangumiSubject] }
        let found = try decode(Answer.self, from: response, what: "搜索条目").data
        if !found.isEmpty { return found }
        // Measured on 2026-11-01: this endpoint answers 200 with an empty list for
        // Chinese keywords when it is not signed in — "进击的巨人" returned 0 while
        // the older endpoint below returned 128. A search box that silently finds
        // nothing for the language the app is written in is worse than an older
        // endpoint, so an empty answer falls back to it.
        return try await searchLegacy(keyword: trimmed, type: type, limit: limit)
    }

    /// The endpoint from before v0. It answers Chinese keywords without an
    /// account, and spells its fields differently: `id` and `type` are strings and
    /// the air date is `air_date`.
    public func searchLegacy(keyword: String, type: Int = 2, limit: Int = 20) async throws -> [BangumiSubject] {
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? keyword
        let response = try await send(request("/search/subject/\(escaped)", query: [
            "type": "\(type)",
            "responseGroup": "small",
            "max_results": "\(limit)",
        ]))
        try expectOK(response, what: "搜索条目")
        struct Answer: Decodable {
            struct Item: Decodable {
                var id: String
                var type: String?
                var name: String?
                var nameCN: String?
                var summary: String?
                var airDate: String?
                var images: BangumiSubject.Images?

                enum CodingKeys: String, CodingKey {
                    case id, type, name, summary, images
                    case nameCN = "name_cn"
                    case airDate = "air_date"
                }
            }
            var list: [Item]
        }
        let answer = try decode(Answer.self, from: response, what: "搜索条目")
        return answer.list.compactMap { item in
            guard let id = Int(item.id) else { return nil }
            return BangumiSubject(id: id,
                                  type: item.type.flatMap(Int.init),
                                  name: item.name ?? "",
                                  nameCN: item.nameCN,
                                  summary: item.summary,
                                  date: item.airDate,
                                  images: item.images)
        }
    }

    public func subject(id: Int) async throws -> BangumiSubject {
        let response = try await send(request("/v0/subjects/\(id)"))
        try expectOK(response, what: "读取条目")
        return try decode(BangumiSubject.self, from: response, what: "条目")
    }

    /// How many episodes this reader will walk. Twenty requests: enough for a
    /// thousand-episode show, bounded so a wrong `total` cannot become an endless
    /// loop.
    public static let episodeLimit = 2000

    /// Every episode of a subject. Paged at 100 because that is Bangumi's maximum.
    ///
    /// The walk ends at the total the server reports rather than at a fixed number:
    /// measured 2026-11-01, ONE PIECE has 1155 episodes, so any cap below that
    /// truncates a real show without saying so.
    public func episodes(subjectID: Int, type: Int = 0) async throws -> [BangumiEpisode] {
        struct Answer: Decodable { var data: [BangumiEpisode]; var total: Int? }
        var all: [BangumiEpisode] = []
        var offset = 0
        var total: Int?
        while all.count < Self.episodeLimit {
            let response = try await send(request("/v0/episodes", query: [
                "subject_id": "\(subjectID)",
                "type": "\(type)",
                "limit": "100",
                "offset": "\(offset)",
            ]))
            try expectOK(response, what: "读取剧集")
            let answer = try decode(Answer.self, from: response, what: "剧集")
            total = total ?? answer.total
            all.append(contentsOf: answer.data)
            if answer.data.isEmpty || answer.data.count < 100 { break }
            if let total, all.count >= total { break }
            offset += answer.data.count
        }
        return all
    }

    /// What airs on each weekday. Needs no account.
    public func calendar() async throws -> [BangumiCalendarDay] {
        let response = try await send(request("/calendar"))
        try expectOK(response, what: "读取每日放送")
        return try decode([BangumiCalendarDay].self, from: response, what: "每日放送")
    }

    // MARK: - Collections

    /// This account's collections, newest first. `-/` means "whoever the token is".
    public func collections(type: CollectionType? = nil, subjectType: Int = 2,
                            limit: Int = 50) async throws -> [BangumiCollection] {
        var query = ["subject_type": "\(subjectType)", "limit": "\(limit)"]
        if let type { query["type"] = "\(type.rawValue)" }
        let response = try await send(request("/v0/users/-/collections", query: query))
        // Measured 2026-11-01: this endpoint answers 404, not 401, when the request
        // carries no token. "找不到这个条目" would send a reader looking for a
        // missing subject when the account is what is missing.
        try expectOK(response, what: "读取收藏",
                     notFound: (token ?? "").isEmpty
                        ? "读取收藏失败:先连接 Bangumi 账号"
                        : "读取收藏失败:Bangumi 没有认出这个账号,令牌可能已失效")
        struct Answer: Decodable { var data: [BangumiCollection] }
        return try decode(Answer.self, from: response, what: "收藏").data
    }

    /// One subject's place in this account's collections, if it has one.
    public func collection(subjectID: Int) async throws -> BangumiCollection? {
        let response = try await send(request("/v0/users/-/collections/\(subjectID)"))
        if response.status == 404 {
            // Without a token the same 404 means "signed out", and answering nil
            // would show every subject as not collected.
            guard (token ?? "").isEmpty == false else {
                throw BangumiError("读取收藏状态失败:先连接 Bangumi 账号")
            }
            return nil
        }
        try expectOK(response, what: "读取收藏状态")
        return try decode(BangumiCollection.self, from: response, what: "收藏状态")
    }

    /// Puts a subject in a collection state, creating the entry when it is new.
    public func setCollection(subjectID: Int, type: CollectionType, rate: Int? = nil,
                              epStatus: Int? = nil, comment: String? = nil) async throws {
        struct Body: Encodable {
            var type: Int
            var rate: Int?
            var epStatus: Int?
            var comment: String?
            enum CodingKeys: String, CodingKey {
                case type, rate, comment
                case epStatus = "ep_status"
            }
        }
        let body = try JSONEncoder().encode(Body(type: type.rawValue, rate: rate,
                                                 epStatus: epStatus, comment: comment))
        let response = try await send(request("/v0/users/-/collections/\(subjectID)",
                                              method: "POST", body: body))
        try expectOK(response, what: "更新收藏")
    }

    /// Marks one episode watched. Bangumi keeps the count itself, so this is a
    /// separate endpoint from the collection.
    public func markWatched(subjectID: Int, episodeID: Int) async throws {
        struct Body: Encodable { var episodeID: Int; var type: Int
            enum CodingKeys: String, CodingKey { case type; case episodeID = "episode_id" } }
        let body = try JSONEncoder().encode(Body(episodeID: episodeID, type: 2))
        let response = try await send(request("/v0/users/-/collections/\(subjectID)/episodes",
                                              method: "PATCH", body: body))
        // 202 is success here: the write is queued, not applied immediately.
        try expectOK(response, what: "标记看过", extraSuccess: [202])
    }

    // MARK: - Plumbing

    private func expectOK(_ response: Response, what: String, extraSuccess: Set<Int> = [],
                          notFound: String? = nil) throws {
        if (200...299).contains(response.status) || extraSuccess.contains(response.status) { return }
        switch response.status {
        case 401: throw BangumiError("\(what)失败:Bangumi 令牌无效或已过期")
        case 403: throw BangumiError("\(what)失败:Bangumi 拒绝了这次请求")
        case 404: throw BangumiError(notFound ?? "\(what)失败:找不到这个条目")
        case 429: throw BangumiError("\(what)失败:请求太频繁,稍后再试")
        default: throw BangumiError("\(what)失败(HTTP \(response.status))")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: Response, what: String) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: response.body)
        } catch {
            throw BangumiError("\(what)的返回看不懂")
        }
    }
}
