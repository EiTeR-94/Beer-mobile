import Foundation
import Network
import Security

@MainActor
final class AppModel: ObservableObject {
    @Published var user: String?
    @Published var isAdmin = false
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var banner: String?
    @Published var isOnline = true

    let api = BeerAPI.shared
    let offline = OfflineQueue()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "beer.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let online = path.status == .satisfied
                self?.isOnline = online
                if online { await self?.syncPending() }
            }
        }
        monitor.start(queue: monitorQueue)
        Task { await bootstrap() }
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await api.me()
            if me.auth && me.user == nil {
                await logout()
                return
            }
            user = me.user
            isAdmin = me.isAdmin
            isLoggedIn = me.user != nil
            if isLoggedIn { await syncPending() }
        } catch {
            if let saved = KeychainStore.username {
                user = saved
                isLoggedIn = true
                banner = isOnline ? "Session à vérifier" : "Hors ligne · \(saved)"
            }
        }
    }

    func login(username: String, password: String) async throws {
        let res = try await api.login(username: username, password: password)
        user = res.user ?? username
        isAdmin = res.isAdmin ?? false
        isLoggedIn = true
        KeychainStore.username = user
        banner = nil
        await syncPending()
    }

    func logout() async {
        await api.logout()
        user = nil
        isAdmin = false
        isLoggedIn = false
        KeychainStore.username = nil
        banner = nil
    }

    func syncPending() async {
        guard isLoggedIn, isOnline else { return }
        let n = await offline.flush(using: api)
        if n > 0 { banner = "\(n) dégustation(s) synchronisée(s)" }
    }

    func saveCheckin(product: BeerProduct, rating: Double, comment: String, force: Bool) async throws -> String {
        let pending = PendingCheckin(
            id: UUID(),
            createdAt: Date(),
            barcode: product.barcode,
            beerName: product.beerName,
            brewery: product.brewery,
            style: product.style,
            abv: product.abv.map { String($0) } ?? "",
            summary: product.summary,
            rating: rating,
            comment: comment,
            untappdBid: product.untappdBid.map(String.init) ?? "",
            force: force
        )

        if !isOnline {
            offline.enqueue(pending)
            return "Enregistré sur l'iPhone — sync au retour réseau"
        }

        do {
            let result = try await api.createCheckin(
                barcode: pending.barcode,
                beerName: pending.beerName,
                brewery: pending.brewery,
                style: pending.style,
                abv: pending.abv,
                summary: pending.summary,
                rating: pending.rating,
                comment: pending.comment,
                untappdBid: pending.untappdBid,
                force: pending.force
            )
            if result.duplicate == true {
                return "duplicate"
            }
            if result.ok == true || result.id != nil {
                return "Enregistré ✓"
            }
            throw BeerAPIError.server(result.error ?? "Échec")
        } catch {
            if case BeerAPIError.network = error {
                offline.enqueue(pending)
                return "Enregistré sur l'iPhone — sync au retour réseau"
            }
            if (error as NSError).domain == NSURLErrorDomain {
                offline.enqueue(pending)
                return "Enregistré sur l'iPhone — sync au retour réseau"
            }
            throw error
        }
    }
}

enum KeychainStore {
    private static let service = "fr.eiter.plexibeer"
    private static let account = "username"

    static var username: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else { return nil }
            return value
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            let add: [String: Any] = query.merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}