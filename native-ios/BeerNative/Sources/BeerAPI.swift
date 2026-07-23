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
    private static let userAgentOwner = "PlexiBeer/4.2.8 (iPhone; native owner) [lan-vpn]"
    private static let userAgentInvite = "PlexiBeer/4.2.8 (iPhone; native invite) [wan]"

    // Un seul client comme OkHttp Android (30s connect, 120s read)
    private let client: URLSession
    private let probeClient: URLSession
    private(set) var baseURL: URL
    private(set) var activeEndpoint: String = ""

    var isInviteMode: Bool {
        ServerSettings.inviteMode || InviteSessionStore.hasInviteSession
    }

    init(baseURL: URL = ServerSettings.lanApiBase) {
        self.baseURL = Self.canonicalBase(baseURL)
        let cookies = HTTPCookieStorage.shared
        func cfg(connect: TimeInterval, read: TimeInterval) -> URLSessionConfiguration {
            let c = URLSessionConfiguration.default
            c.httpCookieStorage = cookies
            c.httpShouldSetCookies = false
            c.httpCookieAcceptPolicy = .always
            c.timeoutIntervalForRequest = connect
            c.timeoutIntervalForResource = read
            c.waitsForConnectivity = false
            return c
        }
        // HomelabTLS = Android HomelabTls (LAN IP + WAN IP + domaine)
        self.client = URLSession(
            configuration: cfg(connect: 30, read: 120),
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
        self.probeClient = URLSession(
            configuration: cfg(connect: ServerSettings.lanProbeTimeoutSec, read: ServerSettings.lanProbeTimeoutSec + 4),
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
    }

    func setBaseURL(_ url: URL) {
        let s = Self.canonicalBase(url)
        baseURL = s
        activeEndpoint = s.absoluteString
        ServerSettings.setRuntimeBase(s.absoluteString)
    }

    func setBaseURL(_ string: String) {
        setBaseURL(URL(string: ServerSettings.normalizeInput(string))!)
    }

    func enableInviteMode(_ enabled: Bool) {
        ServerSettings.inviteMode = enabled
        if enabled {
            let saved = InviteSessionStore.apiBase ?? ServerSettings.apiBaseString
            setBaseURL(saved)
        }
    }

    func clearSession() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        BeerSessionStore.clear()
        InviteSessionStore.clear()
        ServerSettings.inviteMode = false
        ServerSettings.resetToLan()
        baseURL = Self.canonicalBase(URL(string: ServerSettings.effectiveBase)!)
        activeEndpoint = baseURL.absoluteString
    }

    private func absURL(_ path: String) -> URL {
        let base = baseURL.absoluteString
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + p)!
    }

    private func applyHeaders(to req: inout URLRequest) {
        req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
        req.setValue(
            isInviteMode ? Self.userAgentInvite : Self.userAgentOwner,
            forHTTPHeaderField: "User-Agent"
        )
        if let token = InviteSessionStore.accessToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(InviteSessionStore.deviceId, forHTTPHeaderField: "X-Beer-Device")
        } else if let cookie = beerSessionCookieString() {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        // Android: Host canonique si on tape l'IPv4 WAN
        if req.url?.host == ServerSettings.wanIPv4 {
            req.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        }
    }

    private func beerSessionCookieString() -> String? {
        HTTPCookieStorage.shared.cookies?
            .first(where: { $0.name == "beer_session" })
            .map { "beer_session=\($0.value)" }
    }

    /// **Invite WAN = URLSession uniquement** (comme les join 200 en logs prod).
    /// PreferIPv4 force dial `82.64.151.113` (jamais AAAA Freebox).
    /// HomelabTLS accepte le cert LE du domaine sur l'IP.
    /// **Zéro** NWConnection / HomelabIPv4 — c'est ça qui jetait « Timeout 30s » en instantané.
    /// Owner LAN : URLSession + HomelabTLS inchangé.
    private func execute(
        _ request: URLRequest,
        probe: Bool = false,
        allowUnauthorizedBody: Bool = false
    ) async throws -> (Data, Int, HTTPURLResponse, URL) {
        var req = request
        applyHeaders(to: &req)

        let rawHost = req.url?.host ?? ""
        let isLan = ServerSettings.isLanEndpoint(req.url ?? baseURL)
            || ServerSettings.isLanHost(rawHost)

        // Invite / WAN : forcer IPv4 hardcodée (équivalent preferIpv4Dns OkHttp)
        if isInviteMode || (!isLan && (rawHost == ServerSettings.canonicalHost || rawHost == ServerSettings.wanIPv4)) {
            if var c = URLComponents(url: req.url ?? ServerSettings.apiBase, resolvingAgainstBaseURL: false) {
                // Path/query conservés ; host repassera en IPv4 via PreferIPv4
                c.host = ServerSettings.canonicalHost
                c.scheme = "https"
                c.port = nil
                if let u = c.url { req.url = u }
            }
            PreferIPv4.applyAndroidStyle(&req)
        } else if rawHost == ServerSettings.wanIPv4 {
            req.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        }

        // Timeouts réalistes — message d'erreur ne ment plus sur la durée
        let timeout: TimeInterval = probe ? 15 : 45
        req.timeoutInterval = timeout

        let session = probe ? probeClient : client
        let started = Date()
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, let u = response.url else {
                throw BeerAPIError.decode
            }
            if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"), !setCookie.isEmpty {
                let cookies = HTTPCookie.cookies(
                    withResponseHeaderFields: ["Set-Cookie": setCookie],
                    for: u
                )
                for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
                if let domainURL = URL(string: "https://\(ServerSettings.canonicalHost)/beer/") {
                    for c in HTTPCookie.cookies(
                        withResponseHeaderFields: ["Set-Cookie": setCookie],
                        for: domainURL
                    ) {
                        HTTPCookieStorage.shared.setCookie(c)
                    }
                }
            }
            return try finishHTTPInviteAware(
                data: data,
                http: http,
                url: u,
                allowUnauthorizedBody: allowUnauthorizedBody
            )
        } catch let e as BeerAPIError {
            throw e
        } catch let err as URLError {
            let elapsed = Date().timeIntervalSince(started)
            throw mapURLError(err, elapsed: elapsed, budget: timeout)
        } catch {
            throw BeerAPIError.server("Connexion \(ServerSettings.canonicalHost) impossible — réessaie")
        }
    }

    private func finishHTTPInviteAware(
        data: Data,
        http: HTTPURLResponse,
        url: URL,
        allowUnauthorizedBody: Bool
    ) throws -> (Data, Int, HTTPURLResponse, URL) {
        let code = http.statusCode
        if code == 401 && !allowUnauthorizedBody {
            if isInviteMode { InviteSessionStore.clear() }
            NotificationCenter.default.post(name: .beerAuthExpired, object: nil)
            throw BeerAPIError.unauthorized
        }
        if code == 403 && !allowUnauthorizedBody {
            if isInviteMode {
                struct E: Decodable { let error: String? }
                let detail = (try? JSONDecoder().decode(E.self, from: data))?.error ?? ""
                let dead = detail.localizedCaseInsensitiveContains("Invitation invalide")
                    || detail.localizedCaseInsensitiveContains("expir")
                if dead {
                    InviteSessionStore.clear()
                    throw BeerAPIError.server("Invitation invalide ou expirée — demande un nouveau lien")
                }
                throw BeerAPIError.server(
                    detail.isEmpty
                        ? "Accès refusé — réessaie ou rouvre le lien"
                        : detail
                )
            }
            throw BeerAPIError.forbidden
        }
        if !(200..<300).contains(code) && code != 401 && code != 409 {
            struct E: Decodable { let error: String? }
            let err = (try? JSONDecoder().decode(E.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Erreur serveur: \(code)")
        }
        return (data, code, http, url)
    }

    /// Mappe les URLError avec la **vraie** durée écoulée — plus de « Timeout 30s » instantané mensonger.
    private func mapURLError(_ err: URLError, elapsed: TimeInterval, budget: TimeInterval) -> BeerAPIError {
        let host = ServerSettings.canonicalHost
        let secs = max(0, Int(elapsed.rounded()))
        switch err.code {
        case .timedOut:
            if elapsed < 2 {
                // Échec immédiat mal étiqueté « timeout » par CFNetwork
                return .server("Connexion refusée vers \(host) (immédiat) — réessaie")
            }
            return .server("Timeout après \(secs)s vers \(host) — réessaie")
        case .notConnectedToInternet:
            return .server("Pas de réseau cellulaire / Wi‑Fi")
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost:
            return .server("Injoignable \(host) (\(secs)s) — \(err.localizedDescription)")
        case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected:
            return .server("TLS vers \(host) refusé (\(secs)s) — réessaie")
        case .cancelled:
            return .server("Connexion annulée")
        default:
            return .server("Réseau \(host): \(err.localizedDescription) (\(secs)s)")
        }
    }

    func healthCheck() async throws -> Bool {
        var req = URLRequest(url: absURL("api/health"))
        req.httpMethod = "GET"
        let (_, code, _, _) = try await execute(req)
        return (200..<300).contains(code)
    }

    /// Android discoverWorkingEndpoint — candidateURLs, isSuccessful (2xx).
    /// Invite : préfère `/api/native/session` (route publique + Bearer) plutôt que health
    /// (health sans gate valide = 403 nginx → faux « injoignable » après un join OK).
    func discoverWorkingEndpoint() async -> String? {
        let original = baseURL.absoluteString
        for candidate in ServerSettings.candidateURLs {
            do {
                setBaseURL(candidate)
                if isInviteMode, InviteSessionStore.hasInviteSession {
                    var req = URLRequest(url: absURL("api/native/session"))
                    req.httpMethod = "GET"
                    applyHeaders(to: &req)
                    let (_, code, _, _) = try await execute(req, probe: true, allowUnauthorizedBody: true)
                    if (200..<300).contains(code) {
                        return candidate
                    }
                    // 401 = token mort ; autre = endpoint joignable quand même
                    if code == 401 { continue }
                    if code == 403 || code == 404 { return candidate }
                } else {
                    var req = URLRequest(url: absURL("api/health"))
                    req.httpMethod = "GET"
                    applyHeaders(to: &req)
                    let (_, code, _, _) = try await execute(req, probe: true, allowUnauthorizedBody: true)
                    if (200..<300).contains(code) {
                        return candidate
                    }
                    // WAN sans session : 403 nginx prouve TLS/TCP OK
                    if code == 403 || code == 401 {
                        return candidate
                    }
                }
            } catch {
                continue
            }
        }
        setBaseURL(original)
        return nil
    }

    /// Health token invité (nginx allow all + Bearer).
    func nativeSessionOK() async -> Bool {
        guard isInviteMode, InviteSessionStore.hasInviteSession else { return false }
        do {
            var req = URLRequest(url: absURL("api/native/session"))
            req.httpMethod = "GET"
            applyHeaders(to: &req)
            let (_, code, _, _) = try await execute(req, probe: true, allowUnauthorizedBody: true)
            return (200..<300).contains(code)
        } catch {
            return false
        }
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        enableInviteMode(false)
        InviteSessionStore.clear()
        setBaseURL(ServerSettings.lanApiBaseString)
        _ = await discoverWorkingEndpoint()
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        let body = try JSONEncoder().encode(["username": username, "password": password])
        var req = URLRequest(url: absURL("api/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
        req.setValue(Self.userAgentOwner, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        let (data, code, http, responseURL) = try await execute(req, allowUnauthorizedBody: true)
        if code == 403 {
            throw BeerAPIError.server("Accès refusé — Wi‑Fi maison ou VPN Plexi requis pour les comptes principaux")
        }
        guard let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
            throw BeerAPIError.server("Réponse login invalide (HTTP \(code))")
        }
        if code == 401 || code >= 400 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Identifiants incorrects")
        }
        if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"), !setCookie.isEmpty {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: responseURL)
            for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
        }
        if beerSessionCookieString() == nil {
            throw BeerAPIError.server("Login OK mais cookie session absent. Réessaie.")
        }
        return decoded
    }

    /// Activation invité WAN — miroir Android `joinInvite` :
    /// candidates FQDN puis IPv4, transport IPv4+SNI unique, pas de cookies owner.
    /// `email` : saisi par l'invité (pré-enregistré côté admin), aucun indice côté UI.
    func joinInvite(inviteLink: String, email: String) async throws -> NativeJoinResponse {
        guard let token = InviteSessionStore.parseInviteToken(inviteLink) else {
            throw BeerAPIError.server("Lien d'invitation invalide")
        }
        let emailClean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailClean.isEmpty, emailClean.contains("@") else {
            throw BeerAPIError.server("Email requis")
        }
        let deviceId = InviteSessionStore.deviceId
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        BeerSessionStore.clear()

        let body = try JSONEncoder().encode([
            "token": token,
            "device_id": deviceId,
            "email": emailClean,
        ])
        var lastError: Error?

        // Beer prod vs Beerquest alpha : base déduite du lien
        let candidates = ServerSettings.basesFromInviteLink(inviteLink)
        for candidate in candidates {
            do {
                setBaseURL(candidate)
                enableInviteMode(true)
                // URL join = base + api/native/join (beer ou beer-alpha)
                var req = URLRequest(url: absURL("api/native/join"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
                req.setValue(Self.userAgentInvite, forHTTPHeaderField: "User-Agent")
                req.setValue(deviceId, forHTTPHeaderField: "X-Beer-Device")
                req.httpBody = body

                let (data, code, _, _) = try await execute(req, allowUnauthorizedBody: true)
                guard let decoded = try? JSONDecoder().decode(NativeJoinResponse.self, from: data) else {
                    throw BeerAPIError.server("Réponse join invalide (HTTP \(code))")
                }
                if code == 429 {
                    throw BeerAPIError.server("Trop de tentatives — réessaie dans une minute")
                }
                if code == 403, decoded.error == "wrong_device" {
                    throw BeerAPIError.server("Cette invitation est déjà liée à un autre téléphone")
                }
                if code >= 400 || !decoded.ok || (decoded.accessToken ?? "").isEmpty {
                    let msg: String
                    switch decoded.error {
                    case "invalid": msg = "Invitation invalide ou expirée"
                    case "invalid_device": msg = "Identifiant appareil invalide"
                    case "disabled": msg = "Invitations natives désactivées"
                    case "email_required": msg = "Email requis"
                    case "wrong_email": msg = "Email incorrect"
                    case "rate_limit": msg = "Trop de tentatives — réessaie dans une minute"
                    default: msg = decoded.error ?? "Activation impossible (HTTP \(code))"
                    }
                    // Erreurs métier : pas de retry sur autre endpoint
                    throw BeerAPIError.server(msg)
                }
                InviteSessionStore.save(
                    accessToken: decoded.accessToken!,
                    user: decoded.user ?? "invite",
                    label: decoded.label,
                    expiresAt: decoded.expiresAt,
                    deviceId: decoded.deviceId ?? deviceId,
                    apiBase: candidate
                )
                enableInviteMode(true)
                setBaseURL(candidate)
                return decoded
            } catch let e as BeerAPIError {
                lastError = e
                // 400/403/429 métier : stop (comme Android)
                let msg = e.errorDescription ?? ""
                if msg.contains("invalide") || msg.contains("liée") || msg.contains("Trop")
                    || msg.contains("désactiv") || msg.contains("appareil") {
                    throw e
                }
                // réseau : essayer candidat suivant
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw BeerAPIError.server("Serveur injoignable en 4G/5G — réessaie")
    }

    func clearAllAuth() { clearSession() }

    func me() async throws -> MeResponse {
        let (data, http, _) = try await request(path: "/api/me", method: "GET", body: nil)
        // 401 = révoqué / expiré (serveur) — wipe Bearer invité
        if http.statusCode == 401 {
            if isInviteMode { InviteSessionStore.clear() }
            NotificationCenter.default.post(name: .beerAuthExpired, object: nil)
            throw BeerAPIError.unauthorized
        }
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
        // Défense : 200 + user vide alors qu'on était en invite = session morte
        if isInviteMode, (decoded.user ?? "").isEmpty {
            InviteSessionStore.clear()
            NotificationCenter.default.post(name: .beerAuthExpired, object: nil)
            throw BeerAPIError.unauthorized
        }
        return decoded
    }

    /// Beerquest state — enabled=false si RPG off.
    func rpgMe() async throws -> RpgState {
        let (data, http, _) = try await request(path: "/api/rpg/me", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            return RpgState(enabled: false)
        }
        return (try? JSONDecoder().decode(RpgState.self, from: data)) ?? RpgState(enabled: false)
    }

    func rpgSetClass(_ key: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["class": key])
        let (data, http, _) = try await request(
            path: "/api/rpg/class",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 200 && http.statusCode < 300 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["ok"] as? Bool) == true
            }
            return true
        }
        return false
    }

    func rpgIntroSeen() async throws -> Bool {
        let (data, http, _) = try await request(
            path: "/api/rpg/intro-seen",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        if http.statusCode >= 200 && http.statusCode < 300 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["ok"] as? Bool) != false
            }
            return true
        }
        return false
    }

    func adminRpgPlayers() async throws -> [RpgAdminPlayer] {
        let decoded = try await adminRpgPlayersBundle()
        return decoded.players ?? []
    }

    func adminRpgPlayersBundle() async throws -> RpgAdminPlayersResponse {
        let (data, http, _) = try await request(path: "/api/admin/rpg/players", method: "GET", body: nil)
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Admin RPG indisponible")
        }
        return try JSONDecoder().decode(RpgAdminPlayersResponse.self, from: data)
    }

    func adminRpgGetSettings() async throws -> RpgAdminFlags {
        let (data, http, _) = try await request(path: "/api/admin/rpg/settings", method: "GET", body: nil)
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Réglages RPG indisponibles")
        }
        let decoded = try JSONDecoder().decode(RpgAdminSettingsResponse.self, from: data)
        return decoded.flags ?? RpgAdminFlags()
    }

    func adminRpgPatchSettings(_ payload: [String: Any]) async throws -> RpgAdminFlags {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/settings",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec réglages RPG")
        }
        let decoded = try JSONDecoder().decode(RpgAdminSettingsResponse.self, from: data)
        return decoded.flags ?? RpgAdminFlags()
    }

    /// allowed: true=force ON, false=force OFF, nil=auto (défaut)
    func adminRpgSetUserAllowed(username: String, allowed: Bool?) async throws {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let payload: [String: Any]
        if let allowed {
            payload = ["allowed": allowed]
        } else {
            payload = ["allowed": NSNull()]
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (_, http, _) = try await request(
            path: "/api/admin/rpg/settings/users/\(enc)",
            method: "PUT",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec accès user RPG")
        }
    }

    func adminRpgPlayer(_ username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)",
            method: "GET",
            body: nil
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Joueur introuvable")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }

    func adminRpgPatchPlayer(_ username: String, payload: [String: Any]) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec mise à jour profil")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }

    func adminRpgAdjustXp(username: String, delta: Int) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: ["delta": delta])
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/xp",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec XP")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }

    func adminRpgResetDaily(username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/reset-daily",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec reset journalier")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }

    func adminRpgGrantBadge(username: String, badgeKey: String) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: ["badge_key": badgeKey])
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/badges",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec badge")
        }
        // { granted, player: <admin_get_player detail> }
        if let wrap = try? JSONDecoder().decode(RpgAdminBadgeActionResponse.self, from: data),
           let detail = wrap.player {
            return detail
        }
        return try await adminRpgPlayer(username)
    }

    func adminRpgRevokeBadge(username: String, badgeKey: String) async throws -> RpgAdminPlayerDetail {
        let encU = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encB = badgeKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? badgeKey
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(encU)/badges/\(encB)",
            method: "DELETE",
            body: nil
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec retrait badge")
        }
        if let wrap = try? JSONDecoder().decode(RpgAdminBadgeActionResponse.self, from: data),
           let detail = wrap.player {
            return detail
        }
        return try await adminRpgPlayer(username)
    }

    func adminRpgUnquarantine(_ username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/unquarantine",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec levée quarantaine")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }

    func adminRpgWipe(username: String) async throws {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (_, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/wipe",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec wipe RPG")
        }
    }

    func logout() async {
        if !isInviteMode {
            _ = try? await request(path: "/api/logout", method: "POST", body: nil)
        }
        clearAllAuth()
    }

    /// Feedback joueur (parité PWA « Un retour »).
    func sendFeedback(message: String, category: String = "general", appVersion: String = "") async -> (Bool, String?) {
        var payload: [String: Any] = [
            "message": message,
            "category": category,
            "client_info": "native-ios",
            "page_path": "native/ios",
        ]
        if !appVersion.isEmpty {
            payload["app_version"] = appVersion
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return (false, "JSON invalide")
        }
        do {
            let (data, http, _) = try await request(
                path: "/api/feedback",
                method: "POST",
                body: body,
                contentType: "application/json"
            )
            if (200..<300).contains(http.statusCode) {
                return (true, nil)
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String {
                return (false, detail)
            }
            return (false, "Erreur \(http.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
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

    /// Manifest versions natives (portail public, sans session).
    func fetchMobileVersions() async -> MobileVersionsManifest? {
        guard let url = URL(string: ServerSettings.versionsURLString) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try? JSONDecoder().decode(MobileVersionsManifest.self, from: data)
        } catch {
            return nil
        }
    }

    func adminFeedbackStats() async -> AdminFeedbackStats? {
        do {
            let res = try await adminFeedbackList(limit: 1, unreadOnly: false)
            return res.stats
        } catch {
            return nil
        }
    }

    /// Liste feedback admin (parité webapp onglet Feedback).
    func adminFeedbackList(
        limit: Int = 80,
        unreadOnly: Bool = false,
        status: String? = nil
    ) async throws -> AdminFeedbackListResponse {
        var path = "/api/admin/feedback?limit=\(max(1, min(limit, 200)))"
        if unreadOnly { path += "&unread=1" }
        if let status, !status.isEmpty {
            path += "&status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        let (data, http, _) = try await request(path: path, method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        guard (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AdminFeedbackListResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func adminFeedbackMarkRead(id: Int, read: Bool = true) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["read": read])
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/read",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Marquage lu impossible")
        }
    }

    func adminFeedbackReadAll() async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/read-all",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Lecture globale impossible")
        }
    }

    func adminFeedbackResolve(id: Int, status: String, reply: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "status": status,
            "reply": reply,
        ])
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/resolve",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Réponse impossible")
        }
    }

    func adminFeedbackReopen(id: Int) async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/reopen",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Réouverture impossible")
        }
    }

    func adminFeedbackDelete(id: Int) async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)",
            method: "DELETE",
            body: nil
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Suppression impossible")
        }
    }

    /// Réponses admin non vues (popup joueur).
    func feedbackReplies(unseenOnly: Bool = true) async throws -> [AdminFeedbackItem] {
        let path = "/api/feedback/replies?unseen=\(unseenOnly ? "1" : "0")&limit=20"
        let (data, http, _) = try await request(path: path, method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(FeedbackRepliesResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded.items ?? []
    }

    func markFeedbackRepliesSeen(ids: [Int]) async {
        let body = (try? JSONSerialization.data(withJSONObject: ["ids": ids])) ?? Data("{}".utf8)
        _ = try? await request(
            path: "/api/feedback/replies/seen",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
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

    /// Admin : dégustations d'un invité (lecture seule).
    func adminInviteCheckins(inviteId: Int, limit: Int = 30, offset: Int = 0) async throws -> [CheckinItem] {
        let (data, http, _) = try await request(
            path: "/api/invites/\(inviteId)/checkins?limit=\(limit)&offset=\(offset)",
            method: "GET",
            body: nil
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        if http.statusCode == 404 {
            throw BeerAPIError.server("Invitation introuvable")
        }
        return (try? JSONDecoder().decode([CheckinItem].self, from: data)) ?? []
    }

    func adminCreateInvite(label: String, email: String, validity: String = "7d") async throws -> CreateInviteResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "label": label,
            "email": email,
            "validity": validity,
        ])
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


    // MARK: - HTTP helpers (Android execute)

    private func request(
        path: String,
        method: String,
        body: Data?,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse, URL) {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if isInviteMode {
            // invite: 1 transport IPv4+SNI (HomelabIPv4) ; 1 retry réseau seulement
            // Ne JAMAIS retenter après 401/invitation morte (session déjà wipe)
            var lastError: Error?
            for attempt in 1...2 {
                do {
                    setBaseURL(ServerSettings.apiBaseString)
                    enableInviteMode(true)
                    var req = URLRequest(url: absURL(clean))
                    req.httpMethod = method
                    if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
                    req.httpBody = body
                    let (data, _, http, u) = try await execute(req)
                    return (data, http, u)
                } catch let e as BeerAPIError {
                    lastError = e
                    switch e {
                    case .unauthorized, .forbidden:
                        throw e
                    case .server(let msg):
                        let dead = msg.localizedCaseInsensitiveContains("Invitation invalide")
                            || msg.localizedCaseInsensitiveContains("expir")
                            || msg.localizedCaseInsensitiveContains("révoqu")
                        if dead { throw e }
                    default:
                        break
                    }
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
            if let lastError { throw lastError }
            throw BeerAPIError.server("Serveur injoignable en 4G/5G")
        }
        var lastError: Error?
        let saved = baseURL.absoluteString
        for candidate in ServerSettings.candidateURLs {
            do {
                setBaseURL(candidate)
                var req = URLRequest(url: absURL(clean))
                req.httpMethod = method
                if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
                req.httpBody = body
                let (data, _, http, u) = try await execute(req)
                return (data, http, u)
            } catch {
                lastError = error
            }
        }
        setBaseURL(saved)
        if let lastError { throw lastError }
        throw BeerAPIError.allEndpointsFailed(
            "Serveur injoignable. Wi‑Fi maison ou VPN Plexi requis pour les comptes."
        )
    }

    private func performTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        let (data, _, http, u) = try await execute(request)
        return (data, http, u)
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