import Foundation

enum BeerAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case server(String)
    case network(Error)
    case decode
    case allEndpointsFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL API invalide"
        case .unauthorized: return "Session expirée — reconnecte-toi"
        case .forbidden: return "Accès refusé (connecte-toi en WiFi ou via le VPN)"
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        case .decode: return "Réponse serveur illisible"
        case .allEndpointsFailed(let detail): return detail
        }
    }
}

extension Notification.Name {
    static let beerAuthExpired = Notification.Name("beerAuthExpired")
}

final class BeerAPI {
    static let shared = BeerAPI()
    private static let nativeClientHeader = "X-PlexiBeer-Client"
    private static let nativeClientValue = "native-ios"
    private static let nativeUserAgentOwner = "PlexiBeer/3.4.0 (iPhone; native owner) [lan-vpn]"
    private static let nativeUserAgentInvite = "PlexiBeer/3.4.0 (iPhone; native invite) [wan]"

    private let session: URLSession
    private let lanProbeSession: URLSession
    private(set) var baseURL: URL
    private(set) var activeEndpoint: String = ""

    var isInviteMode: Bool {
        ServerSettings.inviteMode || InviteSessionStore.hasInviteSession
    }

    init(baseURL: URL = ServerSettings.lanApiBase) {
        self.baseURL = Self.canonicalBase(baseURL)
        let sharedCookies = HTTPCookieStorage.shared
        func baseConfig(requestTimeout: TimeInterval = 30, resourceTimeout: TimeInterval = 120, shouldSetCookies: Bool = true) -> URLSessionConfiguration {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = sharedCookies
            config.httpShouldSetCookies = shouldSetCookies
            config.httpCookieAcceptPolicy = .always
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = resourceTimeout
            return config
        }
        // Owner session (LAN or VPN): custom IPv4 + TLS for LAN IP cert bypass.
        let ownerConfig = baseConfig(shouldSetCookies: false)
        ownerConfig.protocolClasses = [PlexiIPv4URLProtocol.self]
        self.session = URLSession(
            configuration: ownerConfig,
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
        let lanConfig = baseConfig(
            requestTimeout: ServerSettings.lanProbeTimeoutSec,
            resourceTimeout: ServerSettings.lanProbeTimeoutSec + 4,
            shouldSetCookies: false
        )
        self.lanProbeSession = URLSession(
            configuration: lanConfig,
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
    }

    private func session(for endpoint: URL, probe: Bool = false) -> URLSession {
        // Owner main account (LAN or VPN).
        if probe && ServerSettings.isLanEndpoint(endpoint) { return lanProbeSession }
        return session
    }

    func setBaseURL(_ url: URL) {
        baseURL = Self.canonicalBase(url)
        activeEndpoint = baseURL.absoluteString
    }

    func enableInviteMode(_ enabled: Bool) {
        ServerSettings.inviteMode = enabled
        if enabled {
            setBaseURL(ServerSettings.apiBase)
        }
    }

    func clearAllAuth() {
        InviteSessionStore.clear()
        ServerSettings.inviteMode = false
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        setBaseURL(ServerSettings.lanApiBase)
    }

    func healthCheck() async throws -> Bool {
        let (_, http, _) = try await request(path: "/api/health", method: "GET", body: nil)
        return http.statusCode == 200
    }

    func discoverWorkingEndpoint() async -> String? {
        let originalBase = baseURL
        let candidates = ServerSettings.candidateURLs
        // Invite: WAN only (FQDN then IPv4)
        if isInviteMode {
            for candidate in candidates {
                do {
                    guard let healthURL = URL(string: "api/health", relativeTo: candidate) else { continue }
                    var healthProbe = URLRequest(url: healthURL)
                    healthProbe.httpMethod = "GET"
                    let (_, http, _) = try await performOnEndpoint(candidate, request: healthProbe, probe: false)
                    // health peut être public ou 403 gate — on teste join plutôt pour invite
                    if http.statusCode == 200 || http.statusCode == 403 {
                        baseURL = Self.canonicalBase(candidate)
                        activeEndpoint = candidate.absoluteString
                        if http.statusCode == 200 { return candidate.absoluteString }
                        // 403 health = endpoint joignable ; tenter quand même
                        return candidate.absoluteString
                    }
                } catch {
                    continue
                }
            }
            baseURL = originalBase
            return nil
        }
        // Owner: prefer LAN IP first
        if let lan = candidates.first(where: { ServerSettings.isLanEndpoint($0) }) {
            do {
                guard let healthURL = URL(string: "api/health", relativeTo: lan) else { throw BeerAPIError.invalidURL }
                var healthProbe = URLRequest(url: healthURL)
                healthProbe.httpMethod = "GET"
                let (_, http, _) = try await performOnEndpoint(
                    lan,
                    request: healthProbe,
                    probe: false
                )
                if http.statusCode == 200 {
                    baseURL = Self.canonicalBase(lan)
                    activeEndpoint = lan.absoluteString
                    return lan.absoluteString
                }
            } catch {
                if !ServerSettings.isLikelyOnLocalWifi() {
                    // fall to domain
                }
            }
        }
        for candidate in candidates where !ServerSettings.isLanEndpoint(candidate) {
            do {
                guard let healthURL = URL(string: "api/health", relativeTo: candidate) else { throw BeerAPIError.invalidURL }
                var healthProbe = URLRequest(url: healthURL)
                healthProbe.httpMethod = "GET"
                let (_, http, _) = try await performOnEndpoint(
                    candidate,
                    request: healthProbe,
                    probe: false
                )
                if http.statusCode == 200 {
                    baseURL = Self.canonicalBase(candidate)
                    activeEndpoint = candidate.absoluteString
                    return candidate.absoluteString
                }
            } catch {
                continue
            }
        }
        baseURL = originalBase
        return nil
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        enableInviteMode(false)
        InviteSessionStore.clear()
        setBaseURL(ServerSettings.lanApiBase)
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let (data, http, responseURL) = try await request(
            path: "/api/login",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode == 403 {
            throw BeerAPIError.server("Accès refusé — Wi‑Fi maison ou VPN Plexi requis pour les comptes principaux")
        }
        guard let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
            let hint = http.statusCode == 404
                ? " — vérifie que l'URL se termine par /beer/ (ex. https://192.168.1.50:8444/beer/)"
                : ""
            throw BeerAPIError.server("Réponse login invalide (HTTP \(http.statusCode))\(hint)")
        }
        if http.statusCode == 401 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Identifiants incorrects")
        }
        let setCookieHeader = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        if !setCookieHeader.isEmpty {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookieHeader], for: responseURL)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        return decoded
    }

    /// Activation invité WAN — POST /api/native/join → Bearer.
    func joinInvite(inviteLink: String) async throws -> NativeJoinResponse {
        guard let token = InviteSessionStore.parseInviteToken(inviteLink) else {
            throw BeerAPIError.server("Lien d'invitation invalide")
        }
        let deviceId = InviteSessionStore.deviceId
        // Pas de cookies owner pendant l'activation
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        BeerSessionStore.clear()

        var lastError: Error?
        for candidate in ServerSettings.inviteCandidateURLs {
            do {
                setBaseURL(candidate)
                enableInviteMode(true)
                let body = try JSONEncoder().encode([
                    "token": token,
                    "device_id": deviceId,
                ])
                var req = URLRequest(url: try url("/api/native/join"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
                req.setValue(Self.nativeUserAgentInvite, forHTTPHeaderField: "User-Agent")
                req.setValue(deviceId, forHTTPHeaderField: "X-Beer-Device")
                req.httpBody = body
                let (data, http, _) = try await performOnEndpoint(candidate, request: req, probe: false)
                guard let decoded = try? JSONDecoder().decode(NativeJoinResponse.self, from: data) else {
                    throw BeerAPIError.server("Réponse join invalide (HTTP \(http.statusCode))")
                }
                if http.statusCode == 429 {
                    throw BeerAPIError.server("Trop de tentatives — réessaie dans une minute")
                }
                if http.statusCode == 403, decoded.error == "wrong_device" {
                    throw BeerAPIError.server("Cette invitation est déjà liée à un autre téléphone")
                }
                if http.statusCode >= 400 || !decoded.ok || (decoded.accessToken ?? "").isEmpty {
                    let msg: String
                    switch decoded.error {
                    case "invalid": msg = "Invitation invalide ou expirée"
                    case "invalid_device": msg = "Identifiant appareil invalide"
                    case "disabled": msg = "Invitations natives désactivées"
                    default: msg = decoded.error ?? "Activation impossible (HTTP \(http.statusCode))"
                    }
                    throw BeerAPIError.server(msg)
                }
                let bound = decoded.deviceId ?? deviceId
                InviteSessionStore.save(
                    accessToken: decoded.accessToken!,
                    user: decoded.user ?? "invite",
                    label: decoded.label,
                    expiresAt: decoded.expiresAt,
                    deviceId: bound
                )
                enableInviteMode(true)
                activeEndpoint = candidate.absoluteString
                return decoded
            } catch let e as BeerAPIError {
                // Erreurs métier (lien invalide, wrong_device…) : stop
                if case .server(let msg) = e {
                    let lower = msg.lowercased()
                    if lower.contains("invitation") || lower.contains("appareil")
                        || lower.contains("tentatives") || lower.contains("invalide")
                        || lower.contains("désactiv") || lower.contains("liée") {
                        throw e
                    }
                }
                lastError = e
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BeerAPIError.server("Serveur injoignable en 4G/5G — réessaie")
    }

    func me() async throws -> MeResponse {
        let (data, http, _) = try await request(path: "/api/me", method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode == 403 {
            if isInviteMode {
                InviteSessionStore.clear()
                throw BeerAPIError.server("Invitation invalide ou expirée — demande un nouveau lien")
            }
            throw BeerAPIError.forbidden
        }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func logout() async {
        if !isInviteMode {
            _ = try? await request(path: "/api/logout", method: "POST", body: nil)
        }
        clearAllAuth()
    }

    func lookup(barcode: String) async throws -> LookupResponse {
        let body = try JSONEncoder().encode(["barcode": barcode])
        let (data, http, _) = try await request(
            path: "/api/lookup",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func checkins(
        q: String = "",
        style: String = "",
        minRating: Double = 0,
        period: String = "",
        limit: Int = 10,
        offset: Int = 0
    ) async throws -> [CheckinItem] {
        var components = URLComponents(url: try url("/api/checkins"), resolvingAgainstBaseURL: true)!
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if !style.isEmpty { items.append(URLQueryItem(name: "style", value: style)) }
        if minRating > 0 { items.append(URLQueryItem(name: "min_rating", value: String(minRating))) }
        if !period.isEmpty { items.append(URLQueryItem(name: "period", value: period)) }
        components.queryItems = items
        var req = URLRequest(url: components.url!)
        let (data, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode([CheckinItem].self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func stats() async throws -> HistoryStats {
        let (data, http, _) = try await request(path: "/api/stats", method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(HistoryStats.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func coupleStats() async throws -> CoupleStats {
        let (data, http, _) = try await request(path: "/api/stats/couple", method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(CoupleStats.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func styles() async throws -> [StyleOption] {
        let (data, http, _) = try await request(path: "/api/styles", method: "GET", body: nil)
        // pas de throw unauthorized ici pour éviter clear/toast sur appel non critique
        if http.statusCode == 401 { return [] }
        return (try? JSONDecoder().decode([StyleOption].self, from: data)) ?? []
    }

    func version() async throws -> String {
        let (data, _, _) = try await request(path: "/api/version", method: "GET", body: nil)
        struct V: Decodable { let version: String? }
        return (try? JSONDecoder().decode(V.self, from: data))?.version ?? "?"
    }

    func patchnotes() async throws -> PatchnotesResponse {
        let (data, http, _) = try await request(path: "/api/admin/patchnotes", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        guard let decoded = try? JSONDecoder().decode(PatchnotesResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func wishlist() async throws -> [WishlistItem] {
        let (data, http, _) = try await request(path: "/api/wishlist", method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        return (try? JSONDecoder().decode([WishlistItem].self, from: data)) ?? []
    }

    func addWishlist(beerName: String, brewery: String, style: String = "Unknown", barcode: String = "") async throws {
        let payload: [String: Any] = [
            "beer_name": beerName,
            "brewery": brewery,
            "style": style,
            "barcode": barcode,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(path: "/api/wishlist", method: "POST", body: body, contentType: "application/json")
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Échec wishlist")
        }
    }

    func deleteWishlist(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/wishlist/\(id)", method: "DELETE", body: nil)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func deleteCheckin(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/checkins/\(id)", method: "DELETE", body: nil)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func updateCheckin(
        id: Int,
        rating: Double?,
        flavors: [String]?,
        hops: [String]?,
        comment: String?,
        hiddenFromPartner: Bool?,
        location: String? = nil
    ) async throws {
        var payload: [String: Any] = [:]
        if let rating { payload["rating"] = rating }
        if let flavors { payload["flavors"] = flavors }
        if let hops { payload["hops"] = hops }
        if let comment { payload["comment"] = comment }
        if let location { payload["location"] = location }
        if let hiddenFromPartner { payload["hidden_from_partner"] = hiddenFromPartner }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(
            path: "/api/checkins/\(id)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Modification impossible")
        }
    }

    func replaceCheckinPhoto(id: Int, jpeg: Data) async throws {
        let boundary = "BeerPhoto-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/checkins/\(id)/photo"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = makeMultipart(
            boundary: boundary,
            fields: [:],
            file: ("photo", "photo.jpg", "image/jpeg", jpeg)
        )
        let (_, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        if http.statusCode >= 400 { throw BeerAPIError.server("Photo impossible") }
    }

    func removeCheckinPhoto(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/checkins/\(id)/photo", method: "DELETE", body: nil)
        try throwIfUnauthorized(http.statusCode)
    }

    func adminUsers() async throws -> [AdminUser] {
        let (data, http, _) = try await request(path: "/api/admin/users", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        return (try? JSONDecoder().decode([AdminUser].self, from: data)) ?? []
    }

    func adminCreateUser(username: String, password: String, isAdmin: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "is_admin": isAdmin,
        ] as [String: Any])
        let (data, http, _) = try await request(path: "/api/admin/users", method: "POST", body: body, contentType: "application/json")
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Création impossible")
        }
    }

    func adminDeleteUser(_ username: String) async throws {
        let (data, http, _) = try await request(path: "/api/admin/users/\(username)", method: "DELETE", body: nil)
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Suppression impossible")
        }
    }

    func adminSetAdmin(_ username: String, isAdmin: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["is_admin": isAdmin])
        let (_, http, _) = try await request(
            path: "/api/admin/users/\(username)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 400 { throw BeerAPIError.server("Mise à jour impossible") }
    }

    func adminInvites() async throws -> [InviteItem] {
        let (data, http, _) = try await request(path: "/api/invites", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        return (try? JSONDecoder().decode([InviteItem].self, from: data)) ?? []
    }

    func adminCreateInvite(label: String, validity: String = "7d") async throws -> CreateInviteResponse {
        let body = try JSONSerialization.data(withJSONObject: ["label": label, "validity": validity])
        let (data, http, _) = try await request(path: "/api/invites", method: "POST", body: body, contentType: "application/json")
        guard let decoded = try? JSONDecoder().decode(CreateInviteResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode >= 400 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Opération refusée")
        }
        return decoded
    }

    func adminExtendInvite(id: Int, validity: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["validity": validity])
        let (data, http, _) = try await request(
            path: "/api/invites/\(id)/extend",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Prolongation impossible")
        }
    }

    func adminReissueInvite(id: Int) async throws -> String? {
        let (data, http, _) = try await request(path: "/api/invites/\(id)/reissue", method: "POST", body: Data(), contentType: "application/json")
        struct R: Decodable { let ok: Bool?; let url: String?; let error: String? }
        let decoded = try? JSONDecoder().decode(R.self, from: data)
        if http.statusCode >= 400 || decoded?.ok == false {
            throw BeerAPIError.server(decoded?.error ?? "Réémission impossible")
        }
        return decoded?.url
    }

    func adminRevokeInvite(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/invites/\(id)", method: "DELETE", body: nil)
        if http.statusCode >= 400 { throw BeerAPIError.server("Révocation impossible") }
    }

    func adminCleanupPhotos() async throws -> String {
        let (data, http, _) = try await request(path: "/api/admin/photos/cleanup", method: "POST", body: Data(), contentType: "application/json")
        if http.statusCode >= 400 { throw BeerAPIError.server("Nettoyage impossible") }
        struct R: Decodable { let removed: Int?; let message: String? }
        let r = try? JSONDecoder().decode(R.self, from: data)
        return r?.message ?? "\(r?.removed ?? 0) photo(s) supprimée(s)"
    }

    func downloadAsset(_ pathOrURL: String?) async throws -> Data {
        guard let p = pathOrURL, !p.isEmpty else {
            throw BeerAPIError.invalidURL
        }

        if p.hasPrefix("http://") || p.hasPrefix("https://") {
            // External asset (e.g. Untappd search result labels, or other third-party images).
            // Use plain system networking — do NOT go through homelab transport, cookie injection,
            // (IPv4 forcing for LAN cert bypass)
            guard let url = URL(string: p) else { throw BeerAPIError.invalidURL }
            // Theme 3: retry with backoff also for external photos (centralized)
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    throw BeerAPIError.server("Fichier externe HTTP \(http.statusCode)")
                }
                return data
            }
        }

        // Internal server asset (relative path like "photos/..." or "static/...").
        // Always try LAN IP first for owner (fast direct, no domain transport).
        // If fails (e.g. on VPN where LAN IP not reachable), fallback to current base.
        guard let lanResolved = ServerSettings.resolveAssetURL(p, base: ServerSettings.lanApiBase) else {
            throw BeerAPIError.invalidURL
        }
        var req = URLRequest(url: lanResolved)
        do {
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, http, _) = try await self.performTransport(req)
                try self.throwIfUnauthorized(http.statusCode)
                if http.statusCode != 200 { throw BeerAPIError.server("Fichier HTTP \(http.statusCode)") }
                return data
            }
        } catch {
            // fallback to current base (domain for VPN)
            guard let resolved = ServerSettings.resolveAssetURL(p, base: baseURL) else {
                throw BeerAPIError.invalidURL
            }
            req = URLRequest(url: resolved)
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, http, _) = try await self.performTransport(req)
                try self.throwIfUnauthorized(http.statusCode)
                if http.statusCode != 200 { throw BeerAPIError.server("Fichier HTTP \(http.statusCode)") }
                return data
            }
        }
    }

    func untappdSearch(query: String) async throws -> UntappdSearchResponse {
        var components = URLComponents(url: try url("/api/untappd/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var req = URLRequest(url: components.url!)
        // Priority 3: extend retry backoff to untappd search too
        return try await NetworkManager.shared.withRetry {
            let (data, http, _) = try await performTransport(req)
            try throwIfUnauthorized(http.statusCode)
            guard let decoded = try? JSONDecoder().decode(UntappdSearchResponse.self, from: data) else {
                throw BeerAPIError.decode
            }
            return decoded
        }
    }

    func saveProduct(barcode: String, beerName: String, brewery: String, style: String) async throws -> LookupResponse {
        let payload: [String: Any] = [
            "barcode": barcode,
            "beer_name": beerName,
            "brewery": brewery,
            "style": style,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(path: "/api/products/save", method: "POST", body: json, contentType: "application/json")
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode >= 400 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Sauvegarde impossible")
        }
        return decoded
    }

    func linkProduct(bid: Int, barcode: String, beerName: String, brewery: String) async throws -> LookupResponse {
        let payload: [String: Any] = [
            "untappd_bid": bid,
            "barcode": barcode,
            "beer_name": beerName,
            "brewery": brewery,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(path: "/api/products/link", method: "POST", body: json, contentType: "application/json")
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode >= 400 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Liaison impossible")
        }
        return decoded
    }

    func decodeBarcode(jpeg: Data) async throws -> DecodeBarcodeResponse {
        let boundary = "BeerScan-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/decode-barcode"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = makeMultipart(
            boundary: boundary,
            fields: [:],
            file: ("image", "scan.jpg", "image/jpeg", jpeg)
        )
        let (data, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(DecodeBarcodeResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func scanPhoto(jpeg: Data) async throws -> LookupResponse {
        let boundary = "BeerScan-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/scan-photo"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = makeMultipart(
            boundary: boundary,
            fields: [:],
            file: ("image", "scan.jpg", "image/jpeg", jpeg)
        )
        let (data, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func addHop(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, http, _) = try await request(path: "/api/hops", method: "POST", body: body, contentType: "application/json")
        if http.statusCode >= 400 { throw BeerAPIError.server("Houblon non ajouté") }
    }

    func adminReferentials() async throws -> ReferentialsResponse {
        let (data, http, _) = try await request(path: "/api/admin/referentials", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        guard let decoded = try? JSONDecoder().decode(ReferentialsResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func adminAddStyle(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, http, _) = try await request(path: "/api/styles", method: "POST", body: body, contentType: "application/json")
        if http.statusCode >= 400 { throw BeerAPIError.server("Style non ajouté") }
    }

    func adminDeleteStyle(_ name: String) async throws {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let (_, http, _) = try await request(path: "/api/styles/\(enc)", method: "DELETE", body: nil)
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func adminAddHop(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, http, _) = try await request(path: "/api/hops", method: "POST", body: body, contentType: "application/json")
        if http.statusCode >= 400 { throw BeerAPIError.server("Houblon non ajouté") }
    }

    func adminDeleteHop(_ name: String) async throws {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let (_, http, _) = try await request(path: "/api/hops/\(enc)", method: "DELETE", body: nil)
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func adminAddFlavor(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, http, _) = try await request(path: "/api/flavors/custom", method: "POST", body: body, contentType: "application/json")
        if http.statusCode >= 400 { throw BeerAPIError.server("Saveur non ajoutée") }
    }

    func adminDeleteFlavor(_ name: String) async throws {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let (_, http, _) = try await request(path: "/api/flavors/custom/\(enc)", method: "DELETE", body: nil)
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func adminSetPassword(_ username: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["password": password])
        let (_, http, _) = try await request(
            path: "/api/admin/users/\(username)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 400 { throw BeerAPIError.server("Mot de passe non mis à jour") }
    }

    func untappdFetch(bid: Int, barcode: String = "", beerName: String = "", brewery: String = "") async throws -> LookupResponse {
        let payload: [String: Any] = [
            "untappd_bid": bid,
            "barcode": barcode,
            "beer_name": beerName,
            "brewery": brewery,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(
            path: "/api/untappd/fetch",
            method: "POST",
            body: json,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func flavors(style: String, description: String = "") async throws -> FlavorsResponse {
        var components = URLComponents(url: try url("/api/flavors"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "style", value: style),
            URLQueryItem(name: "description", value: description),
        ]
        var req = URLRequest(url: components.url!)
        let (data, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        guard let decoded = try? JSONDecoder().decode(FlavorsResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func createCheckin(
        barcode: String,
        beerName: String,
        brewery: String,
        style: String,
        abv: String,
        summary: String,
        rating: Double,
        flavors: [String],
        hops: [String],
        comment: String,
        untappdBid: String,
        force: Bool,
        photoJPEG: Data? = nil,
        location: String = ""
    ) async throws -> CreateCheckinResult {
        let boundary = "BeerBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/checkins"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let flavorJSON = (try? String(data: JSONEncoder().encode(flavors), encoding: .utf8)) ?? "[]"
        let hopsJSON = (try? String(data: JSONEncoder().encode(hops), encoding: .utf8)) ?? "[]"
        let loc = String(location.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        req.httpBody = makeMultipart(
            boundary: boundary,
            fields: [
                "barcode": barcode,
                "beer_name": beerName,
                "brewery": brewery,
                "style": style,
                "abv": abv,
                "summary": summary,
                "rating": String(rating),
                "flavors": flavorJSON,
                "hops": hopsJSON,
                "comment": comment,
                "location": loc,
                "untappd_bid": untappdBid,
                "force": force ? "true" : "false",
            ],
            file: photoJPEG.map { ("photo", "photo.jpg", "image/jpeg", $0) }
        )
        let (data, http, _) = try await performTransport(req)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        guard let decoded = try? JSONDecoder().decode(CreateCheckinResult.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode == 409 || decoded.duplicate == true { return decoded }
        if http.statusCode >= 400 {
            throw BeerAPIError.server(decoded.error ?? "Échec enregistrement")
        }
        return decoded
    }

    // MARK: - HTTP

    // Owner main account only (LAN/VPN).

    private func applyCommonHeaders(to req: inout URLRequest) {
        req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
        req.setValue(
            isInviteMode ? Self.nativeUserAgentInvite : Self.nativeUserAgentOwner,
            forHTTPHeaderField: "User-Agent"
        )
        if let token = InviteSessionStore.accessToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(InviteSessionStore.deviceId, forHTTPHeaderField: "X-Beer-Device")
        } else if let cookieStr = beerSessionCookieString() {
            req.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }
    }

    private func beerSessionCookieString() -> String? {
        if let cookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "beer_session" }) {
            return "beer_session=\(cookie.value)"
        }
        return nil
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var lastError: Error?
        let candidates = ServerSettings.candidateURLs
        for candidate in candidates {
            baseURL = Self.canonicalBase(candidate)
            var req = URLRequest(url: try url(path))
            req.httpMethod = method
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            applyCommonHeaders(to: &req)
            req.httpBody = body
            // Cookies owner si pas Bearer
            if InviteSessionStore.accessToken == nil {
                if let cookieStr = beerSessionCookieString() {
                    req.setValue(cookieStr, forHTTPHeaderField: "Cookie")
                } else if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL), !cookies.isEmpty {
                    let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    req.setValue(cookieString, forHTTPHeaderField: "Cookie")
                }
            }
            do {
                let result = try await performOnEndpoint(candidate, request: req, probe: false)
                activeEndpoint = candidate.absoluteString
                return result
            } catch {
                lastError = error
            }
        }
        let tried = candidates.map(\.absoluteString).joined(separator: ", ")
        if let lastError { throw lastError }
        throw BeerAPIError.allEndpointsFailed(
            isInviteMode
                ? "Serveur injoignable en 4G/5G (\(tried)). Réessaie."
                : "Aucun serveur joignable (\(tried)). Vérifie ta connexion Wi-Fi/VPN et l'autorisation « Réseau local » dans Réglages."
        )
    }

    private func performTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        var req = request
        applyCommonHeaders(to: &req)
        if InviteSessionStore.accessToken == nil {
            if let cookieStr = beerSessionCookieString() {
                req.setValue(cookieStr, forHTTPHeaderField: "Cookie")
            } else if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL), !cookies.isEmpty {
                let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                req.setValue(cookieString, forHTTPHeaderField: "Cookie")
            }
        }
        return try await performOnEndpoint(baseURL, request: req, probe: false)
    }

    private func performOnEndpoint(
        _ endpoint: URL,
        request: URLRequest,
        probe: Bool = false
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var req = request
        applyCommonHeaders(to: &req)
        // Host canonique si on tape l'IPv4 WAN directement
        if endpoint.host == ServerSettings.wanIPv4 || req.url?.host == ServerSettings.wanIPv4 {
            req.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        }
        let httpSession = session(for: endpoint, probe: probe)
        do {
            let (data, response) = try await httpSession.data(for: req)
            guard let http = response as? HTTPURLResponse, let url = response.url else {
                throw BeerAPIError.decode
            }
            return (data, http, url)
        } catch let err as BeerAPIError {
            throw err
        } catch let err as URLError {
            switch err.code {
            case .cannotConnectToHost, .networkConnectionLost:
                throw BeerAPIError.server("Injoignable : \(endpoint.host ?? "?"). Vérifie Wi-Fi/VPN et que le serveur est up.")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                let host = endpoint.host ?? "?"
                if host.hasPrefix("192.168.") {
                    throw BeerAPIError.server("SSL refusé sur \(host). Active « Réseau local » pour Beer Log dans Réglages > Confidentialité et sécurité, et réessaie.")
                } else {
                    throw BeerAPIError.server("SSL refusé sur \(host).")
                }
            case .timedOut:
                throw BeerAPIError.server("Timeout \(endpoint.host ?? "?").")
            case .notConnectedToInternet:
                throw BeerAPIError.server("Pas de réseau")
            default:
                throw BeerAPIError.network(err)
            }
        } catch {
            throw BeerAPIError.network(error)
        }
    }

    private func throwIfUnauthorized(_ status: Int) throws {
        if status == 401 {
            NotificationCenter.default.post(name: .beerAuthExpired, object: nil)
            throw BeerAPIError.unauthorized
        }
    }

    private func performWan(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        // Fallback path (for domain access if needed).
        // No custom LAN IPv4 or TLS delegate.
        try await performOnEndpoint(ServerSettings.apiBase, request: request)
    }

    private static func canonicalBase(_ url: URL) -> URL {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/") ?? url
    }

    private func url(_ path: String) throws -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: clean, relativeTo: baseURL) else {
            throw BeerAPIError.invalidURL
        }
        return url
    }

    private func makeMultipart(
        boundary: String,
        fields: [String: String],
        file: (name: String, filename: String, mime: String, data: Data)? = nil
    ) -> Data {
        var body = Data()
        let nl = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(nl)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(nl)\(nl)".data(using: .utf8)!)
            body.append("\(value)\(nl)".data(using: .utf8)!)
        }
        if let file {
            body.append("--\(boundary)\(nl)".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\(nl)"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(file.mime)\(nl)\(nl)".data(using: .utf8)!)
            body.append(file.data)
            body.append(nl.data(using: .utf8)!)
        }
        body.append("--\(boundary)--\(nl)".data(using: .utf8)!)
        return body
    }

    // Note: retry logic centralized in NetworkManager (priority 3). Local copy removed to avoid duplication.
}