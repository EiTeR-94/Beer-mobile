import Foundation

enum BeerAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case network(Error)
    case decode
    case allEndpointsFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL API invalide"
        case .unauthorized: return "Session expirée — reconnecte-toi"
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        case .decode: return "Réponse serveur illisible"
        case .allEndpointsFailed(let detail): return detail
        }
    }
}

final class BeerAPI {
    static let shared = BeerAPI()

    private let session: URLSession
    private(set) var baseURL: URL
    private(set) var activeEndpoint: String = ""

    init(baseURL: URL = ServerSettings.apiBase) {
        self.baseURL = Self.canonicalBase(baseURL)
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(
            configuration: config,
            delegate: HomelabTLSDelegate.shared,
            delegateQueue: nil
        )
    }

    func setBaseURL(_ url: URL) {
        baseURL = Self.canonicalBase(url)
        activeEndpoint = baseURL.absoluteString
    }

    func healthCheck() async throws -> Bool {
        let (_, http, _) = try await request(path: "/api/health", method: "GET", body: nil)
        return http.statusCode == 200
    }

    func discoverWorkingEndpoint() async -> String? {
        for url in ServerSettings.candidateURLs {
            baseURL = Self.canonicalBase(url)
            do {
                if try await healthCheck() {
                    activeEndpoint = url.absoluteString
                    return url.absoluteString
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let (data, http, _) = try await request(
            path: "/api/login",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode == 403 {
            throw BeerAPIError.server("Accès refusé — Wi‑Fi maison ou VPN Plexi requis")
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
        return decoded
    }

    func me() async throws -> MeResponse {
        let (data, http, _) = try await request(path: "/api/me", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func logout() async {
        _ = try? await request(path: "/api/logout", method: "POST", body: nil)
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
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
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode([CheckinItem].self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func stats() async throws -> HistoryStats {
        let (data, http, _) = try await request(path: "/api/stats", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(HistoryStats.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func coupleStats() async throws -> CoupleStats {
        let (data, http, _) = try await request(path: "/api/stats/couple", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(CoupleStats.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func styles() async throws -> [StyleOption] {
        let (data, http, _) = try await request(path: "/api/styles", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        return (try? JSONDecoder().decode([StyleOption].self, from: data)) ?? []
    }

    func version() async throws -> String {
        let (data, _, _) = try await request(path: "/api/version", method: "GET", body: nil)
        struct V: Decodable { let version: String? }
        return (try? JSONDecoder().decode(V.self, from: data))?.version ?? "?"
    }

    func patchnotes() async throws -> PatchnotesResponse {
        let (data, http, _) = try await request(path: "/api/admin/patchnotes", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(PatchnotesResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func wishlist() async throws -> [WishlistItem] {
        let (data, http, _) = try await request(path: "/api/wishlist", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Échec wishlist")
        }
    }

    func deleteWishlist(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/wishlist/\(id)", method: "DELETE", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func deleteCheckin(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/checkins/\(id)", method: "DELETE", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode >= 400 { throw BeerAPIError.server("Suppression impossible") }
    }

    func updateCheckin(
        id: Int,
        rating: Double?,
        flavors: [String]?,
        hops: [String]?,
        comment: String?,
        hiddenFromPartner: Bool?
    ) async throws {
        var payload: [String: Any] = [:]
        if let rating { payload["rating"] = rating }
        if let flavors { payload["flavors"] = flavors }
        if let hops { payload["hops"] = hops }
        if let comment { payload["comment"] = comment }
        if let hiddenFromPartner { payload["hidden_from_partner"] = hiddenFromPartner }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(
            path: "/api/checkins/\(id)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        let (_, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode >= 400 { throw BeerAPIError.server("Photo impossible") }
    }

    func removeCheckinPhoto(id: Int) async throws {
        let (_, http, _) = try await request(path: "/api/checkins/\(id)/photo", method: "DELETE", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
    }

    func adminUsers() async throws -> [AdminUser] {
        let (data, http, _) = try await request(path: "/api/admin/users", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 { throw BeerAPIError.unauthorized }
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
        if http.statusCode == 401 || http.statusCode == 403 { throw BeerAPIError.unauthorized }
        return (try? JSONDecoder().decode([InviteItem].self, from: data)) ?? []
    }

    func adminCreateInvite(label: String, validity: String = "7d") async throws -> CreateInviteResponse {
        let body = try JSONSerialization.data(withJSONObject: ["label": label, "validity": validity])
        let (data, http, _) = try await request(path: "/api/invites", method: "POST", body: body, contentType: "application/json")
        guard let decoded = try? JSONDecoder().decode(CreateInviteResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode >= 400 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Invitation impossible")
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
        guard let resolved = ServerSettings.resolveAssetURL(pathOrURL, base: baseURL) else {
            throw BeerAPIError.invalidURL
        }
        var req = URLRequest(url: resolved)
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode != 200 { throw BeerAPIError.server("Fichier HTTP \(http.statusCode)") }
        return data
    }

    func untappdSearch(query: String) async throws -> UntappdSearchResponse {
        var components = URLComponents(url: try url("/api/untappd/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var req = URLRequest(url: components.url!)
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(UntappdSearchResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
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
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        if http.statusCode == 401 || http.statusCode == 403 { throw BeerAPIError.unauthorized }
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
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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
        photoJPEG: Data? = nil
    ) async throws -> CreateCheckinResult {
        let boundary = "BeerBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/checkins"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let flavorJSON = (try? String(data: JSONEncoder().encode(flavors), encoding: .utf8)) ?? "[]"
        let hopsJSON = (try? String(data: JSONEncoder().encode(hops), encoding: .utf8)) ?? "[]"
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
                "untappd_bid": untappdBid,
                "force": force ? "true" : "false",
            ],
            file: photoJPEG.map { ("photo", "photo.jpg", "image/jpeg", $0) }
        )
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
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

    private func request(
        path: String,
        method: String,
        body: Data?,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var lastError: Error?
        for candidate in ServerSettings.candidateURLs {
            baseURL = Self.canonicalBase(candidate)
            var req = URLRequest(url: try url(path))
            req.httpMethod = method
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            req.httpBody = body
            do {
                let result = try await perform(req)
                activeEndpoint = candidate.absoluteString
                return result
            } catch {
                lastError = error
            }
        }
        let tried = ServerSettings.candidateURLs.map(\.absoluteString).joined(separator: ", ")
        if let lastError { throw lastError }
        throw BeerAPIError.allEndpointsFailed(
            "Aucun serveur joignable (\(tried)). Active « Réseau local » pour Beer Log dans Réglages iPhone."
        )
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, let url = response.url else {
                throw BeerAPIError.decode
            }
            return (data, http, url)
        } catch let err as BeerAPIError {
            throw err
        } catch let err as URLError {
            switch err.code {
            case .cannotConnectToHost, .networkConnectionLost:
                throw BeerAPIError.server("Injoignable : \(baseURL.host ?? "?")")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                throw BeerAPIError.server("SSL refusé sur \(baseURL.host ?? "?")")
            case .timedOut:
                throw BeerAPIError.server("Timeout \(baseURL.host ?? "?")")
            case .notConnectedToInternet:
                throw BeerAPIError.server("Pas de réseau")
            default:
                throw BeerAPIError.network(err)
            }
        } catch {
            throw BeerAPIError.network(error)
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
}