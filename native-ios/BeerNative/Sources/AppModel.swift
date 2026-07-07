import Foundation
import Network
import Security
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum NetworkStatus: Equatable {
        case online
        case serverUnreachable
        case offline

        var label: String {
            switch self {
            case .online: return "En ligne"
            case .serverUnreachable: return "Serveur injoignable"
            case .offline: return "Hors ligne"
            }
        }
    }

    @Published var user: String?
    @Published var isAdmin = false
    @Published var isInvite = false
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var toast: ToastPayload?
    @Published var isOnline = true
    @Published var networkStatus: NetworkStatus = .online
    @Published var serverVersion: String = ""
    @Published var wizardStep = 1
    @Published var wizardProduct: BeerProduct?

    let api = BeerAPI.shared
    let offline = OfflineQueue()
    let cache = BeerOfflineCache.shared

    var pendingCount: Int { offline.items.count }
    var isOfflineMode: Bool { networkStatus != .online }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "beer.network")
    private var toastTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var syncInProgress = false

    init() {
        api.setBaseURL(ServerSettings.lanApiBase)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
        Task { await bootstrap() }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let pathUp = path.status == .satisfied
        isOnline = pathUp
        if !pathUp {
            networkStatus = .offline
            probeTask?.cancel()
            return
        }
        scheduleServerProbe()
        scheduleSyncDebounced()
    }

    private func scheduleServerProbe() {
        probeTask?.cancel()
        probeTask = Task {
            await probeServerReachability()
        }
    }

    private func scheduleSyncDebounced() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await syncPending()
        }
    }

    private func probeServerReachability() async {
        guard isOnline else {
            networkStatus = .offline
            return
        }
        if await api.discoverWorkingEndpoint() != nil {
            networkStatus = .online
            serverVersion = (try? await api.version()) ?? serverVersion
        } else {
            networkStatus = .serverUnreachable
        }
    }

    func applySession(user: String?, isAdmin: Bool, isInvite: Bool, loggedIn: Bool) {
        self.user = user
        self.isAdmin = isAdmin
        self.isInvite = isInvite
        self.isLoggedIn = loggedIn
        if loggedIn, let user {
            BeerSessionStore.save(user: user, isAdmin: isAdmin, isInvite: isInvite)
            KeychainStore.username = user
            if !isInvite {
                PasskeySessionStore.clear()
            }
        }
    }

    func restoreOfflineSessionIfNeeded() {
        guard let saved = BeerSessionStore.restore() else { return }
        applySession(user: saved.user, isAdmin: saved.isAdmin, isInvite: saved.isInvite, loggedIn: true)
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        restoreOfflineSessionIfNeeded()
        await probeServerReachability()
        guard networkStatus == .online else {
            if isLoggedIn {
                showToast("Mode hors ligne — données en cache", variant: .info, durationMs: 3200)
            }
            return
        }
        do {
            let me = try await fetchMeRefreshingPasskeyIfNeeded()
            if me.auth && me.user == nil {
                await logout()
                return
            }
            applySession(
                user: me.user,
                isAdmin: me.isAdmin,
                isInvite: me.isInvite,
                loggedIn: me.user != nil
            )
            if isLoggedIn { await syncPending() }
        } catch BeerAPIError.forbidden {
            showToast(
                "Invitation invalide ou expirée — demande un nouveau lien à l'admin.",
                variant: .error,
                durationMs: 5200
            )
        } catch {
            if !isLoggedIn, let saved = BeerSessionStore.restore() {
                applySession(user: saved.user, isAdmin: saved.isAdmin, isInvite: saved.isInvite, loggedIn: true)
            }
            if isLoggedIn {
                if networkStatus == .offline {
                    showToast("Hors ligne · \(user ?? "")", variant: .info, durationMs: 4200)
                } else {
                    showToast("Session locale — serveur injoignable", variant: .warn, durationMs: 3600)
                    networkStatus = .serverUnreachable
                }
            }
        }
    }

    func applyServerURL(_ raw: String) {
        _ = raw
        api.setBaseURL(ServerSettings.apiBase)
    }

    func testServer() async -> String {
        api.setBaseURL(ServerSettings.lanApiBase)
        if let ok = await api.discoverWorkingEndpoint() {
            networkStatus = .online
            return "Serveur OK · \(ok)"
        }
        networkStatus = isOnline ? .serverUnreachable : .offline
        return "Échec — vérifie ta connexion Wi‑Fi ou VPN Plexi."
    }

    func login(username: String, password: String) async throws {
        PasskeySessionStore.clear()
        api.setBaseURL(ServerSettings.lanApiBase)
        let loginResp = try await api.login(username: username, password: password)
        let me = try? await api.me()
        applySession(
            user: loginResp.user ?? me?.user ?? username,
            isAdmin: loginResp.isAdmin ?? me?.isAdmin ?? false,
            isInvite: me?.isInvite ?? false,
            loggedIn: true
        )
        networkStatus = .online
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
        showToast("Les invitations invités (5G sans VPN) sont retirées pour le moment. Utilise un compte local en WiFi/VPN.", variant: .error, durationMs: 6000)
        // Guest invite activation disabled as requested. Local accounts only for now.
    }

    private func fetchMeRefreshingPasskeyIfNeeded() async throws -> MeResponse {
        do {
            return try await api.me()
        } catch BeerAPIError.forbidden where shouldRefreshPasskeySession {
            await clearInviteSession()
            throw BeerAPIError.forbidden
        } catch BeerAPIError.unauthorized where shouldRefreshPasskeySession {
            guard let username = KeychainStore.username ?? BeerSessionStore.restore()?.user else {
                throw BeerAPIError.unauthorized
            }
            guard PasskeyAuth.biometricsAvailable else { throw BeerAPIError.unauthorized }
            do {
                let token = try await PasskeyAuth.shared.login(username: username)
                PasskeySessionStore.save(accessToken: token)
                return try await api.me()
            } catch {
                await clearInviteSession()
                throw error
            }
        }
    }

    private func clearInviteSession() async {
        PasskeySessionStore.clear()
        BeerSessionStore.clear()
        user = nil
        isAdmin = false
        isInvite = false
        isLoggedIn = false
        KeychainStore.username = nil
    }

    private var shouldRefreshPasskeySession: Bool {
        PasskeySessionStore.accessToken != nil || BeerSessionStore.restore()?.isInvite == true
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

    static func parseJoinToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let token = parseJoinToken(from: url) {
            return token
        }
        if let range = trimmed.range(of: #"/join/([^/?#\s]+)"#, options: .regularExpression) {
            let chunk = String(trimmed[range])
            if let slash = chunk.range(of: "/join/") {
                let token = String(chunk[slash.upperBound...])
                return token.isEmpty ? nil : token
            }
        }
        if trimmed.count >= 20, !trimmed.contains(" ") {
            return trimmed
        }
        return nil
    }

    func redeemInviteFromClipboard() async {
        let text = UIPasteboard.general.string ?? ""
        guard let token = Self.parseJoinToken(from: text) else {
            showToast("Colle d'abord le lien d'invitation (Messages ou mail).", variant: .error)
            return
        }
        await redeemInviteToken(token)
    }

    func logout() async {
        await api.logout()
        user = nil
        isAdmin = false
        isInvite = false
        isLoggedIn = false
        BeerSessionStore.clear()
        PasskeySessionStore.clear()
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
        guard isLoggedIn, isOnline, !syncInProgress else { return }
        guard !offline.items.isEmpty else { return }
        syncInProgress = true
        defer { syncInProgress = false }
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

        let shouldQueueLocally = networkStatus != .online || !isOnline
        if shouldQueueLocally {
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
            if Self.isNetworkFailure(error) {
                offline.enqueue(pending)
                networkStatus = .serverUnreachable
                return "Enregistré sur l'iPhone — sync au retour réseau"
            }
            throw error
        }
    }

    private static func isNetworkFailure(_ error: Error) -> Bool {
        if let apiErr = error as? BeerAPIError {
            switch apiErr {
            case .network, .allEndpointsFailed: return true
            case .server(let msg):
                return msg.contains("Timeout") || msg.contains("Injoignable") || msg.contains("Pas de réseau")
            default: return false
            }
        }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
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