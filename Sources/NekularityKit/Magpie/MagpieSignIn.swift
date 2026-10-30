import Foundation

/// One sign-in in progress: the page the user opens, and the wait for it to
/// finish.
///
/// A package's callback polls the vendor itself, so this waits on the package
/// rather than inventing a poll interval of its own; the sleep only keeps the
/// loop from spinning when a package answers immediately.
public struct MagpieSignInStart: Sendable, Hashable {
    /// The id the package knows this sign-in by.
    public var id: Int64
    public var url: URL?
    /// A code the user types on the page, when the package gives one.
    public var userCode: String
    /// The package's own sentence, often naming the code.
    public var instructions: String
    public var expiresIn: Int
}

public enum MagpieSignInOutcome: Sendable {
    /// Signed in. `authJSON` is what to store, in Magpie's own shape.
    case success(authJSON: String)
    case failed(reason: String)
    case cancelled
}

/// Turns a package's sign-in answers into something worth storing.
///
/// Magpie's own host does this mapping: a successful device flow leaves
/// `{type: "oauth", refresh}`, and a key-based method leaves
/// `{type: "api", key}`. Core hands over the package's answer; the shape it is
/// kept in is decided here, once, with a test.
public enum MagpieAuthShape {
    public static func stored(from result: String, inputs: [String: String]) throws -> String? {
        guard let data = result.data(using: .utf8), !result.isEmpty else { return nil }
        // A bare `null` is valid JSON but not a top-level object to
        // JSONSerialization unless fragments are allowed.
        guard let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                as? [String: Any] else {
            return nil
        }
        guard object["type"] as? String == "success" else { return nil }
        if let refresh = object["refresh"] as? String, !refresh.isEmpty {
            var auth: [String: String] = ["type": "oauth", "refresh": refresh]
            if let access = object["access"] as? String, !access.isEmpty {
                auth["access"] = access
            }
            if let enterprise = object["enterpriseUrl"] as? String, !enterprise.isEmpty {
                auth["enterpriseUrl"] = enterprise
            }
            return try text(auth)
        }
        if let key = object["key"] as? String, !key.isEmpty {
            return try text(["type": "api", "key": key])
        }
        // A method that collected a key itself: the user typed it, so it is
        // kept without the package handing it back.
        if let key = inputs["key"], !key.isEmpty {
            return try text(["type": "api", "key": key])
        }
        return nil
    }

    /// A sign-in the vendor refused, with its own words when it gave any.
    public static func failure(from result: String) -> String {
        guard let data = result.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "登录未完成" }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        return "登录未完成"
    }

    private static func text(_ object: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// Drives one sign-in to an end, and can be stopped when the user walks away.
public final class MagpieSignIn: @unchecked Sendable {
    private let core: MagpieRunner.Core
    private let store: MagpieAuthStore
    private let provider: String
    private let inputs: [String: String]
    private let pollInterval: Duration
    /// A package that keeps answering "nothing yet" must not keep the screen
    /// waiting for ever; the device code itself expires, and so does this.
    private let timeout: Duration

    private let lock = NSLock()
    private var started: MagpieSignInStart?
    private var cancelled = false

    public init(
        core: MagpieRunner.Core,
        store: MagpieAuthStore,
        provider: String,
        inputs: [String: String] = [:],
        pollInterval: Duration = .milliseconds(500),
        timeout: Duration = .seconds(600)
    ) {
        self.core = core
        self.store = store
        self.provider = provider
        self.inputs = inputs
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// Starts the method and reports what to show the user.
    public func start(methodIndex: Int = 0) throws -> MagpieSignInStart {
        let inputsJSON = try Self.encode(inputs)
        let json = try core.authorize(methodIndex: methodIndex, inputsJSON: inputsJSON)
        guard let decoded = try Self.decode(MagpieSignInStartDTO.self, from: json) else {
            throw MagpieError("这一登录方式没有返回任何内容")
        }
        let start = MagpieSignInStart(
            id: decoded.id,
            url: decoded.url.flatMap(URL.init(string:)),
            // The package may send any of these or none; the struct keeps them
            // non-optional so a view never has to unwrap a missing field.
            userCode: decoded.userCode ?? "",
            instructions: decoded.instructions ?? "",
            expiresIn: decoded.expiresIn ?? 0
        )
        lock.withLock { started = start }
        return start
    }

    /// Waits for the package's callback. Cancellation reaches the package, so a
    /// callback still polling the vendor stops instead of running on.
    public func waitForResult() async -> MagpieSignInOutcome {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if ContinuousClock.now > deadline { return .failed(reason: "登录超时,请重新开始") }
            if lock.withLock({ cancelled }) { return .cancelled }
            guard let start = lock.withLock({ started }) else { return .failed(reason: "登录尚未开始") }
            do {
                let answer = try core.poll(id: start.id)
                if let stored = try MagpieAuthShape.stored(from: answer, inputs: inputs) {
                    try store.saveAuthJSON(provider: provider, json: stored)
                    return .success(authJSON: stored)
                }
                // An empty or `null` answer means the package has nothing to say
                // yet, which is the same as "still waiting": turning it into a
                // failure would end a sign-in the user is still completing.
                if answer.isEmpty || answer == "null" {
                    try? await Task.sleep(for: pollInterval)
                    continue
                }
                if answer.contains(#""type":"failed""#) {
                    return .failed(reason: MagpieAuthShape.failure(from: answer))
                }
                // A package that answers without a token is still waiting.
            } catch {
                return .failed(reason: error.localizedDescription)
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// Stops waiting and tells the package, so its callback does not keep
    /// polling a vendor for a user who has gone.
    public func cancel() {
        let start = lock.withLock { () -> MagpieSignInStart? in
            cancelled = true
            return started
        }
        guard let start else { return }
        try? core.cancelSignIn(id: start.id)
    }

    private struct MagpieSignInStartDTO: Decodable {
        var id: Int64
        var url: String?
        var userCode: String?
        var instructions: String?
        var expiresIn: Int?
    }

    private static func encode(_ inputs: [String: String]) throws -> String {
        guard !inputs.isEmpty else { return "" }
        let data = try JSONSerialization.data(withJSONObject: inputs, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T? {
        guard !json.isEmpty, json != "null" else { return nil }
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
