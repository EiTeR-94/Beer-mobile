import Foundation

@MainActor
final class OfflineQueue: ObservableObject {
    @Published private(set) var items: [PendingCheckin] = []
    @Published private(set) var pendingDeletes: [Int] = []  // Theme 5: support offline deletes
    @Published private(set) var pendingEdits: [Int] = []  // Priority 6 stub: offline edits (needs backend PATCH + diffing for full)

    private let fileURL: URL
    private let deletesFileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending-checkins.json")
        deletesFileURL = dir.appendingPathComponent("pending-deletes.json")
        load()
        loadDeletes()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([PendingCheckin].self, from: data) {
            items = decoded
            return
        }
        // Legacy decoder removed (Theme 1: clean legacy code)
        items = []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // Theme 5: deletes queue
    func enqueueDelete(checkinId: Int) {
        if !pendingDeletes.contains(checkinId) {
            pendingDeletes.append(checkinId)
            persistDeletes()
        }
    }

    func removePendingDelete(checkinId: Int) {
        pendingDeletes.removeAll { $0 == checkinId }
        persistDeletes()
    }

    // Priority 6: stub for offline edits support (enqueued on edit when offline)
    func enqueueEdit(checkinId: Int) {
        if !pendingEdits.contains(checkinId) {
            pendingEdits.append(checkinId)
            // persist stub omitted for minimal change; full would save diffs
        }
    }

    private func persistDeletes() {
        guard let data = try? JSONEncoder().encode(pendingDeletes) else { return }
        try? data.write(to: deletesFileURL, options: .atomic)
    }

    private func loadDeletes() {
        guard let data = try? Data(contentsOf: deletesFileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            pendingDeletes = decoded
        }
    }

    func hasSimilar(_ item: PendingCheckin) -> Bool {
        items.contains { existing in
            existing.beerName == item.beerName
                && existing.rating == item.rating
                && existing.comment == item.comment
                && abs(existing.createdAt.timeIntervalSince(item.createdAt)) < 180
        }
    }

    func enqueue(_ item: PendingCheckin) {
        guard !hasSimilar(item) else { return }
        items.append(item)
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func flush(using api: BeerAPI) async -> Int {
        var synced = 0
        let snapshot = items
        for item in snapshot {
            guard items.contains(where: { $0.id == item.id }) else { continue }
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
                if result.ok == true || result.id != nil || result.duplicate == true {
                    remove(id: item.id)
                    synced += 1
                }
            } catch {
                break
            }
        }

        // Theme 5: flush pending deletes
        let deleteSnapshot = pendingDeletes
        for id in deleteSnapshot {
            guard pendingDeletes.contains(id) else { continue }
            do {
                try await api.deleteCheckin(id: id)
                removePendingDelete(checkinId: id)
                synced += 1
            } catch {
                break
            }
        }
        return synced
    }
}