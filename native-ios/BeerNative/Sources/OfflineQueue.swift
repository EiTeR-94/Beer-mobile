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
        items = (try? JSONDecoder().decode([PendingCheckin].self, from: data)) ?? []
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
                let result = try await api.createCheckin(
                    barcode: item.barcode,
                    beerName: item.beerName,
                    brewery: item.brewery,
                    style: item.style,
                    abv: item.abv,
                    summary: item.summary,
                    rating: item.rating,
                    flavors: [],
                    hops: [],
                    comment: item.comment,
                    untappdBid: item.untappdBid,
                    force: item.force
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