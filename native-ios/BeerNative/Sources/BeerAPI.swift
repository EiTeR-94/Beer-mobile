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
    static let nativeClientHeader = "X-PlexiBeer-Client"
    static let nativeClientValue = "native-ios"
    static let userAgentOwner = "PlexiBeer/4.2.8 (iPhone; native owner) [lan-vpn]"
    static let userAgentInvite = "PlexiBeer/4.2.8 (iPhone; native invite) [wan]"

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

    func absURL(_ path: String) -> URL {
        let base = baseURL.absoluteString
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + p)!
    }

    private static let appVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    func applyHeaders(to req: inout URLRequest) {
        req.setValue(Self.nativeClientValue, forHTTPHeaderField: Self.nativeClientHeader)
        req.setValue(
            isInviteMode ? Self.userAgentInvite : Self.userAgentOwner,
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue(Self.appVersion, forHTTPHeaderField: "X-App-Version")
        req.setValue("ios", forHTTPHeaderField: "X-App-Platform")
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

    func beerSessionCookieString() -> String? {
        HTTPCookieStorage.shared.cookies?
            .first(where: { $0.name == "beer_session" })
            .map { "beer_session=\($0.value)" }
    }

    /// **Invite WAN = URLSession uniquement** (comme les join 200 en logs prod).
    /// PreferIPv4 force dial `82.64.151.113` (jamais AAAA Freebox).
    /// HomelabTLS accepte le cert LE du domaine sur l'IP.
    /// **Zéro** NWConnection / HomelabIPv4 — c'est ça qui jetait « Timeout 30s » en instantané.
    /// Owner LAN : URLSession + HomelabTLS inchangé.
    func execute(
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

    func finishHTTPInviteAware(
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
    func mapURLError(_ err: URLError, elapsed: TimeInterval, budget: TimeInterval) -> BeerAPIError {
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















































































    // MARK: - HTTP helpers (Android execute)

    func request(
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

    func performTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        let (data, _, http, u) = try await execute(request)
        return (data, http, u)
    }

    func throwIfUnauthorized(_ status: Int) throws {
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

    func url(_ path: String) throws -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: clean, relativeTo: baseURL) else {
            throw BeerAPIError.invalidURL
        }
        return url
    }

    func makeMultipart(
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