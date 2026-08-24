import Foundation

extension BeerAPI {
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
    func styles() async throws -> [StyleOption] {
        let (data, http, _) = try await request(path: "/api/styles", method: "GET", body: nil)
        // pas de throw unauthorized ici pour éviter clear/toast sur appel non critique
        if http.statusCode == 401 { return [] }
        return (try? JSONDecoder().decode([StyleOption].self, from: data)) ?? []
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
    func geocodeSearch(query: String, lat: Double? = nil, lon: Double? = nil) async throws -> GeocodeSearchResponse {
        var components = URLComponents(url: try url("/api/geocode/search"), resolvingAgainstBaseURL: true)!
        var items = [URLQueryItem(name: "q", value: query)]
        if let lat { items.append(URLQueryItem(name: "lat", value: String(lat))) }
        if let lon { items.append(URLQueryItem(name: "lon", value: String(lon))) }
        components.queryItems = items
        var req = URLRequest(url: components.url!)
        return try await NetworkManager.shared.withRetry {
            let (data, http, _) = try await performTransport(req)
            try throwIfUnauthorized(http.statusCode)
            guard let decoded = try? JSONDecoder().decode(GeocodeSearchResponse.self, from: data) else {
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
}
