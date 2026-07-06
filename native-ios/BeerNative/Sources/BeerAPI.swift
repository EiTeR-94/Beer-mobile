import Foundation

enum BeerAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case network(Error)
    case decode

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL API invalide"
        case .unauthorized: return "Session expirée — reconnecte-toi"
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        case .decode: return "Réponse serveur illisible"
        }
    }
}

final class BeerAPI {
    static let shared = BeerAPI()

    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = BuildConfig.apiBase) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    private func url(_ path: String) throws -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: clean, relativeTo: baseURL) else {
            throw BeerAPIError.invalidURL
        }
        return url
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BeerAPIError.decode }
            return (data, http)
        } catch let err as BeerAPIError {
            throw err
        } catch {
            throw BeerAPIError.network(error)
        }
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        var req = URLRequest(url: try url("/api/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        let (data, http) = try await data(for: req)
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        if http.statusCode == 401 || decoded.ok == false {
            throw BeerAPIError.server(decoded.error ?? "Identifiants incorrects")
        }
        return decoded
    }

    func me() async throws -> MeResponse {
        var req = URLRequest(url: try url("/api/me"))
        let (data, http) = try await data(for: req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(MeResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }

    func logout() async {
        var req = URLRequest(url: (try? url("/api/logout")) ?? baseURL)
        req.httpMethod = "POST"
        _ = try? await session.data(for: req)
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
    }

    func lookup(barcode: String) async throws -> LookupResponse {
        var req = URLRequest(url: try url("/api/lookup"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["barcode": barcode])
        let (data, http) = try await data(for: req)
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
        let (data, http) = try await data(for: req)
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
        let (data, http) = try await data(for: req)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        guard let decoded = try? JSONDecoder().decode(CreateCheckinResult.self, from: data) else {
            throw BeerAPIError.decode
        }
        if http.statusCode == 409 || decoded.duplicate == true {
            return decoded
        }
        if http.statusCode >= 400 {
            throw BeerAPIError.server(decoded.error ?? "Échec enregistrement")
        }
        return decoded
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

enum BuildConfig {
    static var apiBase: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "BEER_API_BASE") as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return URL(string: "https://localhost/beer")!
        }
        return url
    }
}