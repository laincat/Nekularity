import Foundation

public enum KnownServiceID {
    public static let bangumi = "service.bangumi"
    public static let tmdb = "service.tmdb"
    public static let trakt = "service.trakt"
}

public enum ServiceBridgeError: Error, LocalizedError, Equatable, Sendable {
    case notInstalled(String)
    case permissionDenied(service: String, missing: [String])
    case missingSecret(service: String, key: String)
    case accountUnavailable(String)
    case executionFailed(service: String, method: String)
    case invalidPayload(service: String, method: String)
    case invalidResponse(service: String, method: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id): "尚未安装服务包 \(id)"
        case .permissionDenied(let id, let missing): "服务包 \(id) 缺少权限：\(missing.joined(separator: "、"))"
        case .missingSecret(let id, let key): "服务包 \(id) 缺少凭据：\(key)"
        case .accountUnavailable(let id): "无法读取服务包 \(id) 的账号值"
        case .executionFailed(let id, let method): "服务包 \(id) 无法执行 \(method)"
        case .invalidPayload(let id, let method): "服务包 \(id) 的 \(method) 收到了无效的请求参数"
        case .invalidResponse(let id, let method): "服务包 \(id) 的 \(method) 返回了无法解析的数据"
        }
    }
}

/// Structured calls share the installed packages, transport and account vault of one profile.
public struct ServicePackageBridge: Sendable {
    typealias Find = @Sendable (String) async throws -> ServiceRecord?
    typealias Run = @Sendable (ServiceRecord, String, String, [String], [String: String]) async throws -> String

    private let find: Find
    private let run: Run
    private let grants: @Sendable (ServiceRecord) async -> Set<String>
    let accounts: any ServiceAccounts

    init(accounts: any ServiceAccounts, find: @escaping Find,
         grants: @escaping @Sendable (ServiceRecord) async -> Set<String>, run: @escaping Run) {
        self.accounts = accounts
        self.find = find
        self.grants = grants
        self.run = run
    }

    public func installed(_ id: String) async throws -> Bool {
        try await find(id) != nil
    }

    /// The outer optional represents package presence. A nullable operation declares
    /// an optional response type, so a successful JSON null stays distinguishable.
    public func invokeIfInstalled<Response: Decodable & Sendable>(
        _ id: String, method: String, payload: JSONValue = .null,
        secretKeys: [String] = [], as type: Response.Type
    ) async throws -> Response? {
        try await invoke(id, method: method, payload: payload, secretKeys: secretKeys,
                         accounts: accounts, as: type)
    }

    func invoke<Response: Decodable & Sendable>(
        _ id: String, method: String, payload: JSONValue = .null, secretKeys: [String],
        accounts: any ServiceAccounts, as type: Response.Type
    ) async throws -> Response? {
        try Task.checkCancellation()
        let record: ServiceRecord
        do {
            guard let installed = try await find(id) else { return nil }
            record = installed
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceBridgeError.executionFailed(service: id, method: method)
        }
        let required: Set<String> = secretKeys.isEmpty ? ["network"] : ["network", "secrets"]
        let effective = await grants(record).intersection(record.permissions ?? [])
        let missing = required.subtracting(effective).sorted()
        guard missing.isEmpty else { throw ServiceBridgeError.permissionDenied(service: id, missing: missing) }

        var secrets: [String: String] = [:]
        if !secretKeys.isEmpty {
            let values: [String: String]
            do { values = try accounts.values(service: id) }
            catch { throw ServiceBridgeError.accountUnavailable(id) }
            for key in secretKeys {
                guard let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ServiceBridgeError.missingSecret(service: id, key: key)
                }
                secrets[key] = value
            }
        }
        let text = payload.jsonText
        guard ServicePayload.isValid(text) else {
            throw ServiceBridgeError.invalidPayload(service: id, method: method)
        }
        try Task.checkCancellation()
        let raw: String
        do {
            raw = try await run(record, method, text, required.sorted(), secrets)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A package can put credentials in its own errors. Keep the diagnostic local to the method name.
            throw ServiceBridgeError.executionFailed(service: id, method: method)
        }
        try Task.checkCancellation()
        do {
            let decoded = try JSONValue.parse(raw)
            guard !decoded.containsServiceSecret(Array(secrets.values)) else {
                throw ServiceBridgeError.invalidResponse(service: id, method: method)
            }
            return .some(try Response(from: ValueDecoder(value: decoded, codingPath: [])))
        } catch {
            throw ServiceBridgeError.invalidResponse(service: id, method: method)
        }
    }
}

extension JSONValue {
    static func serviceArguments(_ fields: (String, JSONValue?)...) -> JSONValue {
        .object(OrderedObject(fields.compactMap { name, value in value.map { (name, $0) } }))
    }

    static func integer(_ value: Int) -> JSONValue { .number(String(value)) }

    fileprivate func containsServiceSecret(_ secrets: [String]) -> Bool {
        guard !secrets.isEmpty else { return false }
        switch self {
        case .string(let text), .number(let text): return secrets.contains { text.contains($0) }
        case .array(let items): return items.contains { $0.containsServiceSecret(secrets) }
        case .object(let object):
            return object.entries.contains { key, value in
                secrets.contains { key.contains($0) } || value.containsServiceSecret(secrets)
            }
        case .bool, .null: return false
        }
    }
}

/// Mutating methods return null or an explicit success acknowledgement.
struct ServiceAcknowledgement: Decodable, Sendable {
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { return }
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Bool.self, forKey: .ok) else {
            throw DecodingError.dataCorruptedError(forKey: .ok, in: fields, debugDescription: "operation failed")
        }
    }

    private enum CodingKeys: String, CodingKey { case ok }
}
