package fr.eiter.plexibeer

import com.google.gson.annotations.SerializedName
import java.util.UUID

data class MeResponse(
    val user: String? = null,
    val auth: Boolean = false,
    @SerializedName("is_admin") val isAdmin: Boolean = false,
    @SerializedName("is_invite") val isInvite: Boolean = false
)

data class LoginResponse(
    val ok: Boolean = false,
    val user: String? = null,
    @SerializedName("is_admin") val isAdmin: Boolean? = null,
    val error: String? = null
)

data class NativeJoinResponse(
    val ok: Boolean = false,
    @SerializedName("access_token") val accessToken: String? = null,
    val user: String? = null,
    val label: String? = null,
    @SerializedName("is_invite") val isInvite: Boolean = false,
    @SerializedName("device_id") val deviceId: String? = null,
    @SerializedName("expires_at") val expiresAt: String? = null,
    val error: String? = null
)

data class BeerProduct(
    var ok: Boolean = true,
    var barcode: String = "",
    @SerializedName("beer_name") var beerName: String = "",
    var brewery: String = "",
    var style: String = "Unknown",
    @SerializedName("style_fr") var styleFr: String? = null,
    var abv: Double? = null,
    var summary: String = "",
    @SerializedName("untappd_bid") var untappdBid: Int? = null,
    var source: String? = null,
    @SerializedName("photo_url") var photoURL: String? = null
) {
    val displayStyle: String get() = styleFr ?: style

    companion object {
        fun fromCheckin(item: CheckinItem) = BeerProduct(
            barcode = item.barcode.orEmpty(),
            beerName = item.beerName,
            brewery = item.brewery ?: "—",
            style = item.style ?: "Unknown",
            summary = "${item.beerName} — re-dégustation",
            untappdBid = item.untappdBid
        )

        fun fromWishlist(item: WishlistItem) = BeerProduct(
            barcode = item.barcode.orEmpty(),
            beerName = item.beerName,
            brewery = item.brewery ?: "—",
            style = item.style ?: "Unknown",
            summary = "${item.beerName} — depuis À boire",
            source = "wishlist"
        )
    }
}

data class LookupResponse(
    val ok: Boolean = false,
    val error: String? = null,
    val barcode: String? = null,
    @SerializedName("beer_name") val beerName: String? = null,
    val brewery: String? = null,
    val style: String? = null,
    @SerializedName("style_fr") val styleFr: String? = null,
    val abv: Double? = null,
    val summary: String? = null,
    @SerializedName("untappd_bid") val untappdBid: Int? = null,
    val source: String? = null,
    @SerializedName("photo_url") val photoURL: String? = null
) {
    fun asProduct(fallbackBarcode: String) = BeerProduct(
        ok = ok,
        barcode = barcode ?: fallbackBarcode,
        beerName = beerName.orEmpty(),
        brewery = brewery.orEmpty(),
        style = style ?: "Unknown",
        styleFr = styleFr,
        abv = abv,
        summary = summary.orEmpty(),
        untappdBid = untappdBid,
        source = source,
        photoURL = photoURL
    )
}

data class CheckinItem(
    val id: Int = 0,
    @SerializedName("beer_name") val beerName: String = "",
    val brewery: String? = null,
    val style: String? = null,
    val rating: Double = 0.0,
    val comment: String? = null,
    val barcode: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("photo_url") val photoURL: String? = null,
    val flavors: List<String>? = null,
    val hops: List<String>? = null,
    @SerializedName("hidden_from_partner") val hiddenFromPartner: Boolean? = null,
    @SerializedName("untappd_bid") val untappdBid: Int? = null,
    /** Lieu / lien de dégustation (optionnel). */
    val location: String? = null
)

data class HistoryStats(
    val total: Int = 0,
    @SerializedName("avg_rating") val avgRating: Double? = null,
    @SerializedName("top_styles") val topStyles: List<TopStyle>? = null,
    val last: LastCheckin? = null
) {
    data class TopStyle(val style: String? = null, val count: Int? = null)
    data class LastCheckin(@SerializedName("beer_name") val beerName: String? = null)
}

data class StyleOption(val value: String = "", val label: String = "")

data class WishlistItem(
    val id: Int = 0,
    @SerializedName("beer_name") val beerName: String = "",
    val brewery: String? = null,
    val style: String? = null,
    val barcode: String? = null,
    val note: String? = null,
    @SerializedName("created_at") val createdAt: String? = null
)

data class GiftIdea(
    @SerializedName("beer_name") val beerName: String = "",
    val brewery: String? = null,
    val style: String? = null,
    val rating: Double? = null,
    val comment: String? = null,
    @SerializedName("photo_path") val photoPath: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("liked_by") val likedBy: String? = null,
    @SerializedName("for") val forUser: String? = null
) {
    val id: String get() = "$beerName-${likedBy.orEmpty()}-${createdAt.orEmpty()}"
}

data class CoupleStats(
    val users: List<CoupleUser>? = null,
    @SerializedName("gift_ideas") val giftIdeas: List<GiftIdea>? = null
) {
    data class CoupleUser(val username: String = "", val total: Int = 0)
}

data class UntappdSearchResponse(
    val ok: Boolean = false,
    val error: String? = null,
    val results: List<UntappdHit>? = null
)

data class UntappdHit(
    val bid: Int = 0,
    @SerializedName("beer_name") val beerName: String = "",
    val brewery: String? = null,
    @SerializedName("style_fr") val styleFr: String? = null,
    @SerializedName("photo_url") val photoURL: String? = null
)

data class FlavorsResponse(
    val flavors: List<String>? = null,
    @SerializedName("suggested_flavors") val suggestedFlavors: List<String>? = null,
    val hops: List<String>? = null,
    @SerializedName("suggested_hops") val suggestedHops: List<String>? = null,
    @SerializedName("show_flavors_block") val showFlavorsBlock: Boolean? = null,
    @SerializedName("show_hops_block") val showHopsBlock: Boolean? = null
)

data class CreateCheckinResult(
    val ok: Boolean? = null,
    val id: Int? = null,
    val duplicate: Boolean? = null,
    val error: String? = null,
    @SerializedName("previous_checkin") val previousCheckin: PreviousCheckin? = null,
    /** Beerquest loot (null si RPG off / non autorisé) */
    val rpg: RpgLoot? = null
)

data class PreviousCheckin(
    @SerializedName("beer_name") val beerName: String? = null,
    val rating: Double? = null,
    @SerializedName("created_at") val createdAt: String? = null
)

data class DecodeBarcodeResponse(
    val ok: Boolean = false,
    val barcode: String? = null,
    val error: String? = null
)

data class OkResponse(
    val ok: Boolean? = null,
    val error: String? = null
)

data class VersionResponse(val version: String? = null)

data class PatchnotesResponse(
    val version: String? = null,
    val markdown: String? = null
)

data class PendingCheckin(
    val id: String = UUID.randomUUID().toString(),
    val createdAtMs: Long = System.currentTimeMillis(),
    val barcode: String = "",
    val beerName: String = "",
    val brewery: String = "",
    val style: String = "Unknown",
    val abv: String = "",
    val summary: String = "",
    val rating: Double = 3.0,
    val flavors: List<String> = emptyList(),
    val hops: List<String> = emptyList(),
    val comment: String = "",
    val untappdBid: String = "",
    val force: Boolean = false,
    /** Absolute path to local JPEG, or null */
    val photoPath: String? = null,
    /** Lieu / lien de dégustation (optionnel). */
    val location: String? = null
)

enum class NetworkStatus(val label: String) {
    ONLINE("En ligne"),
    SERVER_UNREACHABLE("Serveur injoignable"),
    OFFLINE("Hors ligne")
}

enum class BeerSheet {
    HISTORY, GALLERY, WISHLIST, GIFTS, PENDING, DETAIL, EDIT, ADMIN, PATCHNOTES, GRIMOIRE, RPG_ADMIN
}

data class ToastPayload(
    val message: String,
    val variant: Variant = Variant.INFO,
    val detail: String? = null,
    /** Libellé court type iOS (« Invitation », « Succès »…) — optionnel. */
    val label: String? = null
) {
    enum class Variant { INFO, SUCCESS, WARN, ERROR, DUPLICATE }
}
