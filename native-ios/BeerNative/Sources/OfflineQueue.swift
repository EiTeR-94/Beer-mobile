import Foundation

@MainActor
final class OfflineQueue: ObservableObject {
    @Published private(set) var items: [PendingCheckin] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending-checkins.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([PendingCheckin].self, from: data) {
            items = decoded
            return
        }
        struct Legacy: Decodable {
            let id: UUID
            let createdAt: Date
            var barcode: String
            var beerName: String
            var brewery: String
            var style: String
            var abv: String
            var summary: String
            var rating: Double
            var comment: String
            var untappdBid: String
            var force: Bool
        }
        if let legacy = try? JSONDecoder().decode([Legacy].self, from: data) {
            items = legacy.map {
                PendingCheckin(
                    id: $0.id,
                    createdAt: $0.createdAt,
                    barcode: $0.barcode,
                    beerName: $0.beerName,
                    brewery: $0.brewery,
                    style: $0.style,
                    abv: $0.abv,
                    summary: $0.summary,
                    rating: $0.rating,
                    flavors: [],
                    hops: [],
                    comment: $0.comment,
                    untappdBid: $0.untappdBid,
                    force: $0.force,
                    photoJPEGBase64: nil
                )
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func enqueue(_ item: PendingCheckin) {
        items.append(item)
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func flush(using api: BeerAPI) async -> Int {
        var synced = 0
        for item in items {
            do {
                let photo = item.photoJPEGBase64.flatMap { Data(base64Encoded: $0) }
                let result = try await api.createCheckin(
                    barcode: item.barcode,
                    beerName: item.beerName,
                    brewery: item.brewery,
                    style: item.style,
                    abv: item.abv,
                    summary: item.summary,
                    rating: item.rating,
                    flavors: item.flavors,
                    hops: item.hops,
                    comment: item.comment,
                    untappdBid: item.untappdBid,
                    force: item.force,
                    photoJPEG: photo
                )
                if result.ok == true || result.id != nil {
                    remove(id: item.id)
                    synced += 1
                }
            } catch {
                break
            }
        }
        return synced
    }
}