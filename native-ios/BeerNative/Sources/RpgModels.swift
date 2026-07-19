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
    var classKey: String?
    var classInfo: RpgClassInfo?
    var beerMaster: Bool?
    var prestige: RpgPrestige?
    var titleBand: RpgTitleBand?

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
        case classKey = "class"
        case classInfo = "class_info"
        case beerMaster = "beer_master"
        case titleBand = "title_band"
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
    var id: String { key ?? name ?? UUID().uuidString }
    enum CodingKeys: String, CodingKey {
        case key, name, icon, rarity, lore, hint, earned, progress, target, remaining
        case earnedAt = "earned_at"
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
    var title: String?
    var progressPct: Double?
    var xpToNext: Int?
    var phrase: String?
    var phraseLevelUp: String?
    var badgesEarned: [RpgBadge]?
    var questsCompleted: [RpgQuest]?
    var nextBadges: [RpgBadge]?
    var streakDays: Int?
    enum CodingKeys: String, CodingKey {
        case xp, level, title, phrase
        case xpGained = "xp_gained"
        case levelUp = "level_up"
        case oldLevel = "old_level"
        case progressPct = "progress_pct"
        case xpToNext = "xp_to_next"
        case phraseLevelUp = "phrase_level_up"
        case badgesEarned = "badges_earned"
        case questsCompleted = "quests_completed"
        case nextBadges = "next_badges"
        case streakDays = "streak_days"
    }
}

func rarityLabelFr(_ r: String?) -> String {
    switch (r ?? "common").lowercased() {
    case "legendary": return "Légendaire"
    case "epic": return "Épique"
    case "rare": return "Rare"
    default: return "Commun"
    }
}
