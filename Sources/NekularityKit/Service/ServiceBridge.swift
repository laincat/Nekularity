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
    case unsupportedMethod(service: String, method: String)
    case transportUnavailable(service: String, method: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id): "尚未安装服务包 \(id)"
        case .permissionDenied(let id, let missing): "服务包 \(id) 缺少权限：\(missing.joined(separator: "、"))"
        case .missingSecret(let id, let key): "服务包 \(id) 缺少凭据：\(key)"
        case .accountUnavailable(let id): "无法读取服务包 \(id) 的账号值"
        case .executionFailed(let id, let method): "服务包 \(id) 无法执行 \(method)"
        case .invalidPayload(let id, let method): "服务包 \(id) 的 \(method) 收到了无效的请求参数"
        case .invalidResponse(let id, let method): "服务包 \(id) 的 \(method) 返回了无法解析的数据"
        case .unsupportedMethod(let id, let method): "服务包 \(id) 尚不支持 \(method)"
        case .transportUnavailable(let id, let method): "当前 Core 的服务 HTTP 接口无法执行 \(id) 的 \(method)"
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
        secretKeys: [String] = [], oneOfSecretKeys: [String] = [], as type: Response.Type
    ) async throws -> Response? {
        try await invoke(id, method: method, payload: payload, secretKeys: secretKeys,
                         oneOfSecretKeys: oneOfSecretKeys, accounts: accounts, as: type)
    }

    func invoke<Response: Decodable & Sendable>(
        _ id: String, method: String, payload: JSONValue = .null, secretKeys: [String],
        oneOfSecretKeys: [String] = [], accounts: any ServiceAccounts, as type: Response.Type
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
        let needsSecrets = !secretKeys.isEmpty || !oneOfSecretKeys.isEmpty
        let required: Set<String> = needsSecrets ? ["network", "secrets"] : ["network"]
        let effective = await grants(record).intersection(record.permissions ?? [])
        let missing = required.subtracting(effective).sorted()
        guard missing.isEmpty else { throw ServiceBridgeError.permissionDenied(service: id, missing: missing) }

        var secrets: [String: String] = [:]
        if needsSecrets {
            let values: [String: String]
            do { values = try accounts.values(service: id) }
            catch { throw ServiceBridgeError.accountUnavailable(id) }
            for key in secretKeys {
                guard let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ServiceBridgeError.missingSecret(service: id, key: key)
                }
                secrets[key] = value
            }
            if let preferred = oneOfSecretKeys.first {
                guard let key = oneOfSecretKeys.first(where: { values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
                    throw ServiceBridgeError.missingSecret(service: id, key: preferred)
                }
                secrets[key] = values[key]
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
        } catch let error as ServiceBridgeError {
            throw error
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
            let answer: JSONValue
            if decoded["service"] != nil || decoded["method"] != nil {
                guard decoded["service"] == .string(id), decoded["method"] == .string(method) else {
                    throw ServiceBridgeError.invalidResponse(service: id, method: method)
                }
                switch decoded["ok"] {
                case .bool(true):
                    guard let data = decoded["data"] else { throw ServiceBridgeError.invalidResponse(service: id, method: method) }
                    answer = type == ServiceAcknowledgement.self ? decoded : data
                case .bool(false):
                    if decoded["error"]?["code"] == .string("UNSUPPORTED_METHOD") {
                        throw ServiceBridgeError.unsupportedMethod(service: id, method: method)
                    }
                    throw ServiceBridgeError.executionFailed(service: id, method: method)
                default: throw ServiceBridgeError.invalidResponse(service: id, method: method)
                }
            } else {
                answer = decoded
            }
            return .some(try Response(from: ValueDecoder(value: answer, codingPath: [])))
        } catch let error as ServiceBridgeError {
            throw error
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

struct ServiceItems<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
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
