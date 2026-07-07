import Foundation

enum BeerFormatters {
    static func snappedRating(_ r: Double) -> Double {
        (r * 4).rounded() / 4
    }

    static func ratingLabel(_ r: Double) -> String {
        let n = snappedRating(r)
        if n.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(n))"
        }
        return String(format: "%.2f", n)
    }

    /// Affichage slider : largeur fixe (comme `.note-value` PWA).
    static func ratingSliderText(_ r: Double) -> String {
        let n = snappedRating(r)
        if n.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(n))/5"
        }
        return String(format: "%.2f/5", n)
    }

    static func formatActivityAgo(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return formatDate(raw) }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "à l'instant" }
        if diff < 3600 {
            let min = Int(diff / 60)
            return "il y a \(min) min"
        }
        if diff < 86400 {
            let h = Int(diff / 3600)
            return "il y a \(h) h"
        }
        return formatDate(raw)
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