import Foundation

enum ServerSettings {
    static let canonicalHost = "eiter.freeboxos.fr"
    /// IPv4 WAN fallback (kept for reference, but owner-only native now uses LAN/VPN only).
    static let wanIPv4 = "82.64.151.113"

    /// URL for main account (owner only via LAN IP or VPN).
    static let apiBaseString = "https://\(canonicalHost)/beer/"

    static var apiBase: URL {
        URL(string: apiBaseString)!
    }

    /// Direct LAN IP for owner (WiFi or VPN). Avoids domain IPv6 issues on Freebox.
    /// Main (and only) path now.
    static var lanApiBase: URL {
        URL(string: "https://192.168.1.50:8444/beer/")!
    }

    static var candidateURLs: [URL] {
        // Try direct LAN IP first (fast, avoids DNS/IPv6 issues), fallback to domain (for VPN)
        [lanApiBase, apiBase]
    }

    /// No longer used: guest/invite paths removed (owner only, main account).
    static var passkeyBaseURLs: [URL] {
        []
    }

    /// :8444 hub/LAN — probe court (hors LAN = fail fast, pas 15s de timeout).
    /// Augmenté un peu pour VPN (latence + handshake). Theme 3 correction.
    static let lanProbeTimeoutSec: TimeInterval = 10

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