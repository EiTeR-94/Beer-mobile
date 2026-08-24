import Foundation

extension BeerAPI {
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
}
