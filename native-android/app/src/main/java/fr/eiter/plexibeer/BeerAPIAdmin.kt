package fr.eiter.plexibeer

import com.google.gson.reflect.TypeToken
import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.RequestBody.Companion.toRequestBody

suspend fun BeerAPI.adminUsers(): List<AdminUser> = withContext(Dispatchers.IO) {
    val (body, code) = execute(requestBuilder("api/admin/users").get().build())
    if (code !in 200..299) return@withContext emptyList()
    val type = object : TypeToken<List<AdminUser>>() {}.type
    gson.fromJson<List<AdminUser>>(body, type) ?: emptyList()
}

suspend fun BeerAPI.adminCreateUser(username: String, password: String, isAdmin: Boolean) {
    val json = gson.toJson(
        mapOf("username" to username, "password" to password, "is_admin" to isAdmin)
    )
    val (_, code) = execute(
        requestBuilder("api/admin/users").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Création compte impossible", code)
}

suspend fun BeerAPI.adminDeleteUser(username: String) {
    val enc = java.net.URLEncoder.encode(username, "UTF-8")
    val (_, code) = execute(requestBuilder("api/admin/users/$enc").delete().build())
    if (code !in 200..299) throw ApiException("Suppression impossible", code)
}

suspend fun BeerAPI.adminSetAdmin(username: String, isAdmin: Boolean) {
    val enc = java.net.URLEncoder.encode(username, "UTF-8")
    val json = gson.toJson(mapOf("is_admin" to isAdmin))
    val (_, code) = execute(
        requestBuilder("api/admin/users/$enc").patch(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Changement admin impossible", code)
}

suspend fun BeerAPI.adminSetPassword(username: String, password: String) {
    val enc = java.net.URLEncoder.encode(username, "UTF-8")
    val json = gson.toJson(mapOf("password" to password))
    val (_, code) = execute(
        requestBuilder("api/admin/users/$enc").patch(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Mot de passe non mis à jour", code)
}

suspend fun BeerAPI.adminCleanupPhotos(): String {
    val (body, code) = execute(
        requestBuilder("api/admin/photos/cleanup").post("{}".toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Nettoyage impossible", code)
    val d = gson.fromJson(body, CleanupPhotosResponse::class.java)
    return d?.message
        ?: d?.detail
        ?: (d?.removed?.let { "Supprimé : $it photo(s)" })
        ?: "Photos nettoyées"
}

suspend fun BeerAPI.adminReferentials(): ReferentialsResponse = withContext(Dispatchers.IO) {
    val (body, code) = execute(requestBuilder("api/admin/referentials").get().build())
    if (code !in 200..299) return@withContext ReferentialsResponse()
    gson.fromJson(body, ReferentialsResponse::class.java) ?: ReferentialsResponse()
}

suspend fun BeerAPI.adminAddStyle(name: String) {
    val json = gson.toJson(mapOf("name" to name))
    val (_, code) = execute(
        requestBuilder("api/styles").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Ajout style impossible", code)
}

suspend fun BeerAPI.adminDeleteStyle(name: String) {
    val enc = java.net.URLEncoder.encode(name, "UTF-8")
    val (_, code) = execute(requestBuilder("api/styles/$enc").delete().build())
    if (code !in 200..299) throw ApiException("Suppression style impossible", code)
}

suspend fun BeerAPI.adminAddHop(name: String) {
    val json = gson.toJson(mapOf("name" to name))
    val (_, code) = execute(
        requestBuilder("api/hops").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Ajout houblon impossible", code)
}

suspend fun BeerAPI.adminDeleteHop(name: String) {
    val enc = java.net.URLEncoder.encode(name, "UTF-8")
    val (_, code) = execute(requestBuilder("api/hops/$enc").delete().build())
    if (code !in 200..299) throw ApiException("Suppression houblon impossible", code)
}

suspend fun BeerAPI.adminAddFlavor(name: String) {
    val json = gson.toJson(mapOf("name" to name))
    val (_, code) = execute(
        requestBuilder("api/flavors/custom").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Ajout goût impossible", code)
}

suspend fun BeerAPI.adminDeleteFlavor(name: String) {
    val enc = java.net.URLEncoder.encode(name, "UTF-8")
    val (_, code) = execute(requestBuilder("api/flavors/custom/$enc").delete().build())
    if (code !in 200..299) throw ApiException("Suppression goût impossible", code)
}
