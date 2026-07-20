import Foundation
import Network
import Security
import UIKit
import AudioToolbox
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
    @Published var isInvite = false
    @Published var inviteLabel: String?
    /// Lien d'invitation reçu via deep link / Universal Link.
    @Published var pendingInviteLink: String?
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var toast: ToastPayload?
    @Published var isOnline = true
    @Published var networkStatus: NetworkStatus = .online
    @Published var isOnLocalWifi = false  // used to be patient on slow-but-local networks
    @Published var serverVersion: String = ""
    @Published var wizardStep = 1
    @Published var wizardProduct: BeerProduct?
    @Published var rpgState: RpgState?
    @Published var lastRpgLoot: RpgLoot?
    /// Résumé butin post-check-in (sheet joueur).
    @Published var lootSummary: RpgLoot?
    /// Célébration en cours (level-up / badge) — une à la fois.
    @Published var rpgCelebration: RpgCelebration?
    /// Intro Beerquest 1ʳᵉ visite.
    @Published var showRpgIntro = false
    /// Demande d’ouvrir le grimoire (depuis célébration badge).
    @Published var requestOpenGrimoire = false
    /// Dernière version iOS publiée (portail versions.json).
    @Published var latestIosVersion: String?
    @Published var latestAndroidVersion: String?
    @Published var versionsUpdatedAt: String?

    var rpgActive: Bool { rpgState?.active == true }

    /// Version marketing de l’IPA installée (ex. 4.4.8).
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
    /// True si une version iOS plus récente est publiée sur le portail.
    var needsAppUpdate: Bool {
        guard let latest = latestIosVersion, !latest.isEmpty, appVersion != "?" else { return false }
        return beerVersionCompare(appVersion, latest) < 0
    }
    var portalURL: URL {
        URL(string: ServerSettings.portalURLString) ?? URL(string: "https://eiter.freeboxos.fr/mobile/beer/")!
    }

    private var celebQueue: [RpgCelebration] = []
    private var celebBusy = false
    private var celebPumpTask: Task<Void, Never>?

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
        // Keychain iOS survit à la désinstall → purger si 1er lancement de cette install
        FreshInstallGuard.runIfNeeded()

        // Owner par défaut = LAN (comme Android). Invite bascule ensuite sur WAN.
        api.setBaseURL(ServerSettings.lanApiBase)
        ServerSettings.inviteMode = false
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
                if self.isLoggedIn && !self.isInvite {
                    self.showToast("Session expirée — reconnecte-toi", variant: .error, durationMs: 3500)
                }
            }
        }
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
        let ip = getCurrentIPAddress()
        currentLocalIP = ip

        if isInvite || InviteSessionStore.hasInviteSession {
            // Invité : WAN only (ne touche pas au LAN)
            api.enableInviteMode(true)
            isOnLocalWifi = false
            isOnVPN = false
        } else {
            // Owner : comme Android
            api.enableInviteMode(false)
            if let ip = ip, ip.hasPrefix("192.168.1.") {
                isOnLocalWifi = true
                isOnVPN = false
                api.setBaseURL(ServerSettings.lanApiBase)
            } else if let ip = ip, ip.hasPrefix("192.168.27.") {
                isOnLocalWifi = false
                isOnVPN = true
                api.setBaseURL(ServerSettings.apiBase)
            } else if path.usesInterfaceType(.wifi) && !path.isExpensive {
                isOnLocalWifi = true
                isOnVPN = false
                api.setBaseURL(ServerSettings.lanApiBase)
            } else {
                // 5G / réseau non-LAN : pas de probe 192.168.1.50
                isOnLocalWifi = false
                isOnVPN = false
                ServerSettings.preferWanOnly = true
                api.setBaseURL(ServerSettings.apiBase)
            }
            if isOnLocalWifi || isOnVPN {
                ServerSettings.preferWanOnly = false
            }
        }
        // Invité : pas de probe auto (sinon Bienvenue → « injoignable » en 2 s).
        // Owner : probe fond OK.
        if isLoggedIn && !isInvite && !InviteSessionStore.hasInviteSession {
            scheduleServerProbe()
        }
        scheduleSyncDebounced()
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
        // INVITÉ : ne JAMAIS basculer en « serveur injoignable » via probe fond.
        // C’est ça qui faisait : Bienvenue → 2 s → cache → « déconnexion ».
        // On ne repasse offline que si /api/me renvoie 401 (révoqué) au bootstrap
        // ou si l’utilisateur n’a plus de Bearer.
        if isInvite || InviteSessionStore.hasInviteSession {
            api.enableInviteMode(true)
            if await api.nativeSessionOK() {
                networkStatus = .online
                lastSuccessfulBase = api.baseURL
            }
            // échec probe : on laisse networkStatus tel quel (souvent .online après join)
            return
        }
        if await api.discoverWorkingEndpoint() != nil {
            networkStatus = .online
            lastSuccessfulBase = api.baseURL
        } else if isLoggedIn {
            networkStatus = .serverUnreachable
        }
    }


    func applySession(user: String?, isAdmin: Bool, isInvite: Bool, loggedIn: Bool, inviteLabel: String? = nil) {
        self.user = user
        self.isAdmin = isAdmin && !isInvite
        self.isInvite = isInvite
        self.inviteLabel = inviteLabel ?? InviteSessionStore.label
        self.isLoggedIn = loggedIn
        if loggedIn, let user {
            BeerSessionStore.save(user: user, isAdmin: isAdmin && !isInvite, isInvite: isInvite)
            KeychainStore.username = user
            if isInvite {
                api.enableInviteMode(true)
            }
            Task { await refreshRpg() }
        } else {
            clearRpgUiState()
        }
    }

    func restoreOfflineSessionIfNeeded() {
        guard let saved = BeerSessionStore.restore() else { return }
        if saved.isInvite {
            api.enableInviteMode(true)
        }
        applySession(
            user: saved.user,
            isAdmin: saved.isAdmin,
            isInvite: saved.isInvite,
            loggedIn: true,
            inviteLabel: InviteSessionStore.label
        )
    }

    /// Bootstrap = Android AppViewModel.bootstrap()
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        guard isOnline else {
            networkStatus = .offline
            restoreOfflineSessionIfNeeded()
            if isLoggedIn {
                showToast("Mode hors ligne", variant: .info, detail: "Cache local", durationMs: 3500)
            }
            return
        }

        // Pas de session → écran login immédiat (pas de toast "injoignable" ni attente LAN)
        let hasInvite = InviteSessionStore.hasInviteSession
        let hasCookie = HTTPCookieStorage.shared.cookies?.contains(where: { $0.name == "beer_session" }) == true
        if !hasInvite && !hasCookie && BeerSessionStore.restore() == nil {
            api.enableInviteMode(false)
            networkStatus = .online
            isLoading = false
            // probe en fond, n'affiche rien si hors ligne
            Task { _ = await api.discoverWorkingEndpoint() }
            return
        }

        // Invité : Bearer d'abord — ne jamais retomber en mode owner (LAN) si le token existe.
        // Retry 3× comme un vrai client stable (pas « 1 blip 5G = déconnecté »).
        if InviteSessionStore.hasInviteSession {
            api.enableInviteMode(true)
            let t0 = Date()
            var lastErr: Error?
            for attempt in 1...3 {
                do {
                    let me = try await api.me()
                    lastEndpointLatency = Date().timeIntervalSince(t0)
                    if let u = me.user, !u.isEmpty {
                        networkStatus = .online
                        lastSuccessfulBase = api.baseURL
                        applySession(user: u, isAdmin: false, isInvite: true, loggedIn: true, inviteLabel: InviteSessionStore.label)
                        serverVersion = (try? await api.version()) ?? ""
                        await syncPending()
                        Task { await prewarmRecentPhotos() }
                        cache.prune(maxFiles: 16)
                        return
                    }
                    // user vide = révoqué / invalide (même si pas 401)
                    api.clearSession()
                    BeerSessionStore.clear()
                    await clearSessionState()
                    return
                } catch {
                    lastErr = error
                    if case BeerAPIError.unauthorized = error {
                        api.clearSession()
                        BeerSessionStore.clear()
                        await clearSessionState()
                        showToast("Invitation révoquée ou expirée", variant: .error, durationMs: 4000)
                        return
                    }
                    // 403 métier invite morte
                    if case BeerAPIError.server(let msg) = error,
                       msg.localizedCaseInsensitiveContains("Invitation invalide")
                        || msg.localizedCaseInsensitiveContains("expir") {
                        api.clearSession()
                        BeerSessionStore.clear()
                        await clearSessionState()
                        showToast("Invitation invalide ou expirée", variant: .error, durationMs: 4000)
                        return
                    }
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
                    }
                }
            }
            lastEndpointLatency = Date().timeIntervalSince(t0)
            // Réseau temporaire : garde le Bearer + session UI (pas de wipe)
            networkStatus = .serverUnreachable
            restoreOfflineSessionIfNeeded()
            if isLoggedIn || InviteSessionStore.hasInviteSession {
                let detail = (lastErr as? LocalizedError)?.errorDescription ?? "Réessaie dans un instant"
                showToast("Serveur injoignable", variant: .warn, detail: detail, durationMs: 3500)
            }
            return
        }

        // Owner only à partir d'ici
        api.enableInviteMode(false)
        let t0 = Date()
        let ep = await api.discoverWorkingEndpoint()
        lastEndpointLatency = Date().timeIntervalSince(t0)
        if ep == nil {
            networkStatus = .serverUnreachable
            restoreOfflineSessionIfNeeded()
            if isLoggedIn {
                showToast("Serveur injoignable", variant: .warn, detail: "Cache local", durationMs: 3500)
            }
            return
        }
        networkStatus = .online
        lastSuccessfulBase = api.baseURL

        if HTTPCookieStorage.shared.cookies?.contains(where: { $0.name == "beer_session" }) == true {
            api.enableInviteMode(false)
            do {
                let me = try await api.me()
                if let u = me.user, !u.isEmpty {
                    applySession(
                        user: u,
                        isAdmin: me.isAdmin ?? false,
                        isInvite: me.isInvite ?? false,
                        loggedIn: true
                    )
                    serverVersion = (try? await api.version()) ?? ""
                    await syncPending()
                    await prewarmRecentPhotos()
                    cache.prune(maxFiles: 16)
                    return
                }
                api.clearSession()
                BeerSessionStore.clear()
            } catch {
                if case BeerAPIError.unauthorized = error {
                    api.clearSession()
                    BeerSessionStore.clear()
                } else {
                    networkStatus = .serverUnreachable
                    restoreOfflineSessionIfNeeded()
                    return
                }
            }
        }
        restoreOfflineSessionIfNeeded()
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
        BeerSessionStore.clear()
        InviteSessionStore.clear()
        api.enableInviteMode(false)
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

    func joinInvite(inviteLink: String, email: String) async throws {
        let resp = try await api.joinInvite(inviteLink: inviteLink, email: email)
        pendingInviteLink = nil
        api.enableInviteMode(true)
        applySession(
            user: resp.user ?? "invite",
            isAdmin: false,
            isInvite: true,
            loggedIn: true,
            inviteLabel: resp.label
        )
        networkStatus = .online
        lastSuccessfulBase = api.baseURL
        hideToast()
        // Petit délai pour laisser l’UI basculer Login → Main (évite toast collé à la transition)
        try? await Task.sleep(nanoseconds: 350_000_000)
        let name = (resp.label ?? resp.user ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hello = name.isEmpty ? "Bienvenue !" : "Bienvenue, \(name) !"
        showToast(
            hello,
            variant: .success,
            detail: "Compte invité prêt — 4G/5G OK",
            label: "Invitation",
            durationMs: 3200
        )
        // Ne pas lancer un probe health agressif juste après join
        probeTask?.cancel()
        await syncPending()
        serverVersion = (try? await api.version()) ?? serverVersion
        // styles / historique se chargent à la demande — pas de prewarm bloquant
    }

    func handleOpenURL(_ url: URL) async {
        let s = url.absoluteString
        if s.contains("/beer/join") || s.contains("/beer-alpha/join") || url.scheme == "plexibeer" {
            pendingInviteLink = s
            // Auto-activate if already on login and not logged in
            if !isLoggedIn {
                // LoginView will pick up pendingInviteLink
            }
        }
    }

    private func fetchMe() async throws -> MeResponse {
        return try await api.me()
    }

    private func clearSessionState() async {
        user = nil
        isAdmin = false
        isInvite = false
        inviteLabel = nil
        isLoggedIn = false
    }

    private var shouldRefreshPasskeySession: Bool { false }

    /// Déconnexion effective (après confirmation UI Annuler / Se déconnecter).
    func logout() async {
        let wasInvite = isInvite || InviteSessionStore.hasInviteSession
        hideToast()
        // Owner : logout serveur ; invité : clear Bearer local seulement
        if !wasInvite {
            await api.logout()
        } else {
            api.clearSession()
        }
        await clearSessionState()
        BeerSessionStore.clear()
        InviteSessionStore.clear()
        KeychainStore.username = nil
        networkStatus = .online
    }

    /// Feedback joueur (parité PWA).
    @discardableResult
    func sendFeedback(message: String, category: String) async -> Bool {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? serverVersion
        let (ok, err) = await api.sendFeedback(message: message, category: category, appVersion: ver)
        if ok {
            showToast("Merci ! Feedback envoyé.", variant: .success, label: "Feedback")
        } else {
            showToast(err ?? "Envoi impossible", variant: .error, label: "Feedback")
        }
        return ok
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
        force: Bool,
        location: String = ""
    ) async throws -> String {
        let loc = String(location.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
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
            photoJPEGBase64: photoJPEG?.base64EncodedString(),
            location: loc.isEmpty ? nil : loc
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
                photoJPEG: photoJPEG,
                location: pending.location ?? ""
            )
            if result.duplicate == true {
                let pc = result.previousCheckin
                return "duplicate|\(pc?.beerName ?? product.beerName)|\(pc?.rating ?? 0)|\(pc?.createdAt ?? "")"
            }
            if result.ok == true || result.id != nil {
                hapticSuccess()
                handleRpgLoot(result.rpg)
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

    func refreshRpg() async {
        guard isLoggedIn, networkStatus == .online else { return }
        do {
            let st = try await api.rpgMe()
            rpgState = st
            maybeShowRpgIntro(st)
        } catch {
            // keep previous
        }
    }

    private func maybeShowRpgIntro(_ st: RpgState) {
        guard st.active, let p = st.profile else {
            showRpgIntro = false
            return
        }
        // nil / false → afficher l’intro une fois
        if p.introSeen != true {
            showRpgIntro = true
        }
    }

    func dismissRpgIntro(openGrimoire: Bool = false) {
        showRpgIntro = false
        // Optimistic
        if var st = rpgState, var p = st.profile {
            p.introSeen = true
            st.profile = p
            rpgState = st
        }
        Task {
            _ = try? await api.rpgIntroSeen()
            await refreshRpg()
        }
        if openGrimoire {
            requestOpenGrimoire = true
        }
    }

    func handleRpgLoot(_ loot: RpgLoot?) {
        guard let loot else { return }
        lastRpgLoot = loot
        if var st = rpgState, var p = st.profile {
            p.level = loot.level ?? p.level
            p.xp = loot.xp ?? p.xp
            p.title = loot.title ?? p.title
            p.progressPct = loot.progressPct ?? p.progressPct
            p.xpToNext = loot.xpToNext ?? p.xpToNext
            if let s = loot.streakDays { p.streakDays = s }
            st.profile = p
            rpgState = st
        }

        let hasMeaningful =
            loot.levelUp == true
            || (loot.xpGained ?? 0) != 0
            || !(loot.badgesEarned ?? []).isEmpty
            || !(loot.questsCompleted ?? []).isEmpty

        // Haptique + son systeme léger (pas de fichier audio custom)
        if loot.levelUp == true {
            hapticSuccess()
            // "SMS received" style — plus marqué pour level-up
            AudioServicesPlaySystemSound(1025)
        } else if hasMeaningful {
            hapticImpact(style: .medium)
            AudioServicesPlaySystemSound(1057)
        }

        // Résumé butin (sheet) si XP / level / badge / quête
        if hasMeaningful {
            lootSummary = loot
        }

        var bits: [String] = []
        if loot.levelUp == true { bits.append("LEVEL UP → \(loot.level ?? 0)") }
        if let g = loot.xpGained, g != 0 { bits.append("+\(g) XP") }
        if let b = loot.badgesEarned?.first {
            bits.append("\(b.icon ?? "🏅") \(b.name ?? "Badge")")
        }
        if let q = loot.questsCompleted?.first {
            bits.append("📜 \(q.title ?? "Quête")")
        }
        let hasCeleb = loot.levelUp == true || !(loot.badgesEarned ?? []).isEmpty
        let msg: String
        if loot.levelUp == true {
            msg = loot.phraseLevelUp ?? loot.phrase ?? "Niveau \(loot.level ?? 0) !"
        } else if (loot.xpGained ?? 0) > 0 {
            msg = loot.phrase ?? "Butin +\(loot.xpGained ?? 0) XP"
        } else {
            msg = loot.phrase ?? "Noté"
        }
        // Toast court — le détail est dans le résumé butin
        showToast(
            msg,
            variant: hasCeleb ? .success : .info,
            detail: bits.isEmpty ? nil : bits.joined(separator: " · "),
            label: "Beerquest",
            durationMs: hasCeleb ? 2000 : 3200
        )
        enqueueCelebrations(from: loot)
        Task { await refreshRpg() }
    }

    func dismissLootSummary() {
        lootSummary = nil
    }

    /// Charge versions.json du portail (non bloquant).
    func refreshMobileVersions() async {
        guard let m = await api.fetchMobileVersions() else { return }
        latestIosVersion = m.ios
        latestAndroidVersion = m.android
        versionsUpdatedAt = m.updatedAt
        // Si le manifest a une webapp et qu'on n'a pas encore serverVersion
        if serverVersion.isEmpty, let w = m.webapp, !w.isEmpty {
            serverVersion = w
        }
    }

    private func enqueueCelebrations(from loot: RpgLoot) {
        if loot.levelUp == true {
            celebQueue.append(.levelUp(loot))
        }
        for b in loot.badgesEarned ?? [] {
            celebQueue.append(.badge(b))
        }
        guard !celebQueue.isEmpty else { return }
        // Laisse le toast s’installer (~1.3 s) comme la webapp
        celebPumpTask?.cancel()
        celebPumpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            pumpCelebrationQueue()
        }
    }

    private func pumpCelebrationQueue() {
        guard !celebBusy else { return }
        guard let next = celebQueue.first else { return }
        celebQueue.removeFirst()
        celebBusy = true
        hapticSuccess()
        rpgCelebration = next
    }

    func dismissRpgCelebration(openGrimoire: Bool = false) {
        rpgCelebration = nil
        celebBusy = false
        if openGrimoire {
            requestOpenGrimoire = true
        }
        // Enchaîne la suivante
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            pumpCelebrationQueue()
        }
    }

    func equipRpgClass(_ key: String) async {
        do {
            let ok = try await api.rpgSetClass(key)
            if ok {
                await refreshRpg()
                showToast("Classe équipée", variant: .success, label: "Beerquest")
            } else {
                showToast("Impossible d’équiper", variant: .error, label: "Beerquest")
            }
        } catch {
            showToast("Impossible d’équiper", variant: .error, label: "Beerquest")
        }
    }

    func clearRpgUiState() {
        rpgState = nil
        lastRpgLoot = nil
        lootSummary = nil
        rpgCelebration = nil
        showRpgIntro = false
        celebQueue.removeAll()
        celebBusy = false
        celebPumpTask?.cancel()
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