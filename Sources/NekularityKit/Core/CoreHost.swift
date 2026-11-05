import Foundation
import VeneraCatCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What Core asks the user. The app implements it with SwiftUI.
///
/// Methods are called on the main actor and may suspend until the user
/// answers. nil means the user closed the UI without choosing.
@MainActor
public protocol SourceUI: AnyObject {
    func showMessage(_ message: String)
    func showDialog(title: String, content: String, actions: [DialogButton]) async -> Int?
    /// errorMessage is nil the first time and the script's message after a
    /// rejected entry.
    func askText(title: String, imageURL: String?, errorMessage: String?) async -> String?
    func askChoice(title: String, options: [String], initialIndex: Int?) async -> Int?
    func open(url: URL)
    func showLoading(id: Int64)
    func hideLoading(id: Int64)
    /// Runs a human-verification page and reports what it cleared the way
    /// with, or nil when the user gives up.
    func verify(_ challenge: Challenge) async -> VerificationOutcome?
}

public struct DialogButton: Decodable, Sendable, Hashable {
    public var text: String
    /// "text", "filled" or "danger".
    public var style: String
}

/// What a passed challenge hands back. A cookie-based clearance binds to the
/// WebView's User-Agent; an edge clearance comes back as query parameters of
/// the guarded address, and there is no cookie at all.
public struct VerificationOutcome: Sendable {
    public var userAgent: String
    public var query: [String: String]

    public init(userAgent: String, query: [String: String] = [:]) {
        self.userAgent = userAgent
        self.query = query
    }
}

/// A page Core wants the user to pass in a browser.
public struct Challenge: Decodable, Sendable {
    public var kind: String
    public var url: String
    public var partition: String
    public var absentMarkers: [String]?
    public var requiredCookies: [String]?
    /// Parameters that must be in the page's own query. A challenge that solves
    /// itself in page script records its result here instead of in a cookie.
    public var requiredQueryParams: [String]?
    /// The page must be back on the host of `url`. A challenge page usually
    /// lives elsewhere, so this is what says it has handed the browser over;
    /// without it a blank window would satisfy a markers-only rule.
    public var sameHost: Bool?
}

/// The client side of Core: implements `MobileHostProtocol`.
///
/// gomobile calls these methods on Go threads and they may block, so the
/// work that needs Swift concurrency (HTTP, UI) is bridged with a semaphore.
/// That is safe because Core never calls the host on a thread that the
/// awaited work needs: HTTP runs on URLSession's queues and UI on the main
/// actor, and Core is never called from the main thread (see CoreClient).
public final class CoreHost: NSObject, MobileHostProtocol, @unchecked Sendable {
    public let store: SourceStore
    public let cookies: CookieJars
    public let transport: URLSessionTransport
    private let logSink: @Sendable (String, String, String) -> Void

    private let lock = NSLock()
    private weak var _ui: SourceUI?
    // Core retains its Host across the Go/ObjC bridge. Keep this callback
    // reference weak so CoreClient deinit can close and release the engine.
    private weak var core: MobileCore?

    /// The UI that answers source requests. Without one, dialogs are
    /// treated as closed.
    @MainActor public var ui: SourceUI? {
        get { lock.withLock { _ui } }
        set { lock.withLock { _ui = newValue } }
    }

    public init(store: SourceStore, cookies: CookieJars, transport: URLSessionTransport,
                log: @escaping @Sendable (String, String, String) -> Void = { _, _, _ in }) {
        self.store = store
        self.cookies = cookies
        self.transport = transport
        self.logSink = log
    }

    func attach(_ core: MobileCore) { lock.withLock { self.core = core } }

    // MARK: Blocking bridges

    /// Runs async work and blocks the calling Go thread until it is done.
    private func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        precondition(!Thread.isMainThread, "Core must not call the host on the main thread")
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            sem.signal()
        }
        sem.wait()
        return try box.result!.get()
    }

    private func withUI<T: Sendable>(_ fallback: T, _ body: @escaping @MainActor @Sendable (SourceUI) async -> T) -> T {
        (try? blocking { @MainActor [weak self] in
            guard let ui = self?.ui else { return fallback }
            return await body(ui)
        }) ?? fallback
    }

    private static func json<T: Encodable>(_ v: T) -> String {
        (try? String(decoding: JSONEncoder().encode(v), as: UTF8.self)) ?? "null"
    }

    private static func fail(_ error: NSErrorPointer, _ message: String) {
        error?.pointee = NSError(domain: "Nekularity", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: HTTP

    private struct WireRequest: Decodable {
        var id: Int64
        var method: String
        var url: String
        var headers: [String: [String]]?
        var bodyBase64: String?
        /// Optional on purpose: the contract lists the field, but a host that
        /// left it out used to fail the whole request with "the data couldn't
        /// be read because it is missing" before anything was dialled.
        var cookies: Bool?
        var partition: String?
    }

    private struct WireResponse: Encodable {
        var status: Int
        var headers: [String: [String]]
        var bodyBase64: String
        var finalUrl: String
    }

    public func http(_ requestJSON: String?, error: NSErrorPointer) -> String {
        do {
            let w = try JSONDecoder().decode(WireRequest.self, from: Data((requestJSON ?? "").utf8))
            guard let url = URL(string: w.url) else { throw CoreError("invalid URL \(w.url)") }
            var body: Data?
            if let b = w.bodyBase64, !b.isEmpty {
                guard let d = Data(base64Encoded: b) else { throw CoreError("invalid request body") }
                body = d
            }
            let req = URLSessionTransport.Request(id: w.id, method: w.method, url: url, headers: w.headers ?? [:],
                                                  body: body, useCookies: w.cookies ?? false,
                                                  partition: w.partition ?? "")
            let transport = self.transport
            let resp = try blocking { try await transport.send(req) }
            return Self.json(WireResponse(status: resp.status, headers: resp.headers,
                                          bodyBase64: resp.body.base64EncodedString(), finalUrl: resp.finalURL.absoluteString))
        } catch let e {
            Self.fail(error, e.localizedDescription)
            return ""
        }
    }

    public func cancelHTTP(_ id_: Int64) { transport.cancel(id: id_) }

    public func verify(_ challengeJSON: String?, error: NSErrorPointer) -> String {
        guard let c = try? JSONDecoder().decode(Challenge.self, from: Data((challengeJSON ?? "").utf8)) else {
            Self.fail(error, "invalid challenge")
            return ""
        }
        guard let outcome = withUI(VerificationOutcome?.none, { await $0.verify(c) }) else {
            Self.fail(error, "verification dismissed")
            return ""
        }
        var body: [String: Any] = ["userAgent": outcome.userAgent]
        if !outcome.query.isEmpty {
            body["query"] = outcome.query
        }
        return (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    // MARK: Storage

    public func loadData(_ key: String?, dataKey: String?, error: NSErrorPointer) -> String {
        do { return try store.loadData(key: key ?? "", dataKey: dataKey ?? "") ?? "" } catch let e {
            Self.fail(error, e.localizedDescription)
            return ""
        }
    }

    public func saveData(_ key: String?, dataKey: String?, valueJSON: String?) throws {
        try store.saveData(key: key ?? "", dataKey: dataKey ?? "", json: valueJSON ?? "null")
    }

    public func deleteData(_ key: String?, dataKey: String?) throws {
        try store.deleteData(key: key ?? "", dataKey: dataKey ?? "")
    }

    public func loadSetting(_ key: String?, settingKey: String?, error: NSErrorPointer) -> String {
        do { return try store.loadSetting(key: key ?? "", settingKey: settingKey ?? "") ?? "" } catch let e {
            Self.fail(error, e.localizedDescription)
            return ""
        }
    }

    public func isLogged(_ key: String?) -> Bool { store.isLogged(key: key ?? "") }

    public func log(_ level: String?, title: String?, content: String?) {
        logSink(level ?? "", title ?? "", content ?? "")
    }

    // MARK: Cookies

    public func loadCookies(_ partition: String?, url: String?, error: NSErrorPointer) -> String {
        guard let u = URL(string: url ?? "") else {
            Self.fail(error, "invalid URL")
            return ""
        }
        return Self.json(cookies.cookies(partition: partition ?? "", url: u))
    }

    public func saveCookies(_ partition: String?, url: String?, cookiesJSON: String?) throws {
        guard let u = URL(string: url ?? "") else { throw CoreError("invalid URL") }
        let list = try JSONDecoder().decode([WireCookie].self, from: Data((cookiesJSON ?? "[]").utf8))
        cookies.save(partition: partition ?? "", url: u, cookies: list)
    }

    public func deleteCookies(_ partition: String?, url: String?) throws {
        guard let u = URL(string: url ?? "") else { throw CoreError("invalid URL") }
        cookies.delete(partition: partition ?? "", url: u)
    }

    // MARK: Source UI

    public func showMessage(_ message: String?) {
        let m = message ?? ""
        Task { @MainActor [weak self] in self?.ui?.showMessage(m) }
    }

    public func showDialog(_ title: String?, content: String?, actionsJSON: String?, error: NSErrorPointer) -> String {
        let actions = (try? JSONDecoder().decode([DialogButton].self, from: Data((actionsJSON ?? "[]").utf8))) ?? []
        let t = title ?? "", c = content ?? ""
        guard let i = withUI(Int?.none, { await $0.showDialog(title: t, content: c, actions: actions) }) else { return "" }
        return Self.json(["index": i])
    }

    public func showInputDialog(_ title: String?, image: String?, errorMessage: String?, error: NSErrorPointer) -> String {
        let t = title ?? ""
        let img = (image?.isEmpty ?? true) ? nil : image
        let msg = (errorMessage?.isEmpty ?? true) ? nil : errorMessage
        guard let text = withUI(String?.none, { await $0.askText(title: t, imageURL: img, errorMessage: msg) }) else { return "" }
        return Self.json(["text": text])
    }

    public func showSelectDialog(_ title: String?, optionsJSON: String?, initialIndex: Int64, error: NSErrorPointer) -> String {
        let options = (try? JSONDecoder().decode([String].self, from: Data((optionsJSON ?? "[]").utf8))) ?? []
        let t = title ?? ""
        let initial = initialIndex >= 0 ? Int(initialIndex) : nil
        guard let i = withUI(Int?.none, { await $0.askChoice(title: t, options: options, initialIndex: initial) }) else { return "" }
        return Self.json(["index": i])
    }

    public func launchURL(_ url: String?) {
        // Only web links; a source must not open arbitrary app schemes.
        guard let u = URL(string: url ?? ""), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return }
        Task { @MainActor [weak self] in self?.ui?.open(url: u) }
    }

    public func showLoading(_ id_: Int64) {
        Task { @MainActor [weak self] in self?.ui?.showLoading(id: id_) }
    }

    public func cancelLoading(_ id_: Int64) {
        Task { @MainActor [weak self] in self?.ui?.hideLoading(id: id_) }
    }

    /// Called by the UI when the user dismisses a loading indicator.
    public func loadingDismissed(id: Int64) {
        nonisolated(unsafe) let core = lock.withLock { self.core }
        DispatchQueue.global().async { core?.loadingDismissed(id) }
    }

    // MARK: Clipboard

    public func writeClipboard(_ text: String?) throws {
        let t = text ?? ""
        try blocking { await Clipboard.write(t) }
    }

    public func readClipboard(_ error: NSErrorPointer) -> String {
        (try? blocking { await Clipboard.read() }) ?? ""
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

/// The system pasteboard, on the main actor.
enum Clipboard {
    @MainActor static func write(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    @MainActor static func read() -> String {
        #if canImport(UIKit)
        UIPasteboard.general.string ?? ""
        #elseif canImport(AppKit)
        NSPasteboard.general.string(forType: .string) ?? ""
        #else
        ""
        #endif
    }
}

