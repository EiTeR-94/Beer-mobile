import Foundation

/// Miroir exact d'Android `ServerSettings.kt`
enum ServerSettings {
    static let canonicalHost = "eiter.freeboxos.fr"
    static let wanIPv4 = "82.64.151.113"
    static let apiBaseString = "https://\(canonicalHost)/beer/"
    /// Portail DL IPA/APK + versions.json
    static let portalURLString = "https://\(canonicalHost)/mobile/beer/"
    static let versionsURLString = "https://\(canonicalHost)/mobile/beer/versions.json"
    /// Fallback 4G si AAAA Freebox casse le TLS (IPv4 + SNI host).
    static let wanIPv4ApiBaseString = "https://\(wanIPv4)/beer/"
    static let lanApiBaseString = "https://192.168.1.50:8444/beer/"
    /// Beerquest alpha (clone isolé) — invites IPA/APK
    static let alphaApiBaseString = "https://\(canonicalHost)/beer-alpha/"
    static let alphaWanIPv4ApiBaseString = "https://\(wanIPv4)/beer-alpha/"
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
            let primary = (runtimeBase.flatMap { isLanEndpoint($0) ? nil : $0 }) ?? apiBaseString
            if isAlphaBase(primary) {
                return [primary, alphaWanIPv4ApiBaseString]
            }
            return [primary, wanIPv4ApiBaseString]
        }
        if preferWanOnly {
            return [apiBaseString, wanIPv4ApiBaseString]
        }
        return [lanApiBaseString, apiBaseString]
    }

    static var inviteCandidateURLs: [String] {
        [apiBaseString, wanIPv4ApiBaseString, alphaApiBaseString, alphaWanIPv4ApiBaseString]
    }

    static func isAlphaBase(_ url: String) -> Bool {
        url.contains("/beer-alpha")
    }

    /// Déduit les bases API depuis un lien d'invitation (prod beer vs beer-alpha).
    static func basesFromInviteLink(_ link: String) -> [String] {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = s.range(of: "/join/") else {
            return inviteCandidateURLs
        }
        let prefix = String(s[..<range.lowerBound])
        if prefix.contains("/beer-alpha") {
            return [alphaApiBaseString, alphaWanIPv4ApiBaseString]
        }
        return [apiBaseString, wanIPv4ApiBaseString]
    }

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
        if p.hasPrefix("/beer/") || p.hasPrefix("/beer-alpha/") || p.hasPrefix("/static/") || p.hasPrefix("/photos/") {
            return URL(string: origin + p)
        }
        let root = normalizeInput(base.absoluteString)
        return URL(string: root + (p.hasPrefix("/") ? String(p.dropFirst()) : p))
    }
}

