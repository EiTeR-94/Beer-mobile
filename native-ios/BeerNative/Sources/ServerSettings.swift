import Foundation

enum ServerSettings {
    /// FQDN affiché (liens invitation, Host header).
    static let canonicalHost = "eiter.freeboxos.fr"
    /// IP WAN Freebox — évite l'AAAA IPv6 cassée en 4G.
    static let wanIPv4 = "82.64.151.113"
    static let apiBaseString = "https://\(wanIPv4)/beer/"

    static var apiBase: URL {
        URL(string: apiBaseString)!
    }

    static var candidateURLs: [URL] {
        var urls: [URL] = [apiBase]
        if let fqdn = URL(string: "https://\(canonicalHost)/beer/") {
            urls.append(fqdn)
        }
        if let lan = URL(string: "https://192.168.1.50:8444/beer/") {
            urls.append(lan)
        }
        return urls
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