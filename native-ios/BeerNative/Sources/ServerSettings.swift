import Foundation

enum ServerSettings {
    private static let key = "beer_api_base_override"

    static var candidateURLs: [URL] {
        var raw: [String] = []
        if let saved = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            raw.append(normalizeInput(saved))
        }
        raw.append(BuildConfig.apiBaseString)
        raw.append(contentsOf: BuildConfig.apiFallbacks)
        var seen = Set<String>()
        return raw.compactMap { s -> URL? in
            let n = normalizeInput(s)
            guard !seen.contains(n), let u = URL(string: n) else { return nil }
            seen.insert(n)
            return u
        }
    }

    static var apiBase: URL {
        candidateURLs.first ?? BuildConfig.apiBase
    }

    static var apiBaseString: String {
        apiBase.absoluteString
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

    static func save(_ raw: String) {
        UserDefaults.standard.set(normalizeInput(raw), forKey: key)
    }

    /// Base API avec slash final — requis pour `URL(string:relativeTo:)` (sinon `/beer` est remplacé par `api/...`).
    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.contains(":8443") { s = s.replacingOccurrences(of: ":8443", with: ":8444") }
        return s + "/"
    }
}