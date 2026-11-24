import Foundation

struct BangumiServiceAdapter: Sendable {
    static let id = KnownServiceID.bangumi
    static let tokenKey = "token"
    let bridge: ServicePackageBridge

    func call<Response: Decodable & Sendable>(
        _ method: String, _ payload: JSONValue = .null, authenticated: Bool = false,
        as type: Response.Type
    ) async throws -> Response? {
        try await bridge.invokeIfInstalled(Self.id, method: method, payload: payload,
                                           secretKeys: authenticated ? [Self.tokenKey] : [], as: type)
    }
}
