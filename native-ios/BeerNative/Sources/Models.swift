import Foundation

struct MeResponse: Decodable {
    let user: String?
    let auth: Bool
    let isAdmin: Bool
    let isInvite: Bool

    enum CodingKeys: String, CodingKey {
        case user, auth
        case isAdmin = "is_admin"
        case isInvite = "is_invite"
    }
}

struct LoginResponse: Decodable {
    let ok: Bool
    let user: String?
    let isAdmin: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, user, error
        case isAdmin = "is_admin"
    }
}

struct BeerProduct: Codable, Equatable {
    var ok: Bool = true
    var barcode: String = ""
    var beerName: String = ""
    var brewery: String = ""
    var style: String = "Unknown"
    var styleFr: String?
    var abv: Double?
    var summary: String = ""
    var untappdBid: Int?
    var source: String?
    var photoURL: String?

    enum CodingKeys: String, CodingKey {
        case ok, barcode, brewery, style, abv, summary, source
        case beerName = "beer_name"
        case styleFr = "style_fr"
        case untappdBid = "untappd_bid"
        case photoURL = "photo_url"
    }

    var displayStyle: String { styleFr ?? style }
}

struct LookupResponse: Decodable {
    let ok: Bool
    let error: String?
    let barcode: String?
    let beerName: String?
    let brewery: String?
    let style: String?
    let styleFr: String?
    let abv: Double?
    let summary: String?
    let untappdBid: Int?
    let source: String?
    let photoURL: String?

    enum CodingKeys: String, CodingKey {
        case ok, error, barcode, brewery, style, abv, summary, source
        case beerName = "beer_name"
        case styleFr = "style_fr"
        case untappdBid = "untappd_bid"
        case photoURL = "photo_url"
    }

    func asProduct(fallbackBarcode: String) -> BeerProduct {
        BeerProduct(
            ok: ok,
            barcode: barcode ?? fallbackBarcode,
            beerName: beerName ?? "",
            brewery: brewery ?? "",
            style: style ?? "Unknown",
            styleFr: styleFr,
            abv: abv,
            summary: summary ?? "",
            untappdBid: untappdBid,
            source: source,
            photoURL: photoURL
        )
    }
}

struct CheckinItem: Identifiable, Decodable {
    let id: Int
    let beerName: String
    let brewery: String?
    let style: String?
    let rating: Double
    let comment: String?
    let barcode: String?
    let createdAt: String?
    let photoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, brewery, style, rating, comment, barcode
        case beerName = "beer_name"
        case createdAt = "created_at"
        case photoURL = "photo_url"
    }
}

struct PendingCheckin: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var barcode: String
    var beerName: String
    var brewery: String
    var style: String
    var abv: String
    var summary: String
    var rating: Double
    var comment: String
    var untappdBid: String
    var force: Bool
}

struct CreateCheckinResult: Decodable {
    let ok: Bool?
    let id: Int?
    let duplicate: Bool?
    let error: String?
}