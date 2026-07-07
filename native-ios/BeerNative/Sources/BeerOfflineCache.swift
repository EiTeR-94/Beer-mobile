import Foundation

/// Snapshots JSON des listes consultées en ligne (lecture HL).
@MainActor
final class BeerOfflineCache {
    static let shared = BeerOfflineCache()

    private let dir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("offline-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save<T: Encodable>(_ value: T, name: String) {
        guard let data = try? encoder.encode(CachedEnvelope(savedAt: Date(), payload: value)) else { return }
        try? data.write(to: file(name), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)),
              let env = try? decoder.decode(CachedEnvelope<T>.self, from: data) else { return nil }
        return env.payload
    }

    func savedAt(name: String) -> Date? {
        struct AnyEnvelope: Decodable { let savedAt: Date }
        guard let data = try? Data(contentsOf: file(name)),
              let env = try? decoder.decode(AnyEnvelope.self, from: data) else { return nil }
        return env.savedAt
    }

    private func file(_ name: String) -> URL {
        dir.appendingPathComponent("\(name).json")
    }
}

private struct CachedEnvelope<T: Codable>: Codable {
    let savedAt: Date
    let payload: T
}

enum CacheKey {
    static let historyCheckins = "history_checkins"
    static let historyStats = "history_stats"
    static let styles = "styles"
    static let gifts = "gifts"
    static let adminUsers = "admin_users"
    static let adminInvites = "admin_invites"
    static let adminReferentials = "admin_referentials"
}