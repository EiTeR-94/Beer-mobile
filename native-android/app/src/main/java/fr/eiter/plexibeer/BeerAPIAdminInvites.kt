package fr.eiter.plexibeer

import com.google.gson.reflect.TypeToken
import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.RequestBody.Companion.toRequestBody

/** Dégustations d'un compte invité (lecture seule, admin). */
suspend fun BeerAPI.adminInviteCheckins(inviteId: Int, limit: Int = 30, offset: Int = 0): List<CheckinItem> =
    withContext(Dispatchers.IO) {
        try {
            val (body, code) = execute(
                requestBuilder("api/invites/$inviteId/checkins?limit=$limit&offset=$offset").get().build()
            )
            if (code !in 200..299) return@withContext emptyList()
            val type = object : TypeToken<List<CheckinItem>>() {}.type
            gson.fromJson<List<CheckinItem>>(body, type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

suspend fun BeerAPI.adminInvites(): List<InviteItem> = withContext(Dispatchers.IO) {
    val (body, code) = execute(requestBuilder("api/invites").get().build())
    if (code !in 200..299) return@withContext emptyList()
    val type = object : TypeToken<List<InviteItem>>() {}.type
    gson.fromJson<List<InviteItem>>(body, type) ?: emptyList()
}

suspend fun BeerAPI.adminCreateInvite(label: String, email: String, validity: String = "7d"): CreateInviteResponse {
    val json = gson.toJson(
        mapOf("label" to label, "email" to email, "validity" to validity)
    )
    val (body, code) = execute(
        requestBuilder("api/invites").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    val decoded = gson.fromJson(body, CreateInviteResponse::class.java)
        ?: CreateInviteResponse(ok = false, error = "Réponse invalide")
    if (code !in 200..299) throw ApiException(decoded.error ?: "Création invite impossible", code)
    return decoded
}

suspend fun BeerAPI.adminExtendInvite(id: Int, validity: String) {
    val json = gson.toJson(mapOf("validity" to validity))
    val (_, code) = execute(
        requestBuilder("api/invites/$id/extend").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Prolongation impossible", code)
}

suspend fun BeerAPI.adminReissueInvite(id: Int): String? {
    val (body, code) = execute(
        requestBuilder("api/invites/$id/reissue").post("{}".toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Réémission impossible", code)
    return gson.fromJson(body, CreateInviteResponse::class.java)?.url
}

suspend fun BeerAPI.adminRevokeInvite(id: Int) {
    val (_, code) = execute(requestBuilder("api/invites/$id").delete().build())
    if (code !in 200..299) throw ApiException("Révocation impossible", code)
}
