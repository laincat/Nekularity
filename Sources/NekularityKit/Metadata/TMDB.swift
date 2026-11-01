import Foundation

/// A show as a metadata source describes it, reduced to what this app shows.
public struct SeriesInfo: Codable, Hashable, Sendable {
    public var source: String
    public var id: Int
    public var name: String
    public var overview: String
    public var poster: String?
    public var firstAirDate: String?
    /// The next episode that has not aired yet, when the source knows one.
    public var nextEpisode: Episode?
    /// `Returning Series`, `Ended`, and so on, as the source spells it.
    public var status: String
    /// When this was fetched, so a stale answer can be refreshed instead of shown
    /// forever.
    public var fetchedAt: Date

    public struct Episode: Codable, Hashable, Sendable {
        public var airDate: String
        public var season: Int
        public var number: Int
        public var name: String
    }

    public init(source: String, id: Int, name: String, overview: String = "", poster: String? = nil,
                firstAirDate: String? = nil, nextEpisode: Episode? = nil, status: String = "",
                fetchedAt: Date = Date()) {
        self.source = source
        self.id = id
        self.name = name
        self.overview = overview
        self.poster = poster
        self.firstAirDate = firstAirDate
        self.nextEpisode = nextEpisode
        self.status = status
        self.fetchedAt = fetchedAt
    }

    public var key: String { "\(source)/\(id)" }

    /// The next air date as a day, if it is one.
    public var nextAirDate: Date? {
        guard let text = nextEpisode?.airDate else { return nil }
        return Self.dayFormatter.date(from: text)
    }

    /// TMDB dates are plain `YYYY-MM-DD` days, in no time zone. Parsing them in
    /// the user's zone would move an evening broadcast to the wrong day for half
    /// the world, so the formatter is fixed to UTC.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

public struct MetadataError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The Movie Database, as far as this app needs it.
///
/// TMDB issues two kinds of key: a v3 key that goes in the query string and a v4
/// token that goes in the Authorization header. Which one a user pasted is not
/// something to ask them about, so it is detected: a v4 token contains dots.
public struct TMDBClient: Sendable {
    public struct Request: Sendable {
        public var url: String
        public var headers: [String: String]
    }

    public struct Response: Sendable {
        public var status: Int
        public var body: Data
        public init(status: Int, body: Data = Data()) {
            self.status = status
            self.body = body
        }
    }

    public var apiKey: String
    public var language: String
    public var send: @Sendable (Request) async throws -> Response

    public init(apiKey: String, language: String = "zh-CN",
                send: @escaping @Sendable (Request) async throws -> Response) {
        self.apiKey = apiKey
        self.language = language
        self.send = send
    }

    public static func live(apiKey: String, language: String = "zh-CN") -> TMDBClient {
        TMDBClient(apiKey: apiKey, language: language) { request in
            guard let url = URL(string: request.url) else { throw MetadataError("改不了的地址") }
            var req = URLRequest(url: url)
            for (name, value) in request.headers { req.setValue(value, forHTTPHeaderField: name) }
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: req)
            return Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }
    }

    public var isV4Token: Bool { apiKey.contains(".") }

    /// The URL and headers for one endpoint. `path` starts with `/3/`.
    public func request(_ path: String, query: [String: String] = [:]) -> Request {
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // Both key kinds work: v3 in the query (standard for v3), v4 as a bearer.
        items.append(URLQueryItem(name: "language", value: language))
        if !isV4Token { items.append(URLQueryItem(name: "api_key", value: apiKey)) }
        var components = URLComponents(string: "https://api.themoviedb.org" + path)!
        components.queryItems = items
        var request = Request(url: components.string ?? "", headers: [:])
        request.headers["Accept"] = "application/json"
        if isV4Token { request.headers["Authorization"] = "Bearer \(apiKey)" }
        return request
    }

    public func search(query: String) async throws -> [SeriesInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await send(request("/3/search/tv", query: ["query": trimmed]))
        try expectOK(response, what: "搜索剧集")
        struct Answer: Decodable {
            struct Item: Decodable {
                var id: Int
                var name: String?
                var original_name: String?
                var overview: String?
                var poster_path: String?
                var first_air_date: String?
            }
            var results: [Item]
        }
        let answer = try decode(Answer.self, from: response, what: "搜索剧集")
        return answer.results.map { item in
            SeriesInfo(source: "tmdb", id: item.id,
                       name: item.name ?? item.original_name ?? "",
                       overview: item.overview ?? "",
                       poster: Self.imageURL(item.poster_path),
                       firstAirDate: item.first_air_date)
        }
    }

    /// One show, including the next episode it has not aired yet.
    public func series(id: Int) async throws -> SeriesInfo {
        let response = try await send(request("/3/tv/\(id)"))
        try expectOK(response, what: "读取剧集")
        struct Answer: Decodable {
            struct Episode: Decodable {
                var air_date: String?
                var season_number: Int?
                var episode_number: Int?
                var name: String?
            }
            var id: Int
            var name: String?
            var original_name: String?
            var overview: String?
            var poster_path: String?
            var first_air_date: String?
            var status: String?
            var next_episode_to_air: Episode?
        }
        let answer = try decode(Answer.self, from: response, what: "剧集")
        var info = SeriesInfo(source: "tmdb", id: answer.id,
                              name: answer.name ?? answer.original_name ?? "",
                              overview: answer.overview ?? "",
                              poster: Self.imageURL(answer.poster_path),
                              firstAirDate: answer.first_air_date,
                              status: answer.status ?? "")
        if let episode = answer.next_episode_to_air, let airDate = episode.air_date, !airDate.isEmpty {
            info.nextEpisode = SeriesInfo.Episode(airDate: airDate,
                                                  season: episode.season_number ?? 0,
                                                  number: episode.episode_number ?? 0,
                                                  name: episode.name ?? "")
        }
        return info
    }

    public static func imageURL(_ path: String?, width: Int = 342) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/w\(width)" + path
    }

    private func expectOK(_ response: Response, what: String) throws {
        switch response.status {
        case 200...299: return
        case 401: throw MetadataError("\(what)失败:API key 不对")
        case 404: throw MetadataError("\(what)失败:找不到这个条目")
        case 429: throw MetadataError("\(what)失败:请求太频繁,稍后再试")
        default: throw MetadataError("\(what)失败(HTTP \(response.status))")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: Response, what: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw MetadataError("\(what)的返回看不懂")
        }
    }
}
