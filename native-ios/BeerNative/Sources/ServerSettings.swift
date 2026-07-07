import Foundation

enum ServerSettings {
    static let canonicalHost = "eiter.freeboxos.fr"
    static let wanIPv4 = "82.64.151.113"
    static let apiBaseString = "https://\(canonicalHost)/beer/"

    static var apiBase: URL {
        URL(string: apiBaseString)!
    }

    static var wanApiBase: URL {
        URL(string: "https://\(wanIPv4)/beer/")!
    }

    /// Hub LAN — FQDN obligatoire (cookies domain=eiter.freeboxos.fr ; IP = session morte).
    static var lanApiBase: URL {
        URL(string: "https://\(canonicalHost):8444/beer/")!
    }

    /// Invités 5G : IP + token Bearer. Comptes perso : FQDN :8444 puis :443 (cookies OK).
    static func candidateURLs(guestMode: Bool = false) -> [URL] {
        if guestMode {
            return [wanApiBase]
        }
        return [lanApiBase, apiBase]
    }

    static func serverOrigin(from base: URL = apiBase) -> String {
        "https://\(canonicalHost)"
    }

    static func resolveAssetURL(_ path: String?, base: URL = apiBase) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        let origin: String
        if let host = base.host, IPv4Resolver.isIPv4(host) {
            origin = "https://\(host)"
        } else {
            origin = serverOrigin(from: base)
        }
        let p = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: origin + p)
    }

    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s + "/"
    }
}