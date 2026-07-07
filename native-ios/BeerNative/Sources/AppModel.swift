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
    @Published var toast: ToastPayload?
    @Published var isOnline = true
    @Published var serverVersion: String = ""
    @Published var wizardStep = 1
    @Published var wizardProduct: BeerProduct?

    let api = BeerAPI.shared
    let offline = OfflineQueue()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "beer.network")
    private var toastTask: Task<Void, Never>?

    init() {
        api.setBaseURL(ServerSettings.apiBase)
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
                if isOnline {
                    showToast("Session à vérifier", variant: .warn)
                } else {
                    showToast("Hors ligne · \(saved)", variant: .info, durationMs: 4200)
                }
            }
        }
    }

    func applyServerURL(_ raw: String) {
        _ = raw
        api.setBaseURL(ServerSettings.apiBase)
    }

    func testServer() async -> String {
        api.setBaseURL(ServerSettings.apiBase)
        if let ok = await api.discoverWorkingEndpoint() {
            return "Serveur OK · \(ok)"
        }
        return "Échec — vérifie ta connexion Wi‑Fi ou VPN Plexi."
    }

    func login(username: String, password: String) async throws {
        _ = try await api.login(username: username, password: password)
        let me = try await api.me()
        user = me.user ?? username
        isAdmin = me.isAdmin
        isInvite = me.isInvite
        isLoggedIn = me.user != nil
        KeychainStore.username = user
        hideToast()
        await syncPending()
    }

    func handleOpenURL(_ url: URL) async {
        guard let token = Self.parseJoinToken(from: url) else { return }
        await redeemInviteToken(token)
    }

    func redeemInviteToken(_ token: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await api.redeemInvite(token: token)
            let me = try await api.me()
            user = me.user ?? res.user
            isAdmin = me.isAdmin
            isInvite = me.isInvite
            isLoggedIn = me.user != nil
            if let user { KeychainStore.username = user }
            hideToast()
            let label = res.label ?? user ?? "invité"
            showToast("Bienvenue \(label) !", variant: .success, durationMs: 3600)
            await syncPending()
        } catch let err {
            showToast(err.localizedDescription, variant: .error, durationMs: 4800)
        }
    }

    private static func parseJoinToken(from url: URL) -> String? {
        if url.scheme?.lowercased() == "plexibeer", url.host == "join" {
            let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return token.isEmpty ? nil : token
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: "join"), idx + 1 < parts.count else { return nil }
        let token = parts[idx + 1]
        return token.isEmpty ? nil : token
    }

    func logout() async {
        await api.logout()
        user = nil
        isAdmin = false
        isInvite = false
        isLoggedIn = false
        KeychainStore.username = nil
        hideToast()
    }

    func showToast(
        _ message: String,
        variant: ToastPayload.Variant = .info,
        detail: String? = nil,
        label: String? = nil,
        durationMs: Int = 2800
    ) {
        toastTask?.cancel()
        toast = ToastPayload(variant: variant, message: message, detail: detail, label: label)
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            hideToast()
        }
    }

    func hideToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
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
        if n > 0 {
            showToast("\(n) dégustation(s) synchronisée(s)", variant: .success)
        }
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