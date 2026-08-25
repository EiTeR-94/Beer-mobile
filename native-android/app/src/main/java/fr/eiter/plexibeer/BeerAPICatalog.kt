package fr.eiter.plexibeer

import com.google.gson.reflect.TypeToken
import fr.eiter.plexibeer.BeerAPI.ApiException
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody

suspend fun BeerAPI.lookup(barcode: String): LookupResponse {
    val json = gson.toJson(mapOf("barcode" to barcode))
    val (body, _) = execute(requestBuilder("api/lookup").post(json.toRequestBody(BeerAPI.JSON)).build())
    return gson.fromJson(body, LookupResponse::class.java)
}

suspend fun BeerAPI.styles(): List<StyleOption> {
    return try {
        val (body, code) = execute(requestBuilder("api/styles").get().build())
        if (code == 401) return emptyList()
        val type = object : TypeToken<List<StyleOption>>() {}.type
        gson.fromJson(body, type) ?: emptyList()
    } catch (_: Exception) {
        emptyList()
    }
}

suspend fun BeerAPI.searchUntappd(query: String): UntappdSearchResponse {
    val q = java.net.URLEncoder.encode(query, "UTF-8")
    val (body, _) = execute(requestBuilder("api/untappd/search?q=$q&limit=5").get().build())
    return gson.fromJson(body, UntappdSearchResponse::class.java)
}

/** Backward-compatible brewery+name search used by wizard */
suspend fun BeerAPI.searchUntappd(brewery: String, name: String): UntappdSearchResponse {
    val q = listOf(brewery, name).filter { it.isNotBlank() }.joinToString(" ").trim()
    return if (q.isBlank()) UntappdSearchResponse(ok = false, error = "Requête vide")
    else searchUntappd(q)
}

suspend fun BeerAPI.geocodeSearch(query: String, lat: Double? = null, lon: Double? = null): GeocodeSearchResponse {
    val q = java.net.URLEncoder.encode(query, "UTF-8")
    var path = "api/geocode/search?q=$q"
    if (lat != null) path += "&lat=$lat"
    if (lon != null) path += "&lon=$lon"
    val (body, _) = execute(requestBuilder(path).get().build())
    return gson.fromJson(body, GeocodeSearchResponse::class.java)
}

suspend fun BeerAPI.untappdFetch(
    bid: Int,
    barcode: String = "",
    beerName: String = "",
    brewery: String = ""
): LookupResponse {
    val json = gson.toJson(
        mapOf(
            "untappd_bid" to bid,
            "barcode" to barcode,
            "beer_name" to beerName,
            "brewery" to brewery
        )
    )
    val (body, _) = execute(requestBuilder("api/untappd/fetch").post(json.toRequestBody(BeerAPI.JSON)).build())
    return gson.fromJson(body, LookupResponse::class.java)
}

suspend fun BeerAPI.flavors(style: String, description: String = ""): FlavorsResponse {
    val s = java.net.URLEncoder.encode(style, "UTF-8")
    val d = java.net.URLEncoder.encode(description, "UTF-8")
    val (body, _) = execute(requestBuilder("api/flavors?style=$s&description=$d").get().build())
    return gson.fromJson(body, FlavorsResponse::class.java)
}

suspend fun BeerAPI.flavorsAndHops(): FlavorsResponse = flavors(style = "", description = "")

suspend fun BeerAPI.addHop(name: String) {
    val json = gson.toJson(mapOf("name" to name))
    execute(requestBuilder("api/hops").post(json.toRequestBody(BeerAPI.JSON)).build())
}

suspend fun BeerAPI.scanPhoto(jpeg: ByteArray): LookupResponse {
    val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        .addFormDataPart(
            "image",
            "scan.jpg",
            jpeg.toRequestBody("image/jpeg".toMediaType())
        )
        .build()
    val (respBody, _) = execute(requestBuilder("api/scan-photo").post(body).build())
    return gson.fromJson(respBody, LookupResponse::class.java)
}

suspend fun BeerAPI.decodeBarcode(jpeg: ByteArray): DecodeBarcodeResponse {
    val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        .addFormDataPart(
            "image",
            "scan.jpg",
            jpeg.toRequestBody("image/jpeg".toMediaType())
        )
        .build()
    val (respBody, _) = execute(requestBuilder("api/decode-barcode").post(body).build())
    return gson.fromJson(respBody, DecodeBarcodeResponse::class.java)
}

suspend fun BeerAPI.saveProduct(
    barcode: String,
    beerName: String,
    brewery: String,
    style: String
): LookupResponse {
    val json = gson.toJson(
        mapOf(
            "barcode" to barcode,
            "beer_name" to beerName,
            "brewery" to brewery,
            "style" to style
        )
    )
    val (body, code) = execute(
        requestBuilder("api/products/save").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    val decoded = gson.fromJson(body, LookupResponse::class.java)
    if (code >= 400 || decoded.ok == false) {
        throw ApiException(decoded.error ?: "Sauvegarde produit impossible", code)
    }
    return decoded
}

suspend fun BeerAPI.linkProduct(
    bid: Int,
    barcode: String,
    beerName: String,
    brewery: String
): LookupResponse {
    val json = gson.toJson(
        mapOf(
            "untappd_bid" to bid,
            "barcode" to barcode,
            "beer_name" to beerName,
            "brewery" to brewery
        )
    )
    val (body, code) = execute(
        requestBuilder("api/products/link").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    val decoded = gson.fromJson(body, LookupResponse::class.java)
    if (code >= 400 || decoded.ok == false) {
        throw ApiException(decoded.error ?: "Liaison impossible", code)
    }
    return decoded
}
