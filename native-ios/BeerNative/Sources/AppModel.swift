import Foundation
import Network
import Security

@MainActor
final class AppModel: ObservableObject {
    @Published var user: String?
    @Published var isAdmin = false
    @Published var isInvite = false
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var banner: String?
    @Published var isOnline = true
    @Published var serverVersion: String = ""
    @Published var wizardStep = 1
    @Published var wizardProduct: BeerProduct?

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
        _ = await api.discoverWorkingEndpoint()
        serverVersion = (try? await api.version()) ?? ""
        do {
            let me = try await api.me()
            if me.auth && me.user == nil {
                await logout()
                return
            }
            user = me.user
            isAdmin = me.isAdmin
            isInvite = me.isInvite
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

    func applyServerURL(_ raw: String) {
        let normalized = ServerSettings.normalizeInput(raw)
        ServerSettings.save(normalized)
        if let url = URL(string: normalized) {
            api.setBaseURL(url)
        }
    }

    func testServer() async -> String {
        if let ok = await api.discoverWorkingEndpoint() {
            return "Serveur OK · \(ok)"
        }
        return "Échec — autorise « Réseau local » pour Beer Log dans Réglages iPhone, puis réessaie."
    }

    func login(username: String, password: String) async throws {
        _ = try await api.login(username: username, password: password)
        let me = try await api.me()
        user = me.user ?? username
        isAdmin = me.isAdmin
        isInvite = me.isInvite
        isLoggedIn = me.user != nil
        KeychainStore.username = user
        banner = nil
        await syncPending()
    }

    func logout() async {
        await api.logout()
        user = nil
        isAdmin = false
        isInvite = false
        isLoggedIn = false
        KeychainStore.username = nil
        banner = nil
    }

    func startRetaste(_ item: CheckinItem, step: Int = 2) {
        wizardProduct = BeerProduct.from(checkin: item)
        wizardStep = step
    }

    func startQuickRate(_ item: CheckinItem) {
        wizardProduct = BeerProduct.from(checkin: item)
        wizardStep = 3
    }

    func startWishlistTaste(_ item: WishlistItem) {
        wizardProduct = BeerProduct(
            barcode: item.barcode ?? "",
            beerName: item.beerName,
            brewery: item.brewery ?? "—",
            style: item.style ?? "Unknown",
            summary: "\(item.beerName) — depuis À boire",
            source: "wishlist"
        )
        wizardStep = 1
    }

    func clearWizardPrefill() {
        wizardProduct = nil
        wizardStep = 1
    }

    func syncPending() async {
        guard isLoggedIn, isOnline else { return }
        let n = await offline.flush(using: api)
        if n > 0 { banner = "\(n) dégustation(s) synchronisée(s)" }
    }

    func saveCheckin(
        product: BeerProduct,
        rating: Double,
        flavors: [String],
        hops: [String],
        comment: String,
        photoJPEG: Data?,
        force: Bool
    ) async throws -> String {
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
            flavors: flavors,
            hops: hops,
            comment: comment,
            untappdBid: product.untappdBid.map(String.init) ?? "",
            force: force,
            photoJPEGBase64: photoJPEG?.base64EncodedString()
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
                flavors: flavors,
                hops: hops,
                comment: pending.comment,
                untappdBid: pending.untappdBid,
                force: pending.force,
                photoJPEG: photoJPEG
            )
            if result.duplicate == true {
                let pc = result.previousCheckin
                return "duplicate|\(pc?.beerName ?? product.beerName)|\(pc?.rating ?? 0)|\(pc?.createdAt ?? "")"
            }
            if result.ok == true || result.id != nil {
                return "Enregistré ✓"
            }
            throw BeerAPIError.server(result.error ?? "Échec")
        } catch {
            if case BeerAPIError.network(_) = error {
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