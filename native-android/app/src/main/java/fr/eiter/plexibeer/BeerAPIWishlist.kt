package fr.eiter.plexibeer

import com.google.gson.reflect.TypeToken
import okhttp3.RequestBody.Companion.toRequestBody

suspend fun BeerAPI.wishlist(): List<WishlistItem> {
    val (body, _) = execute(requestBuilder("api/wishlist").get().build())
    val type = object : TypeToken<List<WishlistItem>>() {}.type
    return gson.fromJson(body, type) ?: emptyList()
}

suspend fun BeerAPI.addWishlist(beerName: String, brewery: String, style: String = "Unknown", barcode: String = "") {
    val json = gson.toJson(
        mapOf(
            "beer_name" to beerName,
            "brewery" to brewery,
            "style" to style,
            "barcode" to barcode
        )
    )
    execute(requestBuilder("api/wishlist").post(json.toRequestBody(BeerAPI.JSON)).build())
}

suspend fun BeerAPI.deleteWishlist(id: Int) {
    execute(requestBuilder("api/wishlist/$id").delete().build())
}
