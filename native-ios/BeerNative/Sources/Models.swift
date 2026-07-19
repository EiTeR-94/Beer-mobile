import Foundation

struct MeResponse: Decodable {
    let user: String?
    let auth: Bool?
    let isAdmin: Bool?
    let isInvite: Bool?

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

struct NativeJoinResponse: Decodable {
    let ok: Bool
    let accessToken: String?
    let user: String?
    let label: String?
    let isInvite: Bool?
    let deviceId: String?
    let expiresAt: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, user, label, error
        case accessToken = "access_token"
        case isInvite = "is_invite"
        case deviceId = "device_id"
        case expiresAt = "expires_at"
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

struct CheckinItem: Identifiable, Codable, Hashable {
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
    /// Lieu / lien où la bière a été dégustée (optionnel).
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id, brewery, style, rating, comment, barcode, flavors, hops, location
        case beerName = "beer_name"
        case createdAt = "created_at"
        case photoURL = "photo_url"
        case hiddenFromPartner = "hidden_from_partner"
        case untappdBid = "untappd_bid"
    }
}

struct HistoryStats: Codable {
    let total: Int
    let avgRating: Double?
    let topStyles: [TopStyle]?
    let last: LastCheckin?

    enum CodingKeys: String, CodingKey {
        case total, last
        case avgRating = "avg_rating"
        case topStyles = "top_styles"
    }

    struct TopStyle: Codable {
        let style: String?
        let count: Int?
    }

    struct LastCheckin: Codable {
        let beerName: String?
        enum CodingKeys: String, CodingKey { case beerName = "beer_name" }
    }
}

struct StyleOption: Codable, Identifiable {
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

struct GiftIdea: Identifiable, Codable {
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(beerName, forKey: .beerName)
        try c.encodeIfPresent(brewery, forKey: .brewery)
        try c.encodeIfPresent(style, forKey: .style)
        try c.encodeIfPresent(rating, forKey: .rating)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(photoPath, forKey: .photoPath)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(likedBy, forKey: .likedBy)
        try c.encodeIfPresent(forUser, forKey: .forUser)
    }
}

struct CoupleStats: Codable {
    let users: [CoupleUser]?
    let giftIdeas: [GiftIdea]?

    enum CodingKeys: String, CodingKey {
        case users
        case giftIdeas = "gift_ideas"
    }

    struct CoupleUser: Codable, Identifiable {
        let username: String
        let total: Int
        var id: String { username }
    }
}

struct AdminUser: Identifiable, Codable {
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

struct InviteClientProfile: Codable {
    let browser: String?
    let os: String?
    let device: String?

    var isKnown: Bool {
        guard let browser, browser != "—", !browser.isEmpty else { return false }
        return true
    }
}

struct InviteItem: Identifiable, Codable {
    let id: Int
    let label: String?
    let username: String?
    let url: String?
    let createdAt: String?
    let expiresAt: String?
    let linkExpiresAt: String?
    let active: Bool?
    let linkActive: Bool?
    let revokedAt: String?
    let redeemedAt: String?
    let lastUsedAt: String?
    let reactivationPending: Bool?
    let canExtend: Bool?
    let canReissue: Bool?
    let permanent: Bool?
    let validityLabel: String?
    let checkins: Int?
    let redeemIp: String?
    let lastUsedIp: String?
    let deviceShort: String?
    let redeemClient: InviteClientProfile?
    let lastClient: InviteClientProfile?
    let ipLog: [InviteIpEntry]?
    let emailHint: String?
    let emailRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, username, url, active, permanent, checkins
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case linkExpiresAt = "link_expires_at"
        case linkActive = "link_active"
        case revokedAt = "revoked_at"
        case redeemedAt = "redeemed_at"
        case lastUsedAt = "last_used_at"
        case reactivationPending = "reactivation_pending"
        case canExtend = "can_extend"
        case canReissue = "can_reissue"
        case validityLabel = "validity_label"
        case redeemIp = "redeem_ip"
        case lastUsedIp = "last_used_ip"
        case deviceShort = "device_short"
        case redeemClient = "redeem_client"
        case lastClient = "last_client"
        case ipLog = "ip_log"
        case emailHint = "email_hint"
        case emailRequired = "email_required"
    }

    var statusText: String {
        if revokedAt != nil { return "Révoquée" }
        if reactivationPending == true { return "Réactivation" }
        if redeemedAt != nil { return "Utilisée · lien mort" }
        if active == false { return "Expirée" }
        if linkActive == false { return "Lien expiré" }
        return "En attente"
    }
}

struct CreateInviteResponse: Decodable {
    let ok: Bool?
    let url: String?
    let error: String?
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
    var flavors: [String]
    var hops: [String]
    var comment: String
    var untappdBid: String
    var force: Bool
    var photoJPEGBase64: String?
    /// Lieu / lien de dégustation (optionnel). Optional for legacy offline queue JSON.
    var location: String? = nil
}

struct PreviousCheckin: Decodable {
    let beerName: String?
    let rating: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case rating
        case beerName = "beer_name"
        case createdAt = "created_at"
    }
}

struct CreateCheckinResult: Decodable {
    let ok: Bool?
    let id: Int?
    let duplicate: Bool?
    let error: String?
    let previousCheckin: PreviousCheckin?
    let rpg: RpgLoot?

    enum CodingKeys: String, CodingKey {
        case ok, id, duplicate, error, rpg
        case previousCheckin = "previous_checkin"
    }
}

struct DecodeBarcodeResponse: Decodable {
    let ok: Bool
    let barcode: String?
    let error: String?
}

struct ReferentialEntry: Codable, Identifiable {
    let name: String
    let preset: Bool?
    let deletable: Bool?
    var id: String { name }
}

struct ReferentialsResponse: Codable {
    let styles: [ReferentialEntry]?
    let hops: [ReferentialEntry]?
    let flavors: [ReferentialEntry]?
}

struct InviteIpEntry: Codable {
    let ip: String?
    let firstSeen: String?
    let lastSeen: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
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

// (legacy structs removed)