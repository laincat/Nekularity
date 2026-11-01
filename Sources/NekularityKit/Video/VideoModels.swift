import Foundation

/// A video source's search or catalogue results.
///
/// These mirror Core's `video` package: a video provider is a plugin or a
/// compiled-in rule, and it answers with the same shapes a comic source does,
/// minus chapters and images — a video is played, not paged through.
public struct VideoPage: Decodable, Sendable {
    public struct Item: Decodable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var cover: String?
        public var subtitle: String?
        public var tags: [String]?
        /// Provider-specific fields a screen may show (episode count, status).
        public var extra: [String: String]?
    }

    public var items: [Item]
    /// An opaque cursor; empty means this was the last page.
    public var next: String?
}

/// One video: its playable lines, each holding the episodes a route offers.
public struct VideoDetails: Decodable, Sendable {
    public struct Line: Decodable, Sendable, Hashable, Identifiable {
        public struct Episode: Decodable, Sendable, Hashable, Identifiable {
            public var id: String
            public var title: String
        }

        public var id: String
        /// Core calls a line's label `name`, not `title`. Expecting `title` made
        /// every detail payload fail to decode, which reads in the app as a screen
        /// that spins for ever rather than as a contract mismatch.
        public var title: String
        public var episodes: [Episode]

        enum CodingKeys: String, CodingKey {
            case id, episodes
            case title = "name"
        }
    }

    public var id: String
    public var title: String
    public var cover: String?
    public var description: String?
    public var tags: [String]?
    public var lines: [Line]
}

/// What a provider says to play.
///
/// `url` is the media address and `headers` must travel with every request for
/// it — many origins check `Referer` or `User-Agent` per segment. A provider
/// may instead answer with `sniff`, which asks the client's WebView to load
/// `page` and report the first media request it sees.
public struct VideoPlay: Decodable, Sendable {
    public struct Sniff: Decodable, Sendable {
        public var page: String
        public var `match`: String?
    }

    public var url: String?
    public var format: String?
    /// Core's `http.Header` is a map of **lists** — `{"Referer": ["…"]}` — not a
    /// map of strings. Decoding it as `[String: String]` failed the whole answer,
    /// and the detail page then said the source gave no playable address.
    public var headers: [String: [String]]?
    public var encrypted: Bool?
    public var sniff: Sniff?

    public var isPlayable: Bool { (url?.isEmpty == false) && encrypted != true }

    /// The headers as one value each, which is what a request takes. A list is
    /// what Core sends because `http.Header` allows repeats; the first value is
    /// the one a client sends, and a header with no values is left out rather than
    /// sent empty.
    public var requestHeaders: [String: String] {
        guard let headers else { return [:] }
        return headers.compactMapValues { $0.first }
    }

    /// A play answer the client builds itself, for a file on this device.
    public init(url: String?, format: String? = nil, headers: [String: [String]]? = nil,
                encrypted: Bool? = nil, sniff: Sniff? = nil) {
        self.url = url
        self.format = format
        self.headers = headers
        self.encrypted = encrypted
        self.sniff = sniff
    }
}

extension PluginRecord {
    /// Video providers, in the order Core keeps them.
    public var isVideo: Bool {
        type == "video-js" || type == "kazumi-rule" || type == "builtin"
    }
}
