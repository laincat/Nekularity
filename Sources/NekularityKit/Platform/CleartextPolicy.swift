import Foundation

/// Which plain-http requests the app itself allows.
///
/// ATS is the outer gate: `App/Info.plist` no longer allows arbitrary loads,
/// keeps local networking, and names the one public host an official source
/// uses by default. ATS cannot ask a source what it needs, so this type is the
/// inner gate: even where ATS would permit a cleartext request, the app allows
/// it only for a local address or a declared source host.
///
/// The default is HTTPS. A public http address is refused for AI, accounts,
/// plugins, the collection index and themes; a comic or video source may use
/// one only when its host is listed in `declaredHTTPHosts` (and ATS names the
/// same host in `NSExceptionDomains`).
public enum CleartextPolicy {
    /// Public http hosts an official source needs.
    ///
    /// `lanraragi.js` defaults its API to `http://lrr.tvc-16.science` and its
    /// settings let the user change that address; the same host is the only
    /// entry in `NSExceptionDomains`. Anything else must be https, or local.
    public static let declaredHTTPHosts: Set<String> = ["lrr.tvc-16.science"]

    /// Whether `url` may be fetched in `partition`.
    ///
    /// `https` is always allowed. `http` is allowed to a local host for any
    /// partition — the interface tests, a LAN media server and a local Magpie
    /// all need it — and to a declared host for a comic or video source only.
    public static func allows(_ url: URL, partition: String) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            break
        default:
            // Other schemes never reach URLSession from these call sites, and
            // refusing them here keeps that true.
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if isLocal(host) { return true }
        guard CookiePartition.isContentSource(partition) else { return false }
        return declaredHTTPHosts.contains(host)
    }

    /// Loopback, link-local, private IPv4 and IPv6 unique-local addresses, plus
    /// `.local` names. These are the addresses that never leave the device or
    /// the local network, so a cleartext request to one cannot be read on the
    /// way to a public server.
    static func isLocal(_ host: String) -> Bool {
        // Foundation may keep the brackets of an IPv6 literal in `host`.
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        if host.hasSuffix(".local") { return true }
        // IPv6 link-local (fe80::/10) and unique-local (fc00::/7).
        if host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea")
            || host.hasPrefix("feb") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (169, 254):
            return true
        case (172, 16...31):
            return true
        default:
            return host.hasPrefix("127.")
        }
    }
}
