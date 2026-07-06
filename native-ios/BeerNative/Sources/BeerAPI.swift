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
                    ServerSettings.save(url.absoluteString)
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

    func checkins(limit: Int = 30, offset: Int = 0) async throws -> [CheckinItem] {
        var components = URLComponents(url: try url("/api/checkins"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        var req = URLRequest(url: components.url!)
        let (data, http, _) = try await perform(req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode([CheckinItem].self, from: data) else {
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
        comment: String,
        untappdBid: String,
        force: Bool
    ) async throws -> CreateCheckinResult {
        let boundary = "BeerBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/checkins"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
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
                "flavors": "[]",
                "hops": "[]",
                "comment": comment,
                "untappd_bid": untappdBid,
                "force": force ? "true" : "false",
            ]
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
            "Aucun serveur joignable (\(tried)). Active « Réseau local » pour Plexi Beer dans Réglages iPhone."
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

    private func makeMultipart(boundary: String, fields: [String: String]) -> Data {
        var body = Data()
        let nl = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(nl)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(nl)\(nl)".data(using: .utf8)!)
            body.append("\(value)\(nl)".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\(nl)".data(using: .utf8)!)
        return body
    }
}