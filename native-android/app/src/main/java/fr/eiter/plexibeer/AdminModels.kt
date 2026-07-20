package fr.eiter.plexibeer

import com.google.gson.annotations.SerializedName

// ── Admin comptes / invites / référentiels ───────────────────────────────────

data class AdminUser(
    val username: String = "",
    @SerializedName("is_admin") val isAdmin: Boolean = false,
    val checkins: Int = 0,
    @SerializedName("created_at") val createdAt: String? = null,
    val photos: Int? = null,
    @SerializedName("last_checkin_at") val lastCheckinAt: String? = null,
    @SerializedName("styles_count") val stylesCount: Int? = null,
    @SerializedName("breweries_count") val breweriesCount: Int? = null,
)

data class InviteClientProfile(
    val browser: String? = null,
    val os: String? = null,
    val device: String? = null,
) {
    val isKnown: Boolean
        get() = !browser.isNullOrBlank() && browser != "—"
}

data class InviteIpEntry(
    val ip: String? = null,
    @SerializedName("first_seen") val firstSeen: String? = null,
    @SerializedName("last_seen") val lastSeen: String? = null,
)

data class InviteItem(
    val id: Int = 0,
    val label: String? = null,
    val username: String? = null,
    val url: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("expires_at") val expiresAt: String? = null,
    @SerializedName("link_expires_at") val linkExpiresAt: String? = null,
    val active: Boolean? = null,
    @SerializedName("link_active") val linkActive: Boolean? = null,
    @SerializedName("revoked_at") val revokedAt: String? = null,
    @SerializedName("redeemed_at") val redeemedAt: String? = null,
    @SerializedName("last_used_at") val lastUsedAt: String? = null,
    @SerializedName("reactivation_pending") val reactivationPending: Boolean? = null,
    @SerializedName("can_extend") val canExtend: Boolean? = null,
    @SerializedName("can_reissue") val canReissue: Boolean? = null,
    val permanent: Boolean? = null,
    @SerializedName("validity_label") val validityLabel: String? = null,
    val checkins: Int? = null,
    @SerializedName("email_hint") val emailHint: String? = null,
    @SerializedName("redeem_ip") val redeemIp: String? = null,
    @SerializedName("last_used_ip") val lastUsedIp: String? = null,
    @SerializedName("device_short") val deviceShort: String? = null,
    @SerializedName("redeem_client") val redeemClient: InviteClientProfile? = null,
    @SerializedName("last_client") val lastClient: InviteClientProfile? = null,
    @SerializedName("ip_log") val ipLog: List<InviteIpEntry>? = null,
) {
    val statusText: String
        get() = when {
            revokedAt != null -> "Révoquée"
            reactivationPending == true -> "Réactivation"
            redeemedAt != null -> "Utilisée · lien mort"
            active == false -> "Expirée"
            linkActive == false -> "Lien expiré"
            else -> "En attente"
        }
}

data class CreateInviteResponse(
    val ok: Boolean? = null,
    val url: String? = null,
    val error: String? = null,
)

data class ReferentialEntry(
    val name: String = "",
    val preset: Boolean? = null,
    val deletable: Boolean? = null,
)

data class ReferentialsResponse(
    val styles: List<ReferentialEntry>? = null,
    val hops: List<ReferentialEntry>? = null,
    val flavors: List<ReferentialEntry>? = null,
)

data class CleanupPhotosResponse(
    val ok: Boolean? = null,
    val message: String? = null,
    val removed: Int? = null,
    val detail: String? = null,
)

// ── Feedback admin + réponses joueur ────────────────────────────────────────

data class AdminFeedbackStats(
    val total: Int? = null,
    val unread: Int? = null,
    val open: Int? = null,
    val done: Int? = null,
    val rejected: Int? = null,
)

data class AdminFeedbackListResponse(
    val items: List<AdminFeedbackItem>? = null,
    val stats: AdminFeedbackStats? = null,
)

data class FeedbackRepliesResponse(
    val ok: Boolean? = null,
    val items: List<AdminFeedbackItem>? = null,
    val count: Int? = null,
)

data class AdminFeedbackItem(
    val id: Int? = null,
    val message: String? = null,
    val category: String? = null,
    @SerializedName("category_label") val categoryLabel: String? = null,
    val username: String? = null,
    @SerializedName("is_invite") val isInvite: Boolean? = null,
    @SerializedName("admin_read") val adminRead: Boolean? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("client_ip") val clientIp: String? = null,
    @SerializedName("app_version") val appVersion: String? = null,
    val device: String? = null,
    @SerializedName("os_name") val osName: String? = null,
    val browser: String? = null,
    val status: String? = null,
    @SerializedName("status_label") val statusLabel: String? = null,
    @SerializedName("admin_reply") val adminReply: String? = null,
    @SerializedName("resolved_at") val resolvedAt: String? = null,
    @SerializedName("resolved_by") val resolvedBy: String? = null,
    @SerializedName("user_seen_reply") val userSeenReply: Boolean? = null,
) {
    val displayStatus: String
        get() = statusLabel?.takeIf { it.isNotBlank() }
            ?: when ((status ?: "open").lowercase()) {
                "done" -> "Mis en place"
                "rejected" -> "Refusé"
                else -> "En cours"
            }

    val isOpen: Boolean
        get() = (status ?: "open").lowercase() in setOf("open", "pending", "")

    val isDone: Boolean get() = (status ?: "").lowercase() == "done"
    val isRejected: Boolean get() = (status ?: "").lowercase() == "rejected"
}

// ── Versions portail ────────────────────────────────────────────────────────

data class MobileVersionsManifest(
    val ios: String? = null,
    @SerializedName("ios_build") val iosBuild: String? = null,
    val android: String? = null,
    @SerializedName("android_build") val androidBuild: String? = null,
    val webapp: String? = null,
    @SerializedName("portal_url") val portalUrl: String? = null,
)

fun beerVersionCompare(a: String, b: String): Int {
    fun extract(s: String): List<Int> {
        val buf = StringBuilder()
        var started = false
        for (ch in s) {
            when {
                ch.isDigit() -> {
                    buf.append(ch)
                    started = true
                }
                ch == '.' && started -> buf.append(ch)
                started -> break
            }
        }
        return buf.toString().split('.').mapNotNull { it.toIntOrNull() }
    }
    val pa = extract(a)
    val pb = extract(b)
    val n = maxOf(pa.size, pb.size)
    for (i in 0 until n) {
        val x = pa.getOrElse(i) { 0 }
        val y = pb.getOrElse(i) { 0 }
        if (x < y) return -1
        if (x > y) return 1
    }
    return 0
}
