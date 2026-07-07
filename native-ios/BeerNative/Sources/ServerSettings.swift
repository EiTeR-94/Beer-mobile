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

    /// Hub LAN :8444 — cookies admin OK (FQDN). :443 = fallback IPv4 (passkey / 4G).
    /// On WiFi/VPN, relies on local DNS or hairpin to reach internal. Host header must be the domain for nginx server_name.
    static var lanApiBase: URL {
        URL(string: "https://\(canonicalHost):8444/beer/")!
    }

    static var candidateURLs: [URL] {
        [lanApiBase, apiBase]
    }

    static var passkeyBaseURLs: [URL] {
        [apiBase]
    }

    /// :8444 hub/LAN — probe court (hors LAN = fail fast, pas 15s de timeout).
    static let lanProbeTimeoutSec: TimeInterval = 4

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