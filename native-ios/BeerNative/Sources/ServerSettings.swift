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

    /// Invités 4G/5G : FQDN uniquement (comme la PWA). Admin : FQDN → LAN → WAN.
    static func candidateURLs(guestMode: Bool = false) -> [URL] {
        if guestMode {
            return [apiBase]
        }
        let lan = URL(string: "https://192.168.1.50:8444/beer/")!
        return [apiBase, lan, wanApiBase]
    }

    static func serverOrigin(from base: URL = apiBase) -> String {
        "https://\(canonicalHost)"
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