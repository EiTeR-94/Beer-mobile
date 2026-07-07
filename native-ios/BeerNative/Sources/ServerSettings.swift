import Foundation

enum ServerSettings {
    /// URL canonique — invitations actives en 4G (session invité + appareil lié).
    static let canonicalHost = "eiter.freeboxos.fr"
    static let apiBaseString = "https://\(canonicalHost)/beer/"

    static var apiBase: URL {
        URL(string: apiBaseString)!
    }

    static var candidateURLs: [URL] {
        var urls = [apiBase]
        if let ipv4 = IPv4Resolver.resolve(canonicalHost),
           let fallback = URL(string: "https://\(ipv4)/beer/"),
           fallback != apiBase {
            urls.append(fallback)
        }
        return urls
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