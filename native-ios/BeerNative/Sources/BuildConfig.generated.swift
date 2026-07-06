// Placeholder local — écrasé par scripts/write-native-config.js au build
import Foundation

enum BuildConfig {
    static let apiBaseString = "https://CHANGE_ME:8444/beer"
    static var apiBase: URL {
        URL(string: apiBaseString)!
    }
}