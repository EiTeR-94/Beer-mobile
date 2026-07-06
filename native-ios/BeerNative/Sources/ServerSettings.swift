import Foundation

enum ServerSettings {
    private static let key = "beer_api_base_override"

    static var apiBase: URL {
        if let saved = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty,
           let url = URL(string: saved) {
            return url
        }
        return BuildConfig.apiBase
    }

    static var apiBaseString: String {
        apiBase.absoluteString
    }

    static func save(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    static func normalizeInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if s.contains(":8443") { s = s.replacingOccurrences(of: ":8443", with: ":8444") }
        return s
    }
}