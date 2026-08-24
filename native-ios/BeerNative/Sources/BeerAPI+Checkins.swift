import Foundation

extension BeerAPI {
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
        location: String? = nil,
        locationLat: Double? = nil,
        locationLon: Double? = nil,
        locationOsmId: String? = nil
    ) async throws {
        var payload: [String: Any] = [:]
        if let rating { payload["rating"] = rating }
        if let flavors { payload["flavors"] = flavors }
        if let hops { payload["hops"] = hops }
        if let comment { payload["comment"] = comment }
        if let location {
            payload["location"] = location
            // Trio solidaire (cf. backend update_checkin) : le lieu et ses
            // coordonnées sont toujours envoyés ensemble — omis = pas de lieu réel.
            if let locationLat { payload["location_lat"] = locationLat }
            if let locationLon { payload["location_lon"] = locationLon }
            if let locationOsmId { payload["location_osm_id"] = locationOsmId }
        }
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
        location: String = "",
        locationLat: String = "",
        locationLon: String = "",
        locationOsmId: String = ""
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
                "location_lat": locationLat,
                "location_lon": locationLon,
                "location_osm_id": locationOsmId,
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
}
