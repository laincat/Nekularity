import Foundation

/// One piece of a streamed reply.
public struct MagpieChatEvent: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case text, reasoning, done, error, end
        /// A kind Core reported that this version does not know yet.
        case other
    }

    public var kind: Kind
    public var text: String
    public var finish: String
    /// The vendor's token count as JSON text, kept as it was written.
    public var usageJSON: String

    public init(kind: Kind, text: String = "", finish: String = "", usageJSON: String = "") {
        self.kind = kind
        self.text = text
        self.finish = finish
        self.usageJSON = usageJSON
    }
}

/// A conversation through one provider package.
///
/// Core hands out events when asked, because gomobile cannot push into Swift;
/// this turns that into an async sequence so a view can simply read it and stop
/// when the view goes away.
public final class MagpieChat: @unchecked Sendable {
    private let core: MagpieRunner.Core
    private let pollInterval: Duration

    public init(core: MagpieRunner.Core, pollInterval: Duration = .milliseconds(40)) {
        self.core = core
        self.pollInterval = pollInterval
    }

    /// Sends one turn and yields its events. Cancelling the reading task (or the
    /// surrounding view disappearing) cancels the request in Core, so a closed
    /// screen stops costing a vendor request.
    public func send(
        model: String,
        messages: [MagpieMessage],
        system: String = "",
        maxTokens: Int = 0
    ) -> AsyncThrowingStream<MagpieChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [core, pollInterval] in
                var handle: Int64?
                defer {
                    // Whoever stopped reading — a cancelled task or a view that
                    // went away — the vendor request stops here too.
                    if let handle { core.chatCancel(handle: handle) }
                }
                do {
                    let messagesJSON = try Self.encode(messages)
                    let started = try core.chatStart(model: model, messagesJSON: messagesJSON,
                                                     system: system, maxTokens: maxTokens)
                    guard let opened = Self.handle(from: started) else {
                        throw MagpieError("这一轮对话没有开始:\(started)")
                    }
                    handle = opened
                    while true {
                        if Task.isCancelled { continuation.finish(); return }
                        let answer = try core.chatNext(handle: opened)
                        if answer.isEmpty {
                            try? await Task.sleep(for: pollInterval)
                            continue
                        }
                        let event = Self.event(from: answer)
                        if event.kind == .end {
                            continuation.finish()
                            return
                        }
                        continuation.yield(event)
                    }
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    static func handle(from json: String) -> Int64? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let id = object["id"] as? Int64 { return id }
        if let number = object["id"] as? NSNumber { return number.int64Value }
        return nil
    }

    static func event(from json: String) -> MagpieChatEvent {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return MagpieChatEvent(kind: .error, text: "无法解析的事件") }
        let kind = MagpieChatEvent.Kind(rawValue: object["kind"] as? String ?? "") ?? .other
        var usage = ""
        if let raw = object["usage"],
           let usageData = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) {
            usage = String(decoding: usageData, as: UTF8.self)
        }
        return MagpieChatEvent(
            kind: kind,
            text: object["text"] as? String ?? "",
            finish: object["finish"] as? String ?? "",
            usageJSON: usage
        )
    }

    private static func encode(_ messages: [MagpieMessage]) throws -> String {
        let data = try JSONEncoder().encode(messages)
        return String(decoding: data, as: UTF8.self)
    }
}

/// One turn as Core expects it.
public struct MagpieMessage: Codable, Hashable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
