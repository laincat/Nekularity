import Foundation

/// A standard AI service Core knows how to talk to without any plugin.
///
/// These three protocols are built into Core: OpenAI Chat Completions, OpenAI
/// Responses and Anthropic Messages. Everything else — other vendors, routing
/// between accounts, quota lookups, content masking — belongs to a Magpie
/// package. Keeping the two apart is the point: an OpenAI key should work
/// without installing anything.
public enum StandardProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case chat
    case responses
    case messages

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: "OpenAI Chat"
        case .responses: "OpenAI Responses"
        case .messages: "Anthropic Messages"
        }
    }

    /// Which vendor the endpoint belongs to, for the key and the header naming.
    public var vendor: String { self == .messages ? "Anthropic" : "OpenAI" }

    /// The default API root. A user-specified root replaces the whole root.
    public var defaultBaseURL: String {
        self == .messages ? "https://api.anthropic.com/v1" : "https://api.openai.com/v1"
    }

    /// The protocol requires a token limit: Anthropic refuses the request
    /// without one, and a guess is worse than a documented default.
    public var needsMaxTokens: Bool { self == .messages }
}

/// What the user configured for one protocol. The key is not part of it: it
/// goes to the Keychain, and this value is safe to store anywhere.
public struct StandardAIConfig: Codable, Sendable, Hashable {
    public var `protocol`: StandardProtocol
    public var baseURL: String
    public var model: String
    public var anthropicVersion: String
    public var maxTokens: Int

    public init(protocol standard: StandardProtocol = .chat, baseURL: String = "", model: String = "",
                anthropicVersion: String = "", maxTokens: Int = 4096) {
        self.protocol = standard
        self.baseURL = baseURL
        self.model = model
        self.anthropicVersion = anthropicVersion
        self.maxTokens = maxTokens
    }

    /// The root actually used: what the user typed, or the vendor's default.
    public var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? `protocol`.defaultBaseURL : trimmed
    }

    /// The JSON Core reads. The partition is fixed: an AI request never shares
    /// a comic source's cookie jar.
    public func wireJSON(apiKey: String) throws -> String {
        var body: [String: Any] = [
            "protocol": `protocol`.rawValue,
            "apiKey": apiKey,
            "partition": StandardAI.partition,
        ]
        if !baseURL.trimmingCharacters(in: .whitespaces).isEmpty { body["baseUrl"] = baseURL }
        if !anthropicVersion.isEmpty { body["anthropicVersion"] = anthropicVersion }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// One message sent to a standard endpoint.
public struct StandardMessage: Codable, Sendable, Hashable {
    public var role: String
    public var content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// The request Core built, in the wire shape the host bridge uses. Exposed so a
/// caller can send it on its own connection — which is where streaming will go.
public struct StandardAIWireRequest: Decodable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: [String]]
    public var bodyBase64: String?
    public var cookies: Bool
    public var partition: String?
}

/// What came back from a standard endpoint.
public struct StandardAIAnswer: Decodable, Sendable {
    public var status: Int
    public var headers: [String: [String]]
    public var bodyBase64: String
    public var finalUrl: String
    /// False whenever the reply was not delivered incrementally. Core cannot
    /// stream yet, so a caller must show this rather than pretend.
    public var streamed: Bool

    public var body: Data { Data(base64Encoded: bodyBase64) ?? Data() }

    public var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// Standard-protocol requests through Core, with the reply decoded into text.
public final class StandardAI: @unchecked Sendable {
    /// The cookie partition every standard AI request names. It never enables
    /// cookies; it only keeps AI traffic out of a comic source's jar.
    public static let partition = "ai"

    private let core: CoreClient

    public init(core: CoreClient) {
        self.core = core
    }

    /// Sends one conversation and returns the answer text.
    ///
    /// The reply is delivered whole: Core reports `streamed: false`, and this
    /// method surfaces that instead of silently pretending. A caller that needs
    /// incremental text has to wait for the streaming bridge.
    public func reply(config: StandardAIConfig, apiKey: String, messages: [StandardMessage]) async throws -> StandardAIReply {
        guard !messages.isEmpty else { throw StandardAIError("没有要发送的消息") }
        let trimmedModel = config.model.trimmingCharacters(in: .whitespaces)
        guard !trimmedModel.isEmpty else { throw StandardAIError("先填一个模型名") }
        let body = try Self.requestBody(config: config, model: trimmedModel, messages: messages)
        let answer = try await core.sendAIRequest(configJSON: try config.wireJSON(apiKey: apiKey), bodyJSON: body)
        let providerError: String?
        if case .object(let root) = try? JSONValue.parse(answer.bodyText) {
            providerError = Self.errorMessage(root)
        } else {
            providerError = nil
        }
        guard (200..<300).contains(answer.status) else {
            let detail = providerError.map { ": " + $0 } ?? ""
            throw StandardAIError("接口返回 HTTP \(answer.status)\(detail)")
        }
        if let providerError { throw StandardAIError(providerError) }
        return StandardAIReply(status: answer.status, text: Self.text(from: answer, protocol: config.protocol),
                               raw: answer.bodyText, streamed: answer.streamed)
    }

    /// The models the endpoint lists. A vendor that refuses to list them is an
    /// error, not an empty catalog.
    public func models(config: StandardAIConfig, apiKey: String) async throws -> [String] {
        let wire = try await core.buildAIModelsRequest(configJSON: try config.wireJSON(apiKey: apiKey))
        guard let url = URL(string: wire.url) else { throw StandardAIError("模型目录地址无效") }
        var headers = wire.headers
        if headers.keys.first(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) == nil {
            headers["Accept"] = ["application/json"]
        }
        let response = try await core.host.transport.send(.init(
            id: Int64.random(in: 1_000_000..<2_000_000), method: wire.method, url: url, headers: headers,
            body: nil, useCookies: false, partition: wire.partition ?? StandardAI.partition))
        guard (200..<300).contains(response.status) else {
            throw StandardAIError("模型目录返回 HTTP \(response.status)")
        }
        return try Self.modelIDs(response.body)
    }

    /// The body each protocol expects. Written per protocol rather than being
    /// translated: Core forwards it as it is.
    ///
    /// Static so it can be checked without starting a Core runtime: the body is
    /// the one part of this file with rules worth pinning.
    public static func requestBody(config: StandardAIConfig, model: String, messages: [StandardMessage]) throws -> String {
        var doc: [String: Any] = ["model": model, "stream": false]
        switch config.protocol {
        case .messages:
            doc["messages"] = messages.map { ["role": $0.role, "content": $0.content] }
            doc["max_tokens"] = max(1, config.maxTokens)
        case .chat:
            doc["messages"] = messages.map { ["role": $0.role, "content": $0.content] }
        case .responses:
            doc["input"] = messages.map { ["role": $0.role, "content": $0.content] }
        }
        let data = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Pulls the text out of whichever shape the protocol answered with. An
    /// unrecognised shape keeps the raw JSON rather than showing nothing: a
    /// blank screen would hide a real answer.
    public static func text(from answer: StandardAIAnswer, protocol standard: StandardProtocol) -> String {
        guard case .object(let root) = try? JSONValue.parse(answer.bodyText) else { return answer.bodyText }
        if let failure = errorMessage(root) { return failure }
        switch standard {
        case .chat:
            if let choices = root["choices"]?.array, let first = choices.first,
               case .object(let choice) = first,
               case .object(let m)? = choice["message"],
               let text = m["content"]?.stringValue, !text.isEmpty {
                return text
            }
        case .messages:
            if let content = root["content"]?.array {
                let text = content.compactMap { item -> String? in
                    guard case .object(let o) = item, o["type"]?.stringValue == "text" else { return nil }
                    return o["text"]?.stringValue
                }.joined()
                if !text.isEmpty { return text }
            }
        case .responses:
            if let text = root["output_text"]?.stringValue, !text.isEmpty { return text }
            if let output = root["output"]?.array {
                let text = output.compactMap { item -> String? in
                    guard case .object(let o) = item, o["type"]?.stringValue == "message",
                          let content = o["content"]?.array else { return nil }
                    return content.compactMap { part -> String? in
                        guard case .object(let p) = part else { return nil }
                        return p["text"]?.stringValue
                    }.joined()
                }.joined()
                if !text.isEmpty { return text }
            }
        }
        return answer.bodyText
    }

    private static func errorMessage(_ root: OrderedObject) -> String? {
        guard let raw = root["error"] else { return nil }
        if case .string(let text) = raw { return text }
        if case .object(let o) = raw { return o["message"]?.stringValue }
        return nil
    }

    static func modelIDs(_ data: Data) throws -> [String] {
        guard case .object(let root) = try? JSONValue.parse(String(decoding: data, as: UTF8.self)),
              let list = root["data"]?.array else {
            throw StandardAIError("模型目录不是预期的 JSON")
        }
        return list.compactMap { item -> String? in
            guard case .object(let o) = item, let id = o["id"]?.stringValue, !id.isEmpty else { return nil }
            return id
        }
    }
}

/// One answer, with the text already extracted.
public struct StandardAIReply: Sendable, Hashable {
    public var status: Int
    public var text: String
    /// The body as the endpoint sent it, for a caller that needs a field this
    /// version does not understand yet.
    public var raw: String
    /// False: Core delivered the whole body, not an incrementally streamed one.
    public var streamed: Bool
}

public struct StandardAIError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
