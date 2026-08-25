package fr.eiter.plexibeer

import com.google.gson.reflect.TypeToken
import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody

suspend fun BeerAPI.checkins(
    q: String = "",
    style: String = "",
    minRating: Double = 0.0,
    period: String = "",
    limit: Int = 10,
    offset: Int = 0
): List<CheckinItem> {
    val params = mutableListOf("limit=$limit", "offset=$offset")
    if (q.isNotEmpty()) params += "q=${java.net.URLEncoder.encode(q, "UTF-8")}"
    if (style.isNotEmpty()) params += "style=${java.net.URLEncoder.encode(style, "UTF-8")}"
    if (minRating > 0) params += "min_rating=$minRating"
    if (period.isNotEmpty()) params += "period=${java.net.URLEncoder.encode(period, "UTF-8")}"
    val (body, _) = execute(requestBuilder("api/checkins?${params.joinToString("&")}").get().build())
    val type = object : TypeToken<List<CheckinItem>>() {}.type
    return gson.fromJson(body, type) ?: emptyList()
}

suspend fun BeerAPI.stats(): HistoryStats {
    val (body, _) = execute(requestBuilder("api/stats").get().build())
    return gson.fromJson(body, HistoryStats::class.java)
}

suspend fun BeerAPI.coupleStats(): CoupleStats {
    val (body, _) = execute(requestBuilder("api/stats/couple").get().build())
    return gson.fromJson(body, CoupleStats::class.java)
}

suspend fun BeerAPI.deleteCheckin(id: Int) {
    execute(requestBuilder("api/checkins/$id").delete().build())
}

suspend fun BeerAPI.updateCheckin(
    id: Int,
    rating: Double? = null,
    flavors: List<String>? = null,
    hops: List<String>? = null,
    comment: String? = null,
    hiddenFromPartner: Boolean? = null,
    location: String? = null,
    locationLat: Double? = null,
    locationLon: Double? = null,
    locationOsmId: String? = null
) {
    val payload = mutableMapOf<String, Any?>()
    if (rating != null) payload["rating"] = rating
    if (flavors != null) payload["flavors"] = flavors
    if (hops != null) payload["hops"] = hops
    if (comment != null) payload["comment"] = comment
    if (location != null) {
        payload["location"] = location.take(300)
        // Trio solidaire (cf. backend update_checkin) : le lieu et ses
        // coordonnées sont toujours envoyés ensemble — omis = pas de lieu réel.
        if (locationLat != null) payload["location_lat"] = locationLat
        if (locationLon != null) payload["location_lon"] = locationLon
        if (locationOsmId != null) payload["location_osm_id"] = locationOsmId
    }
    if (hiddenFromPartner != null) payload["hidden_from_partner"] = hiddenFromPartner
    val json = gson.toJson(payload)
    val req = requestBuilder("api/checkins/$id")
        .patch(json.toRequestBody(BeerAPI.JSON))
        .build()
    execute(req)
}

suspend fun BeerAPI.replaceCheckinPhoto(id: Int, jpeg: ByteArray) {
    val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        .addFormDataPart(
            "photo",
            "photo.jpg",
            jpeg.toRequestBody("image/jpeg".toMediaType())
        )
        .build()
    execute(requestBuilder("api/checkins/$id/photo").post(body).build())
}

suspend fun BeerAPI.removeCheckinPhoto(id: Int) {
    execute(requestBuilder("api/checkins/$id/photo").delete().build())
}

suspend fun BeerAPI.createCheckin(
    barcode: String,
    beerName: String,
    brewery: String,
    style: String,
    abv: String,
    summary: String,
    rating: Double,
    flavors: List<String>,
    hops: List<String>,
    comment: String,
    untappdBid: String,
    force: Boolean,
    photoJPEG: ByteArray? = null,
    location: String = "",
    locationLat: String = "",
    locationLon: String = "",
    locationOsmId: String = ""
): CreateCheckinResult = withContext(Dispatchers.IO) {
    val loc = location.trim().take(300)
    val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
    builder.addFormDataPart("barcode", barcode)
    builder.addFormDataPart("beer_name", beerName)
    builder.addFormDataPart("brewery", brewery)
    builder.addFormDataPart("style", style.ifBlank { "Unknown" })
    builder.addFormDataPart("abv", abv)
    builder.addFormDataPart("summary", summary)
    builder.addFormDataPart("rating", rating.toString())
    builder.addFormDataPart("flavors", gson.toJson(flavors))
    builder.addFormDataPart("hops", gson.toJson(hops))
    builder.addFormDataPart("comment", comment.take(300))
    builder.addFormDataPart("location", loc)
    builder.addFormDataPart("location_lat", locationLat)
    builder.addFormDataPart("location_lon", locationLon)
    builder.addFormDataPart("location_osm_id", locationOsmId)
    builder.addFormDataPart("untappd_bid", untappdBid)
    builder.addFormDataPart("force", if (force) "true" else "false")
    if (photoJPEG != null && photoJPEG.isNotEmpty()) {
        builder.addFormDataPart(
            "photo",
            "photo.jpg",
            photoJPEG.toRequestBody("image/jpeg".toMediaType())
        )
    }
    val req = requestBuilder("api/checkins").post(builder.build()).build()
    val (body, code) = execute(req)
    val decoded = gson.fromJson(body, CreateCheckinResult::class.java)
        ?: throw ApiException("Réponse création illisible")
    if (code == 409 || decoded.duplicate == true) return@withContext decoded
    if (decoded.ok != true && decoded.id == null) {
        throw ApiException(decoded.error ?: "Échec création")
    }
    decoded
}

/** Multipart convenience used by older wizard path */
suspend fun BeerAPI.createCheckinMultipart(
    beerName: String,
    brewery: String,
    style: String,
    rating: Double,
    comment: String?,
    photoFile: java.io.File? = null,
    barcode: String = "",
    untappdBid: Int? = null,
    flavors: List<String> = emptyList(),
    hops: List<String> = emptyList(),
    force: Boolean = false,
    location: String = ""
): Int {
    val bytes = photoFile?.takeIf { it.exists() }?.readBytes()
    val result = createCheckin(
        barcode = barcode,
        beerName = beerName,
        brewery = brewery,
        style = style,
        abv = "",
        summary = "",
        rating = rating,
        flavors = flavors,
        hops = hops,
        comment = comment.orEmpty(),
        untappdBid = untappdBid?.toString().orEmpty(),
        force = force,
        photoJPEG = bytes,
        location = location
    )
    if (result.duplicate == true) {
        throw ApiException(
            "duplicate|${result.previousCheckin?.beerName.orEmpty()}|${result.previousCheckin?.rating ?: 0}|${result.previousCheckin?.createdAt.orEmpty()}",
            409
        )
    }
    return result.id ?: 0
}
