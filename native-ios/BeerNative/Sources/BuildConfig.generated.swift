// Placeholder — écrasé au build CI
import Foundation

enum BuildConfig {
    static let apiBaseString = "https://192.168.1.50:8444/beer/"
    static let apiFallbacks: [String] = [
        "https://192.168.1.50:8444/beer/",
        "https://eiter.freeboxos.fr:8444/beer/",
    ]
    static var apiBase: URL { URL(string: apiBaseString)! }
}