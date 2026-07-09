import Foundation
import Network
import Security
import UIKit
import LocalAuthentication  // Theme 4: biometric support for sensitive actions
import os  // Priority 6: structured logging
import Darwin  // for getifaddrs, NI_MAXHOST in getCurrentIPAddress

private let logger = Logger(subsystem: "fr.eiter.plexibeer", category: "AppModel")

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
    @Published var isInvite = false  // always false (owner main account only)
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var toast: ToastPayload?
    @Published var isOnline = true
    @Published var networkStatus: NetworkStatus = .online
    @Published var isOnLocalWifi = false  // used to be patient on slow-but-local networks
    @Published var serverVersion: String = ""
    @Published var wizardStep = 1
    @Published var wizardProduct: BeerProduct?

    let api = BeerAPI.shared
    let offline = OfflineQueue()
    let cache = BeerOfflineCache.shared

    var pendingItems: [PendingCheckin] { offline.items }
    var pendingDeletes: [Int] { offline.pendingDeletes }  // Theme 5
    var pendingEdits: [Int] { offline.pendingEdits }  // Priority 6 stub

    func removePending(id: UUID) {
        offline.remove(id: id)
        objectWillChange.send()
    }

    func removePendingDelete(id: Int) {
        offline.removePendingDelete(checkinId: id)
        objectWillChange.send()
    }

    // Haptics for actions
    func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func hapticError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func hapticImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // Theme 4: biometric prompt for critical actions (delete etc)
    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            completion(true) // fallback allow if no biometrics available (dev or setting)
        }
    }

    var pendingCount: Int { offline.items.count + offline.pendingDeletes.count }  // include deletes for badge
    var isOfflineMode: Bool { networkStatus != .online }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "beer.network")
    private var toastTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var syncInProgress = false

    @Published var isOnVPN = false
    @Published var currentLocalIP: String?
    @Published var lastEndpointLatency: TimeInterval? // simple monitoring for latency of last successful health
    private var lastSuccessfulBase: URL? // store last working endpoint for better strategy

    /// Pre-warm the connection on launch / network change to avoid "first connect slow" timeouts
    /// on WiFi/VPN when the native app is used frequently.
    private func prewarmConnection() {
        Task {
            // Fire a quick health check in background (non blocking)
            _ = try? await api.healthCheck()
        }
    }

    private func getCurrentIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name.hasPrefix("utun") || name.hasPrefix("ipsec") { // wifi or vpn
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    init() {
        api.setBaseURL(ServerSettings.lanApiBase)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
        NotificationCenter.default.addObserver(
            forName: .beerAuthExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isLoggedIn {
                    // Ne plus clear automatiquement pour éviter de délogguer sur un appel raté (ex: styles)
                    self.showToast("Session expirée — reconnecte-toi", variant: .error, durationMs: 3500)
                }
            }
        }
        Task { 
            await bootstrap()
            prewarmConnection()
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let pathUp = path.status == .satisfied
        isOnline = pathUp
        if !pathUp {
            networkStatus = .offline
            probeTask?.cancel()
            return
        }
        // Finer detection: local LAN (192.168.1.x) vs VPN (192.168.27.x) vs other
        let ip = getCurrentIPAddress()
        currentLocalIP = ip
        if let ip = ip {
            if ip.hasPrefix("192.168.1.") {
                isOnLocalWifi = true
                isOnVPN = false
                api.setBaseURL(ServerSettings.lanApiBase)
                PlexiIPv4URLProtocol.useCustomTransport = false
            } else if ip.hasPrefix("192.168.27.") {
                isOnLocalWifi = false
                isOnVPN = true
                api.setBaseURL(ServerSettings.apiBase) // domain for VPN
                PlexiIPv4URLProtocol.useCustomTransport = false // use high-level on known VPN too
            } else {
                isOnLocalWifi = false
                isOnVPN = false
                PlexiIPv4URLProtocol.useCustomTransport = true
            }
        } else if path.usesInterfaceType(.wifi) && !path.isExpensive {
            isOnLocalWifi = true
            isOnVPN = false
            api.setBaseURL(ServerSettings.lanApiBase)
            PlexiIPv4URLProtocol.useCustomTransport = false
        } else {
            isOnLocalWifi = false
            isOnVPN = false
            PlexiIPv4URLProtocol.useCustomTransport = true
            if let last = lastSuccessfulBase {
                api.setBaseURL(last)
            }
        }
        scheduleServerProbe()
        scheduleSyncDebounced()
        if isOnLocalWifi || isOnVPN || path.usesInterfaceType(.wifi) {
            prewarmConnection()
        }
    }

    private func scheduleServerProbe() {
        probeTask?.cancel()
        probeTask = Task {
            await probeServerReachability()
        }
    }

    private func scheduleRetryProbe() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            guard !Task.isCancelled else { return }
            if networkStatus == .serverUnreachable {
                await probeServerReachability()
                if networkStatus == .serverUnreachable {
                    // retry again later with backoff
                    try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                    guard !Task.isCancelled else { return }
                    await probeServerReachability()
                }
            }
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
        let start = Date()
        if await api.discoverWorkingEndpoint() != nil {
            let latency = Date().timeIntervalSince(start)
            lastEndpointLatency = latency
            lastSuccessfulBase = api.baseURL
            networkStatus = .online
            serverVersion = (try? await api.version()) ?? serverVersion
            retryTask?.cancel()
        } else {
            networkStatus = .serverUnreachable
            scheduleRetryProbe()
        }
    }

    func applySession(user: String?, isAdmin: Bool, isInvite: Bool, loggedIn: Bool) {
        self.user = user
        self.isAdmin = isAdmin
        self.isInvite = false  // owner main account only
        self.isLoggedIn = loggedIn
        if loggedIn, let user {
            BeerSessionStore.save(user: user, isAdmin: isAdmin, isInvite: false)
            KeychainStore.username = user
            // (no legacy guest tokens)
        }
    }

    func restoreOfflineSessionIfNeeded() {
        guard let saved = BeerSessionStore.restore() else { return }
        applySession(user: saved.user, isAdmin: saved.isAdmin, isInvite: false, loggedIn: true)
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
            let me = try await fetchMe()
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
            cache.prune(maxFiles: 12)  // Theme 5: keep cache small
            await prewarmRecentPhotos()
        } catch BeerAPIError.forbidden {
            await clearSessionState()
            BeerSessionStore.clear()
            KeychainStore.username = nil
            showToast("Accès refusé.", variant: .error, durationMs: 4000)
        } catch BeerAPIError.unauthorized {
            await clearSessionState()
            if networkStatus == .online {
                showToast("Session expirée — reconnecte-toi", variant: .error, durationMs: 4000)
            }
        } catch {
            // Erreurs réseau / injoignable : on peut garder l'état offline depuis la session locale
            if !isLoggedIn, let saved = BeerSessionStore.restore() {
                applySession(user: saved.user, isAdmin: saved.isAdmin, isInvite: false, loggedIn: true)
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
        // Test LAN IP first, then domain as fallback (more diagnostic info)
        let endpoints = [ServerSettings.lanApiBase, ServerSettings.apiBase]
        var results: [String] = []
        for ep in endpoints {
            api.setBaseURL(ep)
            let ok = await api.discoverWorkingEndpoint()
            if ok != nil {
                networkStatus = .online
                return "Serveur OK via \(ep.host ?? "?"):\(ep.port ?? 0)"
            } else {
                results.append("\(ep.host ?? "?"): unreachable")
            }
        }
        networkStatus = isOnline ? .serverUnreachable : .offline
        return "Échec. Tests: \(results.joined(separator: " | ")) — Vérifie Wi-Fi/VPN + autorisation Réseau local."
    }

    func login(username: String, password: String) async throws {
        // Owner main account.
        BeerSessionStore.clear()
        api.setBaseURL(ServerSettings.lanApiBase)
        let loginResp = try await api.login(username: username, password: password)
        let me = try? await api.me()
        applySession(
            user: loginResp.user ?? me?.user ?? username,
            isAdmin: loginResp.isAdmin ?? me?.isAdmin ?? false,
            isInvite: false,
            loggedIn: true
        )
        networkStatus = .online
        hideToast()
        await syncPending()
    }

    func handleOpenURL(_ url: URL) async {
        // (no legacy guest tokens)
    }

    private func fetchMe() async throws -> MeResponse {
        // Main account only.
        return try await api.me()
    }

    private func clearSessionState() async {
        user = nil
        isAdmin = false
        isInvite = false
        isLoggedIn = false
    }

    private var shouldRefreshPasskeySession: Bool { false }

    func logout() async {
        await api.logout()
        await clearSessionState()
        // Logout explicite : on oublie aussi l'identité locale (plus de restore offline ni refresh auto)
        BeerSessionStore.clear()
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

    func prewarmPhotos(_ items: [CheckinItem]) {
        for item in items.prefix(25) {
            if let p = item.photoURL {
                BeerImageLoader.prewarm(path: p, api: self.api)
            }
        }
    }

    // Theme 5: pre-download photos of last N at bootstrap for snappy gallery offline
    private func prewarmRecentPhotos() async {
        guard networkStatus == .online, isLoggedIn else { return }
        do {
            let recent = try await api.checkins(limit: 8, offset: 0)
            prewarmPhotos(recent)
        } catch {
            // ignore, best effort
        }
    }

    func syncPending() async {
        guard isLoggedIn, isOnline, !syncInProgress else { return }
        let hasWork = !offline.items.isEmpty || !offline.pendingDeletes.isEmpty
        guard hasWork else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        let n = await offline.flush(using: api)
        if n > 0 {
            showToast("\(n) action(s) synchronisée(s)", variant: .success)
            hapticSuccess()
            objectWillChange.send()
            logger.info("Synced \(n) pending actions")
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
                hapticSuccess()
                return "Enregistré ✓"
            }
            throw BeerAPIError.server(result.error ?? "Échec")
        } catch {
            if Self.isNetworkFailure(error) {
                offline.enqueue(pending)
                networkStatus = .serverUnreachable
                hapticImpact()
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

    // Theme 4: hardened - username also AfterFirstUnlockThisDeviceOnly (consistent).
    // (passkey comment removed)
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
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}