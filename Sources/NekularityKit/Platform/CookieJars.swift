import Foundation

/// One cookie as Core's host interface describes it.
public struct WireCookie: Codable, Sendable, Hashable {
    public var name: String
    public var value: String
    /// A leading dot also matches subdomains; none means host-only.
    public var domain: String?
    public var path: String?
    /// Unix milliseconds, 0 or nil when absent.
    public var expires: Int64?
    /// Seconds, 0 or nil when absent.
    public var maxAge: Int?
    public var secure: Bool?
    public var httpOnly: Bool?

    public init(name: String, value: String, domain: String? = nil, path: String? = nil, expires: Int64? = nil,
                maxAge: Int? = nil, secure: Bool? = nil, httpOnly: Bool? = nil) {
        self.name = name; self.value = value; self.domain = domain; self.path = path
        self.expires = expires; self.maxAge = maxAge; self.secure = secure; self.httpOnly = httpOnly
    }
}

/// Cookie jars, one per partition (`comic:<key>` for comic sources).
///
/// Sources must never see each other's cookies, so partitions are fully
/// separate. Matching follows RFC 6265: host-only versus domain cookies,
/// path prefixes, Secure, and expiry. Session cookies are kept only in
/// memory; persistent ones are saved to `file`.
public final class CookieJars: @unchecked Sendable {
    struct Stored: Codable, Hashable {
        var name: String
        var value: String
        /// Lower-case, no leading dot.
        var domain: String
        var hostOnly: Bool
        var path: String
        var secure: Bool
        var httpOnly: Bool
        /// nil for a session cookie.
        var expiresAt: Date?
    }

    private let lock = NSLock()
    private var jars: [String: [Stored]] = [:]
    private let file: URL?
    private let now: @Sendable () -> Date

    public init(file: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.file = file
        self.now = now
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: [Stored]].self, from: data) {
            jars = saved
        }
    }

    // MARK: Core host interface

    /// Cookies the jar would send to url.
    public func cookies(partition: String, url: URL) -> [WireCookie] {
        lock.lock(); defer { lock.unlock() }
        return matching(partition, url).map { s in
            WireCookie(name: s.name, value: s.value, domain: s.hostOnly ? s.domain : "." + s.domain, path: s.path,
                       expires: s.expiresAt.map { Int64($0.timeIntervalSince1970 * 1000) }, secure: s.secure, httpOnly: s.httpOnly)
        }
    }

    /// Stores cookies received for url.
    public func save(partition: String, url: URL, cookies: [WireCookie]) {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var jar = jars[partition] ?? []
        for c in cookies {
            guard let s = stored(c, host: host, url: url) else { continue }
            jar.removeAll { $0.name == s.name && $0.domain == s.domain && $0.path == s.path }
            if let exp = s.expiresAt, exp <= now() { continue } // an expired cookie deletes
            jar.append(s)
        }
        jars[partition] = jar
        persist()
    }

    /// Removes every cookie that would be sent to url.
    public func delete(partition: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        let doomed = Set(matching(partition, url, ignoreSecure: true))
        jars[partition]?.removeAll { doomed.contains($0) }
        persist()
    }

    /// Removes a whole partition (on uninstall or logout).
    public func clear(partition: String) {
        lock.lock(); defer { lock.unlock() }
        jars[partition] = nil
        persist()
    }

    // MARK: HTTP integration

    /// The Cookie header value for url, or nil.
    public func header(partition: String, url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        let list = matching(partition, url)
        guard !list.isEmpty else { return nil }
        return list.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Stores Set-Cookie headers from a response.
    public func store(partition: String, url: URL, setCookieHeaders: [String]) {
        let parsed = setCookieHeaders.compactMap { Self.parseSetCookie($0, now: now()) }
        save(partition: partition, url: url, cookies: parsed)
    }

    /// Writes cookies that came from a backup into one partition.
    ///
    /// These are not page-set, so the domain is taken as given rather than
    /// checked against a request host: the backup is a local file the user chose
    /// to restore. Entries whose domain is not a host are skipped, and the count
    /// returned is what was actually stored. Restoring never falls back to a
    /// shared jar — the caller names one partition at a time.
    @discardableResult
    public func restore(partition: String, cookies: [WireCookie]) -> Int {
        var stored = 0
        lock.lock(); defer { lock.unlock() }
        var jar = jars[partition] ?? []
        for c in cookies {
            let name = c.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !c.value.isEmpty else { continue }
            let raw = (c.domain ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let hostOnly = !raw.hasPrefix(".")
            let domain = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
            guard Self.isHost(domain) else { continue }
            let path = (c.path?.isEmpty == false) ? (c.path ?? "/") : "/"
            var expiresAt: Date?
            if let ms = c.expires, ms > 0 {
                let when = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
                // Already dead: writing it would store a row the jar can never
                // send, and the count would claim a sign-in that no longer works.
                if when <= now() { continue }
                expiresAt = when
            }
            let row = Stored(name: name, value: c.value, domain: domain, hostOnly: hostOnly,
                             path: path.hasPrefix("/") ? path : "/" + path,
                             secure: c.secure ?? false, httpOnly: c.httpOnly ?? false, expiresAt: expiresAt)
            jar.removeAll { $0.name == row.name && $0.domain == row.domain && $0.path == row.path }
            jar.append(row)
            stored += 1
        }
        jars[partition] = jar
        persist()
        return stored
    }

    /// A domain a cookie could belong to, as opposed to junk such as `https://x`.
    static func isHost(_ domain: String) -> Bool {
        !domain.isEmpty && domain.contains(".") && !domain.contains("/")
            && !domain.contains(":") && !domain.contains(" ")
    }

    /// Copies cookies from a WebView after a challenge (cf_clearance).
    public func importCookies(partition: String, _ cookies: [HTTPCookie]) {
        lock.lock(); defer { lock.unlock() }
        var jar = jars[partition] ?? []
        for c in cookies {
            let domain = c.domain.lowercased()
            let s = Stored(name: c.name, value: c.value, domain: domain.hasPrefix(".") ? String(domain.dropFirst()) : domain,
                           hostOnly: !domain.hasPrefix("."), path: c.path.isEmpty ? "/" : c.path,
                           secure: c.isSecure, httpOnly: c.isHTTPOnly, expiresAt: c.expiresDate)
            jar.removeAll { $0.name == s.name && $0.domain == s.domain && $0.path == s.path }
            jar.append(s)
        }
        jars[partition] = jar
        persist()
    }

    // MARK: Internals; callers hold the lock.

    private func stored(_ c: WireCookie, host: String, url: URL) -> Stored? {
        guard !c.name.isEmpty else { return nil }
        var domain = host
        var hostOnly = true
        if let d = c.domain?.lowercased().trimmingCharacters(in: .whitespaces), !d.isEmpty {
            let bare = d.hasPrefix(".") ? String(d.dropFirst()) : d
            // A page may only set cookies for its own host or a parent
            // domain, and never for a bare IP's parent.
            guard host == bare || (host.hasSuffix("." + bare) && !Self.isIP(host) && bare.contains(".")) else { return nil }
            domain = bare
            // Core marks domain cookies with a leading dot; without one the
            // cookie is host-only.
            hostOnly = !d.hasPrefix(".")
        }
        var path = c.path ?? ""
        if !path.hasPrefix("/") { path = Self.defaultPath(url) }
        var expiresAt: Date?
        if let m = c.maxAge, m != 0 { expiresAt = now().addingTimeInterval(TimeInterval(m)) }
        else if let e = c.expires, e != 0 { expiresAt = Date(timeIntervalSince1970: TimeInterval(e) / 1000) }
        return Stored(name: c.name, value: c.value, domain: domain, hostOnly: hostOnly, path: path,
                      secure: c.secure ?? false, httpOnly: c.httpOnly ?? false, expiresAt: expiresAt)
    }

    private func matching(_ partition: String, _ url: URL, ignoreSecure: Bool = false) -> [Stored] {
        guard let host = url.host()?.lowercased() else { return [] }
        let path = url.path().isEmpty ? "/" : url.path()
        let secure = url.scheme?.lowercased() == "https"
        let t = now()
        var jar = jars[partition] ?? []
        let before = jar.count
        jar.removeAll { ($0.expiresAt.map { $0 <= t }) ?? false }
        if jar.count != before { jars[partition] = jar }
        return jar.filter { c in
            let domainOK = c.hostOnly ? host == c.domain : (host == c.domain || host.hasSuffix("." + c.domain))
            return domainOK && Self.pathMatches(path, c.path) && (ignoreSecure || !c.secure || secure)
        }
        // Longer paths first, as RFC 6265 recommends.
        .sorted { $0.path.count > $1.path.count }
    }

    private func persist() {
        guard let file else { return }
        let persistent = jars.mapValues { $0.filter { $0.expiresAt != nil } }.filter { !$0.value.isEmpty }
        if let data = try? JSONEncoder().encode(persistent) {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func pathMatches(_ request: String, _ cookie: String) -> Bool {
        if request == cookie { return true }
        guard request.hasPrefix(cookie) else { return false }
        return cookie.hasSuffix("/") || request.dropFirst(cookie.count).first == "/"
    }

    static func defaultPath(_ url: URL) -> String {
        let p = url.path()
        guard p.hasPrefix("/"), let i = p.lastIndex(of: "/"), i != p.startIndex else { return "/" }
        return String(p[..<i])
    }

    static func isIP(_ host: String) -> Bool {
        host.contains(":") || host.split(separator: ".").allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    /// Parses one Set-Cookie header.
    static func parseSetCookie(_ header: String, now: Date) -> WireCookie? {
        let parts = header.split(separator: ";", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let eq = first.firstIndex(of: "=") else { return nil }
        var c = WireCookie(name: String(first[..<eq]).trimmingCharacters(in: .whitespaces),
                           value: String(first[first.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
        guard !c.name.isEmpty else { return nil }
        for attr in parts.dropFirst() {
            let kv = attr.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let k = kv[0].lowercased()
            let v = kv.count > 1 ? kv[1] : ""
            switch k {
            case "domain": if !v.isEmpty { c.domain = "." + (v.hasPrefix(".") ? String(v.dropFirst()) : v) }
            case "path": c.path = v
            case "max-age": if let n = Int(v) { c.maxAge = n <= 0 ? -1 : n }
            case "expires": if let d = httpDate(v) { c.expires = Int64(d.timeIntervalSince1970 * 1000) }
            case "secure": c.secure = true
            case "httponly": c.httpOnly = true
            default: break
            }
        }
        if c.maxAge == -1 { c.maxAge = nil; c.expires = 1 } // in the past: delete
        return c
    }

    static func httpDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE, dd-MMM-yyyy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
