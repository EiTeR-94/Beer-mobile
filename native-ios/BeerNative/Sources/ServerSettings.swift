import Foundation

/// Miroir exact d'Android `ServerSettings.kt`
enum ServerSettings {
    static let canonicalHost = "eiter.freeboxos.fr"
    static let wanIPv4 = "82.64.151.113"
    static let apiBaseString = "https://\(canonicalHost)/beer/"
    /// Fallback 4G si AAAA Freebox casse le TLS (IPv4 + SNI host).
    static let wanIPv4ApiBaseString = "https://\(wanIPv4)/beer/"
    static let lanApiBaseString = "https://192.168.1.50:8444/beer/"
    static let lanProbeTimeoutSec: TimeInterval = 15

    static var apiBase: URL { URL(string: apiBaseString)! }
    static var wanIPv4ApiBase: URL { URL(string: wanIPv4ApiBaseString)! }
    static var lanApiBase: URL { URL(string: lanApiBaseString)! }

    private static var runtimeBase: String?

    /// Mode invité : forcer WAN (jamais LAN Freebox).
    static var inviteMode: Bool = false
    /// 5G : ne pas sonder le LAN.
    static var preferWanOnly: Bool = false

    static var effectiveBase: String {
        if inviteMode {
            if let r = runtimeBase, !isLanEndpoint(r) { return r }
            return apiBaseString
        }
        return runtimeBase ?? lanApiBaseString
    }

    /// Comme Android candidateURLs (+ skip LAN en 5G).
    static var candidateURLs: [String] {
        if inviteMode {
            return [apiBaseString]
        }
        if preferWanOnly {
            return [apiBaseString]
        }
        return [lanApiBaseString, apiBaseString]
    }

    /// Un seul endpoint FQDN : le dial IPv4 est forcé dans HomelabIPv4Transport
    /// (candidate IP pure + rewrite cassait le SNI / doublonnait le FQDN).
    static let inviteCandidateURLs: [String] = [apiBaseString]

    static func isLanEndpoint(_ url: String) -> Bool {
        url.contains(":8444")
    }

    static func isLanEndpoint(_ url: URL) -> Bool {
        url.port == 8444
    }

    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s + "/"
    }

    static func setRuntimeBase(_ url: String?) {
        runtimeBase = (url?.isEmpty == false) ? normalizeInput(url!) : nil
    }

    static func resetToLan() {
        runtimeBase = nil
    }

    static func serverOrigin(from base: URL = apiBase) -> String {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.path = ""
        c.query = nil
        c.fragment = nil
        return c.string ?? base.absoluteString
    }

    static func resolveAssetURL(_ path: String?, base: URL = lanApiBase) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        let origin = serverOrigin(from: base)
        let p = path.hasPrefix("/") ? path : "/\(path)"
        if p.hasPrefix("/beer/") || p.hasPrefix("/static/") || p.hasPrefix("/photos/") {
            return URL(string: origin + p)
        }
        let root = normalizeInput(base.absoluteString)
        return URL(string: root + (p.hasPrefix("/") ? String(p.dropFirst()) : p))
    }
}

