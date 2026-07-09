package fr.eiter.plexibeer

import com.google.gson.annotations.SerializedName

data class MeResponse(
    val user: String?,
    val auth: Boolean,
    @SerializedName("is_admin") val isAdmin: Boolean = false,
    @SerializedName("is_invite") val isInvite: Boolean = false
)

data class LoginResponse(
    val ok: Boolean,
    val user: String?,
    @SerializedName("is_admin") val isAdmin: Boolean?,
    val error: String? = null
)

data class CheckinItem(
    val id: Int,
    @SerializedName("beer_name") val beerName: String,
    val brewery: String?,
    val style: String?,
    val rating: Double,
    val comment: String?,
    val barcode: String?,
    @SerializedName("created_at") val createdAt: String?,
    @SerializedName("photo_url") val photoURL: String?,
    val flavors: List<String>?,
    val hops: List<String>?,
    @SerializedName("hidden_from_partner") val hiddenFromPartner: Boolean?,
    @SerializedName("untappd_bid") val untappdBid: Int?
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
}

data class LookupResponse(
    val ok: Boolean,
    val error: String?,
    val barcode: String?,
    @SerializedName("beer_name") val beerName: String?,
    val brewery: String?,
    val style: String?,
    @SerializedName("style_fr") val styleFr: String?,
    val abv: Double?,
    val summary: String?,
    @SerializedName("untappd_bid") val untappdBid: Int?,
    val source: String?,
    @SerializedName("photo_url") val photoURL: String?
)

data class WishlistItem(
    val id: Int,
    @SerializedName("beer_name") val beerName: String,
    val brewery: String?,
    val style: String?,
    val barcode: String?,
    val note: String?,
    @SerializedName("created_at") val createdAt: String?
)

data class HistoryStats(
    val total: Int,
    @SerializedName("avg_rating") val avgRating: Double?,
    @SerializedName("top_styles") val topStyles: List<TopStyle>?,
    val last: LastCheckin?
) {
    data class TopStyle(val style: String?, val count: Int?)
    data class LastCheckin(@SerializedName("beer_name") val beerName: String?)
}

data class StyleOption(val value: String, val label: String)