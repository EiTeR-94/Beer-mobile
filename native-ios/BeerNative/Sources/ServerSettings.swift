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
            guard !seen.contains(s), let u = URL(string: s) else { return nil }
            seen.insert(s)
            return u
        }
    }

    static var apiBase: URL {
        candidateURLs.first ?? BuildConfig.apiBase
    }

    static var apiBaseString: String {
        apiBase.absoluteString
    }

    static func save(_ raw: String) {
        UserDefaults.standard.set(normalizeInput(raw), forKey: key)
    }

    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.contains(":8443") { s = s.replacingOccurrences(of: ":8443", with: ":8444") }
        return s
    }
}