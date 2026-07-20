import Foundation

struct RpgState: Decodable {
    var enabled: Bool?
    var ui: Bool?
    var allowed: Bool?
    var profile: RpgProfile?
    var quests: RpgQuests?
    var badges: [RpgBadge]?
    var nextBadges: [RpgBadge]?
    var atlas: RpgAtlas?
    var classes: [RpgClassInfo]?
    var classAffinity: [String: Int]?
    var phrase: String?

    enum CodingKeys: String, CodingKey {
        case enabled, ui, allowed, profile, quests, badges, atlas, classes, phrase
        case nextBadges = "next_badges"
        case classAffinity = "class_affinity"
    }

    var active: Bool {
        enabled == true && ui == true && profile != nil
    }
}

struct RpgProfile: Decodable {
    var username: String?
    var level: Int?
    var xp: Int?
    var title: String?
    var progressPct: Double?
    var xpToNext: Int?
    var xpIntoLevel: Int?
    var xpLevelStart: Int?
    var xpLevelNext: Int?
    var streakDays: Int?
    var dailyXp: Int?
    var dailySoftCap: Int?
    var dailySoftCapped: Bool?
    var dailySoftCapRemaining: Int?
    var classKey: String?
    var classInfo: RpgClassInfo?
    var beerMaster: Bool?
    var prestige: RpgPrestige?
    var titleBand: RpgTitleBand?
    var introSeen: Bool?

    enum CodingKeys: String, CodingKey {
        case username, level, xp, title, prestige
        case progressPct = "progress_pct"
        case xpToNext = "xp_to_next"
        case xpIntoLevel = "xp_into_level"
        case xpLevelStart = "xp_level_start"
        case xpLevelNext = "xp_level_next"
        case streakDays = "streak_days"
        case dailyXp = "daily_xp"
        case dailySoftCap = "daily_soft_cap"
        case dailySoftCapped = "daily_soft_capped"
        case dailySoftCapRemaining = "daily_soft_cap_remaining"
        case classKey = "class"
        case classInfo = "class_info"
        case beerMaster = "beer_master"
        case titleBand = "title_band"
        case introSeen = "intro_seen"
    }

    var displayIcon: String {
        if beerMaster == true { return prestige?.icon ?? "👑" }
        return classInfo?.icon ?? "🍺"
    }
}

struct RpgClassInfo: Decodable, Identifiable {
    var key: String?
    var name: String?
    var icon: String?
    var blurb: String?
    var whenText: String?
    var special: String?
    var id: String { key ?? name ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case key, name, icon, blurb, special
        case whenText = "when"
    }
}

struct RpgPrestige: Decodable {
    var key: String?
    var icon: String?
    var ribbon: String?
    var tagline: String?
    var blurb: String?
}

struct RpgTitleBand: Decodable {
    var name: String?
    var fromLevel: Int?
    var to: Int?
    enum CodingKeys: String, CodingKey {
        case name, to
        case fromLevel = "from"
    }
}

struct RpgQuests: Decodable {
    var active: [RpgQuest]?
    var doneToday: [RpgQuest]?
    var doneWeekly: [RpgQuest]?
    enum CodingKeys: String, CodingKey {
        case active
        case doneToday = "done_today"
        case doneWeekly = "done_weekly"
    }
}

struct RpgQuest: Decodable, Identifiable {
    var key: String?
    var kind: String?
    var title: String?
    var description: String?
    var progress: Int?
    var target: Int?
    var status: String?
    var rewardXp: Int?
    var id: String { key ?? title ?? UUID().uuidString }
    enum CodingKeys: String, CodingKey {
        case key, kind, title, description, progress, target, status
        case rewardXp = "reward_xp"
    }
}

struct RpgBadge: Decodable, Identifiable {
    var key: String?
    var name: String?
    var icon: String?
    var rarity: String?
    var lore: String?
    var hint: String?
    var earned: Bool?
    var earnedAt: String?
    var progress: Int?
    var target: Int?
    var remaining: Int?
    var unlockPhrase: String?
    var id: String { key ?? name ?? UUID().uuidString }
    enum CodingKeys: String, CodingKey {
        case key, name, icon, rarity, lore, hint, earned, progress, target, remaining
        case earnedAt = "earned_at"
        case unlockPhrase = "unlock_phrase"
    }
}

struct RpgAtlas: Decodable {
    var stylesCount: Int?
    var hopsCount: Int?
    var breweriesCount: Int?
    var photos: Int?
    var totalCheckins: Int?
    var styles: [String]?
    enum CodingKeys: String, CodingKey {
        case photos, styles
        case stylesCount = "styles_count"
        case hopsCount = "hops_count"
        case breweriesCount = "breweries_count"
        case totalCheckins = "total_checkins"
    }
}

struct RpgLoot: Decodable {
    var xpGained: Int?
    var xp: Int?
    var level: Int?
    var levelUp: Bool?
    var oldLevel: Int?
    var levelsGained: Int?
    var title: String?
    var oldTitle: String?
    var titleChanged: Bool?
    var progressPct: Double?
    var xpToNext: Int?
    var phrase: String?
    var phraseLevelUp: String?
    var badgesEarned: [RpgBadge]?
    var questsCompleted: [RpgQuest]?
    var nextBadges: [RpgBadge]?
    var streakDays: Int?
    var dailyXp: Int?
    var dailySoftCap: Int?
    var dailySoftCapped: Bool?
    var dailySoftCapJustHit: Bool?
    var softCapMessage: String?
    enum CodingKeys: String, CodingKey {
        case xp, level, title, phrase
        case xpGained = "xp_gained"
        case levelUp = "level_up"
        case oldLevel = "old_level"
        case levelsGained = "levels_gained"
        case oldTitle = "old_title"
        case titleChanged = "title_changed"
        case progressPct = "progress_pct"
        case xpToNext = "xp_to_next"
        case phraseLevelUp = "phrase_level_up"
        case badgesEarned = "badges_earned"
        case questsCompleted = "quests_completed"
        case nextBadges = "next_badges"
        case streakDays = "streak_days"
        case dailyXp = "daily_xp"
        case dailySoftCap = "daily_soft_cap"
        case dailySoftCapped = "daily_soft_capped"
        case dailySoftCapJustHit = "daily_soft_cap_just_hit"
        case softCapMessage = "soft_cap_message"
    }
}

// MARK: - Célébrations / intro

enum RpgCelebration: Identifiable, Equatable {
    case levelUp(RpgLoot)
    case badge(RpgBadge)

    var id: String {
        switch self {
        case .levelUp(let loot):
            return "lvl-\(loot.level ?? 0)-\(loot.oldLevel ?? 0)-\(loot.xp ?? 0)"
        case .badge(let b):
            return "badge-\(b.key ?? b.name ?? UUID().uuidString)"
        }
    }

    static func == (lhs: RpgCelebration, rhs: RpgCelebration) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Admin Beerquest (liste joueurs)

struct RpgAdminPlayersResponse: Decodable {
    var players: [RpgAdminPlayer]?
    var total: Int?
    var withProfile: Int?
    enum CodingKeys: String, CodingKey {
        case players, total
        case withProfile = "with_profile"
    }
}

struct RpgAdminPlayer: Decodable, Identifiable {
    var username: String?
    var level: Int?
    var xp: Int?
    var title: String?
    var streakDays: Int?
    var classKey: String?
    var classInfo: RpgClassInfo?
    var beerMaster: Bool?
    var isAdmin: Bool?
    var isInvite: Bool?
    var checkins: Int?
    var badgeCount: Int?
    var allowed: Bool?
    var hasProfile: Bool?
    var progressPct: Double?
    var suspicionScore: Int?
    var suspicionFlagged: Bool?
    var orphan: Bool?
    var introSeen: Bool?
    var backfilled: Bool?
    var dailyXpTotal: Int?
    var dailyXpCount: Int?
    var dailySoftCap: Int?
    var dailyXpToday: Int?
    var dailyCheckinsToday: Int?
    var dailySoftCapped: Bool?
    var dailySoftCapRemaining: Int?
    var lastRpgCheckinAt: String?
    var id: String { username ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case username, level, xp, title, checkins, allowed, orphan
        case streakDays = "streak_days"
        case classKey = "class"
        case classInfo = "class_info"
        case beerMaster = "beer_master"
        case isAdmin = "is_admin"
        case isInvite = "is_invite"
        case badgeCount = "badge_count"
        case hasProfile = "has_profile"
        case progressPct = "progress_pct"
        case suspicionScore = "suspicion_score"
        case suspicionFlagged = "suspicion_flagged"
        case introSeen = "intro_seen"
        case backfilled
        case dailyXpTotal = "daily_xp_total"
        case dailyXpCount = "daily_xp_count"
        case dailySoftCap = "daily_soft_cap"
        case dailyXpToday = "daily_xp_today"
        case dailyCheckinsToday = "daily_checkins_today"
        case dailySoftCapped = "daily_soft_capped"
        case dailySoftCapRemaining = "daily_soft_cap_remaining"
        case lastRpgCheckinAt = "last_rpg_checkin_at"
    }
}

/// GET/PATCH /api/admin/rpg/players/{user} — détail complet
struct RpgAdminPlayerDetail: Decodable {
    var player: RpgAdminPlayer?
    var badges: [RpgBadge]?
    var quests: [RpgAdminQuest]?
    var events: [RpgAdminEvent]?
    var atlas: RpgAtlas?
    var classAffinity: [String: Int]?
    var classes: [RpgClassInfo]?
    var catalogBadges: [RpgBadge]?

    enum CodingKeys: String, CodingKey {
        case player, badges, quests, events, atlas, classes
        case classAffinity = "class_affinity"
        case catalogBadges = "catalog_badges"
    }
}

struct RpgAdminQuest: Decodable, Identifiable {
    var key: String?
    var kind: String?
    var title: String?
    var status: String?
    var progress: Int?
    var target: Int?
    var rewardXp: Int?
    var periodKey: String?
    var id: String { "\(key ?? "")-\(periodKey ?? "")-\(title ?? UUID().uuidString)" }
    enum CodingKeys: String, CodingKey {
        case key, kind, title, status, progress, target
        case rewardXp = "reward_xp"
        case periodKey = "period_key"
    }
}

struct RpgAdminEvent: Decodable, Identifiable {
    var kind: String?
    var createdAt: String?
    var id: String { "\(kind ?? "")-\(createdAt ?? UUID().uuidString)" }
    enum CodingKeys: String, CodingKey {
        case kind
        case createdAt = "created_at"
    }
}

struct RpgAdminBadgeActionResponse: Decodable {
    var ok: Bool?
    var granted: Bool?
    var removed: Bool?
    var player: RpgAdminPlayerDetail?
}

/// Manifest portail `/mobile/beer/versions.json` — versions natives publiées.
struct MobileVersionsManifest: Decodable {
    var ios: String?
    var iosBuild: String?
    var android: String?
    var androidBuild: String?
    var webapp: String?
    var updatedAt: String?
    var portalUrl: String?

    enum CodingKeys: String, CodingKey {
        case ios, android, webapp
        case iosBuild = "ios_build"
        case androidBuild = "android_build"
        case updatedAt = "updated_at"
        case portalUrl = "portal_url"
    }
}

struct AdminFeedbackStats: Decodable {
    var total: Int?
    var unread: Int?
    var open: Int?
    var done: Int?
    var rejected: Int?
}

struct AdminFeedbackListResponse: Decodable {
    var items: [AdminFeedbackItem]?
    var stats: AdminFeedbackStats?
}

struct FeedbackRepliesResponse: Decodable {
    var ok: Bool?
    var items: [AdminFeedbackItem]?
    var count: Int?
}

struct AdminFeedbackItem: Decodable, Identifiable {
    var id: Int?
    var message: String?
    var category: String?
    var categoryLabel: String?
    var username: String?
    var isInvite: Bool?
    var adminRead: Bool?
    var createdAt: String?
    var clientIp: String?
    var appVersion: String?
    var device: String?
    var osName: String?
    var browser: String?
    var pagePath: String?
    var meta: [String: FlexibleJSON]?
    var status: String?
    var statusLabel: String?
    var adminReply: String?
    var resolvedAt: String?
    var resolvedBy: String?
    var userSeenReply: Bool?

    enum CodingKeys: String, CodingKey {
        case id, message, category, username, device, browser, meta, status
        case categoryLabel = "category_label"
        case isInvite = "is_invite"
        case adminRead = "admin_read"
        case createdAt = "created_at"
        case clientIp = "client_ip"
        case appVersion = "app_version"
        case osName = "os_name"
        case pagePath = "page_path"
        case statusLabel = "status_label"
        case adminReply = "admin_reply"
        case resolvedAt = "resolved_at"
        case resolvedBy = "resolved_by"
        case userSeenReply = "user_seen_reply"
    }

    /// Identifiant stable pour ForEach
    var stableId: Int { id ?? 0 }

    var displayCategory: String {
        let lab = (categoryLabel ?? "").trimmingCharacters(in: .whitespaces)
        if !lab.isEmpty { return lab }
        return category ?? "général"
    }

    var displayStatus: String {
        let lab = (statusLabel ?? "").trimmingCharacters(in: .whitespaces)
        if !lab.isEmpty { return lab }
        switch (status ?? "open").lowercased() {
        case "done": return "Mis en place"
        case "rejected": return "Refusé"
        default: return "En cours"
        }
    }

    var isOpen: Bool { (status ?? "open").lowercased() == "open" || status == nil || status?.isEmpty == true }
    var isDone: Bool { (status ?? "").lowercased() == "done" }
    var isRejected: Bool { (status ?? "").lowercased() == "rejected" }

    var deviceLine: String {
        [device, osName, browser]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }

    var metaRpgLevel: String? {
        guard let m = meta, let v = m["rpg_level"] else { return nil }
        switch v {
        case .int(let i): return "Lv \(i)"
        case .double(let d): return "Lv \(Int(d))"
        case .string(let s) where !s.isEmpty: return "Lv \(s)"
        default: return nil
        }
    }
}

/// JSON hétérogène pour meta feedback (int/string/bool…).
enum FlexibleJSON: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .other
    }
}

/// Compare versions "4.4.7" style. -1 si a<b, 0 égal, 1 si a>b.
func beerVersionCompare(_ a: String, _ b: String) -> Int {
    func extract(_ s: String) -> [Int] {
        // digits and dots only, first sequence
        var buf = ""
        var started = false
        for ch in s {
            if ch.isNumber {
                buf.append(ch)
                started = true
            } else if ch == "." && started {
                buf.append(ch)
            } else if started {
                break
            }
        }
        return buf.split(separator: ".").compactMap { Int($0) }
    }
    let pa = extract(a)
    let pb = extract(b)
    let n = max(pa.count, pb.count)
    for i in 0..<n {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x < y { return -1 }
        if x > y { return 1 }
    }
    return 0
}

func rarityLabelFr(_ r: String?) -> String {
    switch (r ?? "common").lowercased() {
    case "legendary": return "Légendaire"
    case "epic": return "Épique"
    case "rare": return "Rare"
    default: return "Commun"
    }
}
