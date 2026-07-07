import Foundation

private struct CacheEnvelopeEnc<P: Encodable>: Encodable {
    let savedAt: Date
    let payload: P
}

private struct CacheEnvelopeDec<P: Decodable>: Decodable {
    let savedAt: Date
    let payload: P
}

private struct CacheSavedAtEnvelope: Decodable {
    let savedAt: Date
}

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
        guard let data = try? encoder.encode(CacheEnvelopeEnc(savedAt: Date(), payload: value)) else { return }
        try? data.write(to: file(name), options: Data.WritingOptions.atomic)
    }

    func load<T: Decodable>(_ type: T.Type, name: String, maxAge: TimeInterval? = nil) -> T? {
        guard let data = try? Data(contentsOf: file(name)),
              let env = try? decoder.decode(CacheEnvelopeDec<T>.self, from: data) else { return nil }
        if let maxAge = maxAge {
            if Date().timeIntervalSince(env.savedAt) > maxAge {
                try? FileManager.default.removeItem(at: file(name))
                return nil
            }
        }
        return env.payload
    }

    func savedAt(name: String) -> Date? {
        guard let data = try? Data(contentsOf: file(name)),
              let env = try? decoder.decode(CacheSavedAtEnvelope.self, from: data) else { return nil }
        return env.savedAt
    }

    // Theme 5: explicit invalidation on delete etc.
    func remove(name: String) {
        try? FileManager.default.removeItem(at: file(name))
    }

    // Theme 5: basic size limit / prune old snapshots (call opportunistically)
    func prune(maxFiles: Int = 20) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted { (a, b) in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for f in sorted.dropFirst(maxFiles) {
            try? fm.removeItem(at: f)
        }
    }

    private func file(_ name: String) -> URL {
        dir.appendingPathComponent("\(name).json")
    }
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