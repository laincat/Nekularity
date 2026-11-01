import Foundation

/// Bangumi spells the same number three ways depending on the endpoint: `1`,
/// `1.0`, and `"1.5"`. Episode sort in particular arrives as a fraction for
/// specials, so decoding it as `Int` would throw on exactly the entries that need
/// care.
struct FlexNumber: Codable, Hashable, Sendable {
    var value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let int = try? container.decode(Int.self) {
            value = Double(int)
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }

    /// Only ever written back as a number: nothing here posts an episode, but a
    /// decode-only member would keep `BangumiEpisode` from being `Codable` at all,
    /// and the compiler says so once for every field rather than once for the type.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

/// One entry on Bangumi: an anime, a book, a game.
public struct BangumiSubject: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// 1 book, 2 anime, 4 game, 6 live action.
    public var type: Int?
    public var name: String
    public var nameCN: String?
    public var summary: String?
    /// `yyyy-MM-dd`, possibly with only a year or a month.
    public var date: String?
    public var platform: String?
    /// Aired so far, as Bangumi counts it.
    public var eps: Int?
    public var totalEpisodes: Int?
    public var images: Images?
    public var rating: Rating?
    public var counts: Counts?

    public struct Images: Codable, Hashable, Sendable {
        public var large: String?
        public var common: String?
        public var medium: String?
        public var grid: String?
        public var small: String?
    }

    public struct Rating: Codable, Hashable, Sendable {
        public var score: Double?
        public var total: Int?
    }

    /// How many people have it in each collection state.
    public struct Counts: Codable, Hashable, Sendable {
        public var wish: Int?
        public var collect: Int?
        public var doing: Int?
        public var onHold: Int?
        public var dropped: Int?

        enum CodingKeys: String, CodingKey {
            case wish, collect, doing, dropped
            case onHold = "on_hold"
        }
    }

    public init(id: Int, type: Int? = nil, name: String, nameCN: String? = nil,
                summary: String? = nil, date: String? = nil, platform: String? = nil,
                eps: Int? = nil, totalEpisodes: Int? = nil, images: Images? = nil,
                rating: Rating? = nil, counts: Counts? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.nameCN = nameCN
        self.summary = summary
        self.date = date
        self.platform = platform
        self.eps = eps
        self.totalEpisodes = totalEpisodes
        self.images = images
        self.rating = rating
        self.counts = counts
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, summary, date, platform, eps, images, rating
        case nameCN = "name_cn"
        case totalEpisodes = "total_episodes"
        case counts = "collection"
    }

    /// The Chinese title when there is one, because that is what the user typed
    /// into the search box and what the collection screen should echo back.
    public var title: String {
        if let nameCN, !nameCN.isEmpty { return nameCN }
        return name
    }

    public var poster: String? { images?.large ?? images?.common ?? images?.medium }

    public var score: Double? { rating?.score }

    /// Bangumi counts every aired episode, so an entry that is still airing has
    /// `eps` below `total_episodes`.
    public var airedEpisodes: Int? { eps ?? totalEpisodes }
}

/// One episode of a subject.
public struct BangumiEpisode: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// 0 main story, 1 special, 2 opening, 3 ending, 4 trailer, 5 MAD, 6 other.
    public var type: Int?
    public var name: String?
    public var nameCN: String?
    /// `yyyy-MM-dd`: a day, not a moment. Bangumi does not publish a broadcast
    /// time, which is why reminders here are planned for the day.
    public var airdate: String?
    public var comment: Int?
    private var sortValue: FlexNumber?

    public init(id: Int, type: Int? = nil, name: String? = nil, nameCN: String? = nil,
                airdate: String? = nil, comment: Int? = nil, sort: Double? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.nameCN = nameCN
        self.airdate = airdate
        self.comment = comment
        sortValue = FlexNumber(sort)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, airdate, comment
        case nameCN = "name_cn"
        case sortValue = "sort"
    }

    /// `1`, `1.5` for an episode between chapters — a Double on purpose.
    public var sort: Double? { sortValue?.value }

    /// The whole number for the badge: 1 from 1.5.
    public var number: Int? { sort.map { Int($0.rounded(.down)) } }

    public var title: String {
        if let nameCN, !nameCN.isEmpty { return nameCN }
        return name ?? ""
    }

    public var isMainStory: Bool { (type ?? 0) == 0 }
}

/// Which collection state a subject is in, as Bangumi numbers it.
public enum CollectionType: Int, Codable, CaseIterable, Sendable, Identifiable {
    case wish = 1
    case done = 2
    case doing = 3
    case onHold = 4
    case dropped = 5

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .wish: "想看"
        case .done: "看过"
        case .doing: "在看"
        case .onHold: "搁置"
        case .dropped: "抛弃"
        }
    }
}

/// One subject in this account's collections.
public struct BangumiCollection: Codable, Hashable, Sendable, Identifiable {
    public var subjectID: Int
    public var type: CollectionType
    public var rate: Int?
    /// Episodes watched.
    public var epStatus: Int?
    /// Chapters read or volumes, for books.
    public var volStatus: Int?
    public var comment: String?
    public var subject: BangumiSubject?

    public var id: Int { subjectID }

    public init(subjectID: Int, type: CollectionType, rate: Int? = nil, epStatus: Int? = nil,
                volStatus: Int? = nil, comment: String? = nil, subject: BangumiSubject? = nil) {
        self.subjectID = subjectID
        self.type = type
        self.rate = rate
        self.epStatus = epStatus
        self.volStatus = volStatus
        self.comment = comment
        self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
        case type, rate, comment, subject
        case subjectID = "subject_id"
        case epStatus = "ep_status"
        case volStatus = "vol_status"
    }

    /// `7/12` when the subject knows its length, `7` when it does not.
    public var progressText: String {
        let watched = epStatus ?? 0
        guard let total = subject?.totalEpisodes ?? subject?.eps, total > 0 else { return "\(watched)" }
        return "\(watched)/\(total)"
    }
}

/// The signed-in account.
public struct BangumiUser: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var username: String
    public var nickname: String?
    public var avatar: Avatar?

    public struct Avatar: Codable, Hashable, Sendable {
        public var large: String?
        public var medium: String?
        public var small: String?
    }

    public init(id: Int, username: String, nickname: String? = nil, avatar: Avatar? = nil) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
    }

    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return username
    }
}

/// One weekday of Bangumi's broadcast calendar.
public struct BangumiCalendarDay: Codable, Hashable, Sendable, Identifiable {
    public var weekday: Weekday
    public var items: [BangumiSubject]

    public struct Weekday: Codable, Hashable, Sendable {
        public var id: Int?
        public var cn: String?
        public var ja: String?
        public var en: String?
    }

    public var id: Int { weekday.id ?? 0 }

    public var label: String { weekday.cn ?? weekday.en ?? "" }

    public init(weekday: Weekday, items: [BangumiSubject]) {
        self.weekday = weekday
        self.items = items
    }
}

extension SeriesInfo {
    /// Bangumi's answer, in the shape the rest of the app already understands.
    ///
    /// The next episode is the first main-story episode whose air date is today or
    /// later: Bangumi publishes a date per episode, not a single "next to air"
    /// field, so the list has to be read to find it.
    public init(subject: BangumiSubject, episodes: [BangumiEpisode] = [], now: Date = Date()) {
        let aired = BangumiEpisode.dayFormatter.string(from: now)
        let next = episodes
            .filter { $0.isMainStory }
            .filter { ($0.airdate ?? "").isEmpty == false && ($0.airdate ?? "") >= aired }
            .min { ($0.airdate ?? "") < ($1.airdate ?? "") }

        var nextEpisode: SeriesInfo.Episode?
        if let next, let airDate = next.airdate {
            nextEpisode = SeriesInfo.Episode(airDate: airDate,
                                             season: 1,
                                             number: next.number ?? 0,
                                             name: next.title)
        }

        self.init(source: "bangumi",
                  id: subject.id,
                  name: subject.title,
                  overview: subject.summary ?? "",
                  poster: subject.poster,
                  firstAirDate: subject.date,
                  nextEpisode: nextEpisode,
                  status: (subject.eps ?? 0) > 0 ? "airing" : "")
    }
}

extension BangumiEpisode {
    /// Bangumi writes dates as `yyyy-MM-dd`. Parsing is done in UTC on purpose: the
    /// string is a day, and a device in another zone must not shift it into the
    /// previous one.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
