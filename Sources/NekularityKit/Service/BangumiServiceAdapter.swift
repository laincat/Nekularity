import Foundation

struct BangumiServiceAdapter: Sendable {
    static let id = KnownServiceID.bangumi
    static let tokenKey = "access_token"
    let bridge: ServicePackageBridge

    func call<Response: Decodable & Sendable>(
        _ method: String, _ payload: JSONValue = .null, authenticated: Bool = false,
        as type: Response.Type
    ) async throws -> Response? {
        try await bridge.invokeIfInstalled(Self.id, method: method, payload: payload,
                                           secretKeys: authenticated ? [Self.tokenKey] : [], as: type)
    }

    struct Subject: Decodable, Sendable {
        let model: BangumiSubject
        let episodes: [Episode]?

        init(from decoder: Decoder) throws {
            let wire = try JSONValue(from: decoder)
            episodes = try decoder.container(keyedBy: AnyKey.self).decodeIfPresent([Episode].self, forKey: AnyKey(stringValue: "episodes"))
            model = try Self.decodeModel(wire)
        }

        private static func decodeModel(_ wire: JSONValue) throws -> BangumiSubject {
            var fields = ["id", "type", "name", "summary", "date", "platform", "eps", "images", "rating", "collection"]
                .compactMap { key in wire[key].map { (key, $0) } }
            fields.append(("name_cn", wire["nameCn"] ?? .null))
            fields.append(("total_episodes", wire["totalEpisodes"] ?? .null))
            if let id = wire["id"]?.stringValue.flatMap(Int.init) {
                fields.removeAll { $0.0 == "id" }
                fields.append(("id", .integer(id)))
            }
            if let type = wire["type"]?.stringValue.flatMap(Int.init) {
                fields.removeAll { $0.0 == "type" }
                fields.append(("type", .integer(type)))
            }
            if wire["rating"] == nil, let score = wire["score"] {
                fields.append(("rating", .serviceArguments(("score", score))))
            }
            return try BangumiSubject(from: ValueDecoder(value: .object(OrderedObject(fields)), codingPath: []))
        }
    }

    struct Episode: Decodable, Sendable {
        let model: BangumiEpisode

        init(from decoder: Decoder) throws {
            let wire = try JSONValue(from: decoder)
            let value = JSONValue.serviceArguments(("id", wire["id"]), ("type", wire["type"]),
                                                   ("sort", wire["sort"]), ("name", wire["name"]),
                                                   ("name_cn", wire["nameCn"]), ("airdate", wire["airdate"]))
            model = try BangumiEpisode(from: ValueDecoder(value: value, codingPath: decoder.codingPath))
        }
    }

    struct Collection: Decodable, Sendable {
        let subjectId: Int
        let type: CollectionType
        let rate: Int?
        let epStatus: Int?
        let volStatus: Int?
        let comment: String?
        let subject: Subject?

        var model: BangumiCollection {
            BangumiCollection(subjectID: subjectId, type: type, rate: rate, epStatus: epStatus,
                              volStatus: volStatus, comment: comment, subject: subject?.model)
        }
    }

    struct CollectionDetail: Decodable, Sendable { let item: Collection? }
}
