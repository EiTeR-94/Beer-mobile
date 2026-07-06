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

    static func from(checkin: CheckinItem) -> BeerProduct {
        BeerProduct(
            barcode: checkin.barcode ?? "",
            beerName: checkin.beerName,
            brewery: checkin.brewery ?? "—",
            style: checkin.style ?? "Unknown",
            summary: "\(checkin.beerName) — re-dégustation",
            untappdBid: checkin.untappdBid
        )
    }
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

struct CheckinItem: Identifiable, Decodable, Hashable {
    let id: Int
    let beerName: String
    let brewery: String?
    let style: String?
    let rating: Double
    let comment: String?
    let barcode: String?
    let createdAt: String?
    let photoURL: String?
    let flavors: [String]?
    let hops: [String]?
    let hiddenFromPartner: Bool?
    let untappdBid: Int?

    enum CodingKeys: String, CodingKey {
        case id, brewery, style, rating, comment, barcode, flavors, hops
        case beerName = "beer_name"
        case createdAt = "created_at"
        case photoURL = "photo_url"
        case hiddenFromPartner = "hidden_from_partner"
        case untappdBid = "untappd_bid"
    }
}

struct HistoryStats: Decodable {
    let total: Int
    let avgRating: Double?
    let topStyles: [TopStyle]?
    let last: LastCheckin?

    enum CodingKeys: String, CodingKey {
        case total, last
        case avgRating = "avg_rating"
        case topStyles = "top_styles"
    }

    struct TopStyle: Decodable {
        let style: String?
        let count: Int?
    }

    struct LastCheckin: Decodable {
        let beerName: String?
        enum CodingKeys: String, CodingKey { case beerName = "beer_name" }
    }
}

struct StyleOption: Decodable, Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct WishlistItem: Identifiable, Decodable {
    let id: Int
    let beerName: String
    let brewery: String?
    let style: String?
    let barcode: String?
    let note: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, brewery, style, barcode, note
        case beerName = "beer_name"
        case createdAt = "created_at"
    }
}

struct GiftIdea: Identifiable, Decodable {
    let id: String
    let beerName: String
    let brewery: String?
    let style: String?
    let rating: Double?
    let comment: String?
    let photoPath: String?
    let createdAt: String?
    let likedBy: String?
    let forUser: String?

    enum CodingKeys: String, CodingKey {
        case brewery, style, rating, comment
        case beerName = "beer_name"
        case photoPath = "photo_path"
        case createdAt = "created_at"
        case likedBy = "liked_by"
        case forUser = "for"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        beerName = try c.decode(String.self, forKey: .beerName)
        brewery = try c.decodeIfPresent(String.self, forKey: .brewery)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        likedBy = try c.decodeIfPresent(String.self, forKey: .likedBy)
        forUser = try c.decodeIfPresent(String.self, forKey: .forUser)
        id = "\(beerName)-\(likedBy ?? "")-\(createdAt ?? "")"
    }
}

struct CoupleStats: Decodable {
    let users: [CoupleUser]?
    let giftIdeas: [GiftIdea]?

    enum CodingKeys: String, CodingKey {
        case users
        case giftIdeas = "gift_ideas"
    }

    struct CoupleUser: Decodable, Identifiable {
        let username: String
        let total: Int
        var id: String { username }
    }
}

struct AdminUser: Identifiable, Decodable {
    let username: String
    let isAdmin: Bool
    let checkins: Int
    let createdAt: String?

    var id: String { username }

    enum CodingKeys: String, CodingKey {
        case username, checkins
        case isAdmin = "is_admin"
        case createdAt = "created_at"
    }
}

struct InviteItem: Identifiable, Decodable {
    let id: Int
    let label: String?
    let username: String?
    let url: String?
    let expiresAt: String?
    let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, username, url, active
        case expiresAt = "expires_at"
    }
}

struct PatchnotesResponse: Decodable {
    let version: String?
    let markdown: String?
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

struct UntappdSearchResponse: Decodable {
    let ok: Bool
    let error: String?
    let results: [UntappdHit]?
}

struct UntappdHit: Decodable, Identifiable {
    let bid: Int
    let beerName: String
    let brewery: String?
    let styleFr: String?
    let photoURL: String?

    var id: Int { bid }

    enum CodingKeys: String, CodingKey {
        case bid, brewery
        case beerName = "beer_name"
        case styleFr = "style_fr"
        case photoURL = "photo_url"
    }
}

struct FlavorsResponse: Decodable {
    let flavors: [String]?
    let suggestedFlavors: [String]?
    let hops: [String]?
    let suggestedHops: [String]?
    let showFlavorsBlock: Bool?
    let showHopsBlock: Bool?

    enum CodingKeys: String, CodingKey {
        case flavors, hops
        case suggestedFlavors = "suggested_flavors"
        case suggestedHops = "suggested_hops"
        case showFlavorsBlock = "show_flavors_block"
        case showHopsBlock = "show_hops_block"
    }
}

struct OKResponse: Decodable {
    let ok: Bool?
    let error: String?
}