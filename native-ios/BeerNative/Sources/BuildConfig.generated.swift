// Généré au build CI — NE PAS ÉDITER
import Foundation

enum BuildConfig {
    static let apiBaseString = "https://eiter.freeboxos.fr/beer/"
    static let apiFallbacks: [String] = []
    static var apiBase: URL { URL(string: apiBaseString)! }
}
