import Foundation

enum ServerSettings {
    static let canonicalHost = "eiter.freeboxos.fr"
    /// IPv4 WAN — AAAA Freebox injoignable ; utilisé par PlexiIPv4URLProtocol.
    static let wanIPv4 = "82.64.151.113"

    /// URL canonique — LAN, VPN et 4G via le FQDN Plexi (:443, TCP forcé IPv4).
    static let apiBaseString = "https://\(canonicalHost)/beer/"

    static var apiBase: URL {
        URL(string: apiBaseString)!
    }

    /// Direct LAN IP for local accounts (WiFi/VPN) — avoids DNS/hairpin issues.
    /// Uses 192.168.1.50:8444, TLS delegate accepts it.
    /// Falls back to FQDN (with forced IPv4 on :443) if direct IP unreachable.
    static var lanApiBase: URL {
        URL(string: "https://192.168.1.50:8444/beer/")!
    }

    static var candidateURLs: [URL] {
        [lanApiBase, apiBase]
    }

    static var passkeyBaseURLs: [URL] {
        [apiBase]
    }

    /// :8444 hub/LAN — probe court (hors LAN = fail fast, pas 15s de timeout).
    /// Augmenté un peu pour VPN (latence + handshake).
    static let lanProbeTimeoutSec: TimeInterval = 8

    static func isLanEndpoint(_ url: URL) -> Bool {
        url.port == 8444
    }

    static func serverOrigin(from base: URL = apiBase) -> String {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.path = ""
        c.query = nil
        c.fragment = nil
        return c.string ?? base.absoluteString
    }

    static func resolveAssetURL(_ path: String?, base: URL = apiBase) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        let origin = serverOrigin(from: base)
        let p = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: origin + p)
    }

    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s + "/"
    }
}