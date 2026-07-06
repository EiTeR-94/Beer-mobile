import Foundation

enum BeerFormatters {
    static func ratingLabel(_ r: Double) -> String {
        String(format: "%.2f", (r * 4).rounded() / 4)
            .replacingOccurrences(of: ".00", with: "")
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    static func starFillWidth(_ rating: Double, totalWidth: CGFloat = 55) -> CGFloat {
        CGFloat(min(5, max(0, rating)) / 5.0) * totalWidth
    }

    static func normalizeSearch(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    static func formatDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return String(raw.prefix(10)) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}