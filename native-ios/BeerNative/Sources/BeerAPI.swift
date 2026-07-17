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
    private static let nativeUserAgentOwner = "PlexiBeer/3.5.0 (iPhone; native owner) [lan-vpn]"
    private static let nativeUserAgentInvite = "PlexiBeer/3.5.0 (iPhone; native invite) [wan]"

    /// Owner LAN/VPN — URLSession + TLS homelab (pas de transport custom IPv4)
    private let ownerSession: URLSession
    /// Probe LAN court
    private let lanProbeSession: URLSession
    private(set) var baseURL: URL
    private(set) var activeEndpoint: String = ""

    var isInviteMode: Bool {
        ServerSettings.inviteMode || InviteSessionStore.hasInviteSession
    }

    init(baseURL: URL = ServerSettings.lanApiBase) {
        self.baseURL = Self.canonicalBase(baseURL)
        let sharedCookies = HTTPCookieStorage.shared
        func baseConfig(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) -> URLSessionConfiguration {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = sharedCookies
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .always
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = resourceTimeout
            config.waitsForConnectivity = false
            return config
        }
        // Owner : session standard + HomelabTLS (accepte cert LE sur IP LAN)
        self.ownerSession = URLSession(
            configuration: baseConfig(requestTimeout: 20, resourceTimeout: 60),
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
        self.lanProbeSession = URLSession(
            configuration: baseConfig(requestTimeout: 5, resourceTimeout: 8),
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
    }

    func setBaseURL(_ url: URL) {
        baseURL = Self.canonicalBase(url)
        activeEndpoint = baseURL.absoluteString
    }

    func enableInviteMode(_ enabled: Bool) {
        ServerSettings.inviteMode = enabled
        if enabled {
            setBaseURL(ServerSettings.apiBase)
        } else {
            // Owner : repasser en LAN par défaut (comme Android)
            if !ServerSettings.isLanEndpoint(baseURL) {
                setBaseURL(ServerSettings.lanApiBase)
            }
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

    /// Owner discover — miroir Android : LAN puis FQDN (pas de mode invite).
    func discoverWorkingEndpoint() async -> String? {
        if isInviteMode {
            return await probeInviteWan()
        }
        let original = baseURL
        // 1) LAN maison
        do {
            let lan = ServerSettings.lanApiBase
            var req = URLRequest(url: URL(string: "api/health", relativeTo: lan)!)
            req.httpMethod = "GET"
            applyCommonHeaders(to: &req)
            let (_, http, _) = try await ownerData(req, session: lanProbeSession)
            if http.statusCode == 200 {
                setBaseURL(lan)
                return lan.absoluteString
            }
        } catch {
            NSLog("BeerAPI LAN probe fail: \(error.localizedDescription)")
        }
        // 2) Domaine (VPN) via URLSession normal
        do {
            let wan = ServerSettings.apiBase
            var req = URLRequest(url: URL(string: "api/health", relativeTo: wan)!)
            req.httpMethod = "GET"
            applyCommonHeaders(to: &req)
            let (_, http, _) = try await ownerData(req, session: ownerSession)
            if http.statusCode == 200 {
                setBaseURL(wan)
                return wan.absoluteString
            }
        } catch {
            NSLog("BeerAPI domain probe fail: \(error.localizedDescription)")
        }
        baseURL = original
        return nil
    }

    /// Invite only — IPv4+SNI (comme Android Prefer IPv4).
    private func probeInviteWan() async -> String? {
        var req = URLRequest(url: URL(string: "https://\(ServerSettings.canonicalHost)/beer/api/health")!)
        req.httpMethod = "GET"
        req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
        req.setValue(Self.nativeUserAgentInvite, forHTTPHeaderField: "User-Agent")
        do {
            let (_, http, _) = try await HomelabIPv4Transport.perform(req, timeoutSeconds: 12)
            if http.statusCode == 200 || http.statusCode == 403 {
                setBaseURL(ServerSettings.apiBase)
                return ServerSettings.apiBase.absoluteString
            }
        } catch {
            NSLog("BeerAPI invite probe fail: \(error.localizedDescription)")
        }
        return nil
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        // Owner path = Android login
        enableInviteMode(false)
        InviteSessionStore.clear()
        setBaseURL(ServerSettings.lanApiBase)
        _ = await discoverWorkingEndpoint()
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
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
            throw BeerAPIError.server("Réponse login invalide (HTTP \(http.statusCode))")
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
        // Force cookie capture even if Domain mismatched (like Android)
        if beerSessionCookieString() == nil {
            // try parse from raw header variants
            if let all = http.value(forHTTPHeaderField: "Set-Cookie"), all.contains("beer_session=") {
                // already handled above
            }
        }
        return decoded
    }

    /// Invitation WAN — miroir Android joinInvite (IPv4 first, puis IP directe).
    func joinInvite(inviteLink: String) async throws -> NativeJoinResponse {
        guard let token = InviteSessionStore.parseInviteToken(inviteLink) else {
            throw BeerAPIError.server("Lien d'invitation invalide")
        }
        let deviceId = InviteSessionStore.deviceId
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        BeerSessionStore.clear()
        enableInviteMode(true)
        setBaseURL(ServerSettings.apiBase)

        let body = try JSONEncoder().encode(["token": token, "device_id": deviceId])

        func buildReq(host: String) -> URLRequest {
            var req = URLRequest(url: URL(string: "https://\(host)/beer/api/native/join")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
            req.setValue(Self.nativeUserAgentInvite, forHTTPHeaderField: "User-Agent")
            req.setValue(deviceId, forHTTPHeaderField: "X-Beer-Device")
            req.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
            req.httpBody = body
            return req
        }

        var lastError: Error?
        // 1) FQDN via transport IPv4+SNI (comme PreferIpv4Dns Android)
        do {
            let (data, http, _) = try await HomelabIPv4Transport.perform(
                buildReq(host: ServerSettings.canonicalHost),
                timeoutSeconds: 15
            )
            return try parseJoin(data: data, http: http, deviceId: deviceId)
        } catch {
            lastError = error
            NSLog("joinInvite FQDN fail: \(error.localizedDescription)")
        }
        // 2) IP directe (comme Android WAN_IPV4_API_BASE)
        do {
            let (data, http, _) = try await HomelabIPv4Transport.perform(
                buildReq(host: ServerSettings.wanIPv4),
                timeoutSeconds: 15
            )
            return try parseJoin(data: data, http: http, deviceId: deviceId)
        } catch {
            lastError = error
        }
        throw lastError ?? BeerAPIError.server("Serveur injoignable en 4G/5G")
    }

    private func parseJoin(data: Data, http: HTTPURLResponse, deviceId: String) throws -> NativeJoinResponse {
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
        InviteSessionStore.save(
            accessToken: decoded.accessToken!,
            user: decoded.user ?? "invite",
            label: decoded.label,
            expiresAt: decoded.expiresAt,
            deviceId: decoded.deviceId ?? deviceId
        )
        enableInviteMode(true)
        activeEndpoint = ServerSettings.apiBase.absoluteString
        return decoded
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

    // MARK: - HTTP (owner = URLSession ; invite = IPv4 transport)

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

    private func ownerData(_ req: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse, URL) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, let u = response.url else {
                throw BeerAPIError.decode
            }
            return (data, http, u)
        } catch let err as URLError {
            switch err.code {
            case .cannotConnectToHost, .networkConnectionLost:
                throw BeerAPIError.server("Injoignable (\(req.url?.host ?? "?")). Wi‑Fi maison ou VPN ?")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                throw BeerAPIError.server("SSL refusé sur \(req.url?.host ?? "?"). Autorise « Réseau local » pour Beer Log.")
            case .timedOut:
                throw BeerAPIError.server("Timeout \(req.url?.host ?? "?")")
            case .notConnectedToInternet:
                throw BeerAPIError.server("Pas de réseau")
            default:
                throw BeerAPIError.network(err)
            }
        }
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse, URL) {
        // —— INVITÉ (comme Android) : uniquement WAN IPv4 ——
        if isInviteMode {
            baseURL = Self.canonicalBase(ServerSettings.apiBase)
            var req = URLRequest(url: try url(path))
            req.httpMethod = method
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            applyCommonHeaders(to: &req)
            req.httpBody = body
            let result = try await HomelabIPv4Transport.perform(req, timeoutSeconds: 15)
            activeEndpoint = ServerSettings.apiBase.absoluteString
            return result
        }

        // —— OWNER (comme Android) : LAN puis domaine ——
        var lastError: Error?
        let candidates = [ServerSettings.lanApiBase, ServerSettings.apiBase]
        for candidate in candidates {
            baseURL = Self.canonicalBase(candidate)
            var req = URLRequest(url: try url(path))
            req.httpMethod = method
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            applyCommonHeaders(to: &req)
            req.httpBody = body
            if let cookieStr = beerSessionCookieString() {
                req.setValue(cookieStr, forHTTPHeaderField: "Cookie")
            }
            do {
                let result = try await ownerData(req, session: ownerSession)
                activeEndpoint = candidate.absoluteString
                return result
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw BeerAPIError.allEndpointsFailed(
            "Serveur injoignable. Wi‑Fi maison (192.168.1.50) ou VPN Plexi requis pour les comptes."
        )
    }

    private func performTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        var req = request
        applyCommonHeaders(to: &req)
        if isInviteMode {
            // Forcer URL absolue domaine pour le transport IPv4
            if let u = req.url, u.host != ServerSettings.canonicalHost {
                let path = u.path + (u.query.map { "?\($0)" } ?? "")
                req.url = URL(string: "https://\(ServerSettings.canonicalHost)\(path)")
            }
            return try await HomelabIPv4Transport.perform(req, timeoutSeconds: 15)
        }
        if let cookieStr = beerSessionCookieString() {
            req.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }
        return try await ownerData(req, session: ownerSession)
    }

    private func throwIfUnauthorized(_ status: Int) throws {
        if status == 401 {
            NotificationCenter.default.post(name: .beerAuthExpired, object: nil)
            throw BeerAPIError.unauthorized
        }
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