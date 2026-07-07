// URL fixe — identique PWA
import Foundation

enum BuildConfig {
    static let apiBaseString = "https://eiter.freeboxos.fr/beer/"
    static let apiFallbacks: [String] = []
    static var apiBase: URL { URL(string: apiBaseString)! }
}