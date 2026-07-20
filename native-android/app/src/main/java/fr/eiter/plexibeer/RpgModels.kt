package fr.eiter.plexibeer

import com.google.gson.annotations.SerializedName
import com.google.gson.JsonElement

/** GET /api/rpg/me */
data class RpgState(
    val enabled: Boolean = false,
    val ui: Boolean = false,
    val allowed: Boolean = false,
    val profile: RpgProfile? = null,
    val quests: RpgQuests? = null,
    val badges: List<RpgBadge> = emptyList(),
    @SerializedName("next_badges") val nextBadges: List<RpgBadge> = emptyList(),
    val atlas: RpgAtlas? = null,
    val classes: List<RpgClassInfo> = emptyList(),
    @SerializedName("class_affinity") val classAffinity: Map<String, Int>? = null,
    val phrase: String? = null
)

data class RpgProfile(
    val username: String? = null,
    val level: Int = 1,
    val xp: Int = 0,
    val title: String? = null,
    @SerializedName("progress_pct") val progressPct: Double = 0.0,
    @SerializedName("xp_to_next") val xpToNext: Int? = null,
    @SerializedName("xp_into_level") val xpIntoLevel: Int? = null,
    @SerializedName("xp_level_start") val xpLevelStart: Int? = null,
    @SerializedName("xp_level_next") val xpLevelNext: Int? = null,
    @SerializedName("streak_days") val streakDays: Int = 0,
    @SerializedName("daily_xp") val dailyXp: Int = 0,
    @SerializedName("daily_soft_cap") val dailySoftCap: Int = 100,
    @SerializedName("daily_soft_capped") val dailySoftCapped: Boolean = false,
    @SerializedName("daily_soft_cap_remaining") val dailySoftCapRemaining: Int? = null,
    @SerializedName("class") val classKey: String? = null,
    @SerializedName("class_info") val classInfo: RpgClassInfo? = null,
    @SerializedName("beer_master") val beerMaster: Boolean = false,
    val prestige: RpgPrestige? = null,
    @SerializedName("title_band") val titleBand: RpgTitleBand? = null,
    @SerializedName("intro_seen") val introSeen: Boolean = false
)

data class RpgClassInfo(
    val key: String? = null,
    val name: String? = null,
    val icon: String? = null,
    val blurb: String? = null,
    @SerializedName("when") val whenText: String? = null,
    val special: String? = null
)

data class RpgPrestige(
    val key: String? = null,
    val icon: String? = null,
    val ribbon: String? = null,
    val tagline: String? = null,
    val blurb: String? = null
)

data class RpgTitleBand(
    val name: String? = null,
    @SerializedName("from") val fromLevel: Int? = null,
    val to: Int? = null
)

data class RpgQuests(
    val active: List<RpgQuest> = emptyList(),
    @SerializedName("done_today") val doneToday: List<RpgQuest> = emptyList(),
    @SerializedName("done_weekly") val doneWeekly: List<RpgQuest> = emptyList()
)

data class RpgQuest(
    val key: String? = null,
    val kind: String? = null,
    val title: String? = null,
    val description: String? = null,
    val progress: Int = 0,
    val target: Int = 1,
    val status: String? = null,
    @SerializedName("reward_xp") val rewardXp: Int = 0
)

data class RpgBadge(
    val key: String? = null,
    val name: String? = null,
    val icon: String? = null,
    val rarity: String? = null,
    val lore: String? = null,
    val hint: String? = null,
    val earned: Boolean = false,
    @SerializedName("earned_at") val earnedAt: String? = null,
    val progress: Int = 0,
    val target: Int = 1,
    val remaining: Int? = null,
    @SerializedName("unlock_phrase") val unlockPhrase: String? = null
)

data class RpgAtlas(
    @SerializedName("styles_count") val stylesCount: Int = 0,
    @SerializedName("hops_count") val hopsCount: Int = 0,
    @SerializedName("breweries_count") val breweriesCount: Int = 0,
    val photos: Int = 0,
    @SerializedName("total_checkins") val totalCheckins: Int = 0,
    val styles: List<String>? = null
)

/** Bloc `rpg` renvoyé par POST /api/checkins */
data class RpgLoot(
    @SerializedName("xp_gained") val xpGained: Int = 0,
    val xp: Int = 0,
    val level: Int = 1,
    @SerializedName("level_up") val levelUp: Boolean = false,
    @SerializedName("old_level") val oldLevel: Int? = null,
    @SerializedName("levels_gained") val levelsGained: Int? = null,
    val title: String? = null,
    @SerializedName("old_title") val oldTitle: String? = null,
    @SerializedName("title_changed") val titleChanged: Boolean = false,
    @SerializedName("progress_pct") val progressPct: Double = 0.0,
    @SerializedName("xp_to_next") val xpToNext: Int? = null,
    val phrase: String? = null,
    @SerializedName("phrase_level_up") val phraseLevelUp: String? = null,
    @SerializedName("badges_earned") val badgesEarned: List<RpgBadge> = emptyList(),
    @SerializedName("quests_completed") val questsCompleted: List<RpgQuest> = emptyList(),
    @SerializedName("next_badges") val nextBadges: List<RpgBadge> = emptyList(),
    @SerializedName("streak_days") val streakDays: Int? = null,
    @SerializedName("daily_xp") val dailyXp: Int? = null,
    @SerializedName("daily_soft_cap") val dailySoftCap: Int? = null,
    @SerializedName("daily_soft_capped") val dailySoftCapped: Boolean = false,
    @SerializedName("daily_soft_cap_just_hit") val dailySoftCapJustHit: Boolean = false,
    @SerializedName("soft_cap_message") val softCapMessage: String? = null,
    /** breakdown items may be heterogeneous — keep as JsonElement list if needed */
    val breakdown: List<Map<String, JsonElement>>? = null
)

/** File de célébrations (level-up / badge). */
sealed class RpgCelebration {
    data class LevelUp(val loot: RpgLoot) : RpgCelebration()
    data class BadgeUnlock(val badge: RpgBadge) : RpgCelebration()
}

data class RpgAdminPlayersResponse(
    val players: List<RpgAdminPlayer> = emptyList(),
    val total: Int = 0,
    @SerializedName("with_profile") val withProfile: Int = 0
)

data class RpgAdminPlayer(
    val username: String? = null,
    val level: Int = 1,
    val xp: Int = 0,
    val title: String? = null,
    @SerializedName("streak_days") val streakDays: Int = 0,
    @SerializedName("class") val classKey: String? = null,
    @SerializedName("beer_master") val beerMaster: Boolean = false,
    @SerializedName("is_admin") val isAdmin: Boolean = false,
    @SerializedName("is_invite") val isInvite: Boolean = false,
    val checkins: Int = 0,
    @SerializedName("badge_count") val badgeCount: Int = 0,
    val allowed: Boolean = true,
    @SerializedName("has_profile") val hasProfile: Boolean = false,
    @SerializedName("daily_soft_cap") val dailySoftCap: Int = 0,
    @SerializedName("daily_xp_today") val dailyXpToday: Int = 0,
    @SerializedName("daily_checkins_today") val dailyCheckinsToday: Int = 0,
    @SerializedName("daily_soft_capped") val dailySoftCapped: Boolean = false,
    @SerializedName("daily_soft_cap_remaining") val dailySoftCapRemaining: Int? = null
)

fun RpgProfile.displayIcon(): String {
    if (beerMaster) return prestige?.icon ?: "👑"
    return classInfo?.icon ?: "🍺"
}

fun rarityLabelFr(r: String?): String = when ((r ?: "common").lowercase()) {
    "legendary" -> "Légendaire"
    "epic" -> "Épique"
    "rare" -> "Rare"
    else -> "Commun"
}
