package fr.eiter.plexibeer

import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.RequestBody.Companion.toRequestBody

/** Feedback joueur (parité PWA « Un retour »). */
suspend fun BeerAPI.sendFeedback(
    message: String,
    category: String = "general",
    appVersion: String = "",
): Pair<Boolean, String?> {
    return try {
        val payload = mutableMapOf<String, Any>(
            "message" to message,
            "category" to category,
            "client_info" to "native-android",
            "page_path" to "native/android",
        )
        if (appVersion.isNotBlank()) payload["app_version"] = appVersion
        val json = gson.toJson(payload)
        val (body, code) = execute(
            requestBuilder("api/feedback").post(json.toRequestBody(BeerAPI.JSON)).build()
        )
        if (code in 200..299) {
            true to null
        } else {
            val err = try {
                @Suppress("UNCHECKED_CAST")
                (gson.fromJson(body, Map::class.java) as? Map<String, Any>)
                    ?.get("detail")?.toString()
            } catch (_: Exception) {
                null
            }
            false to (err ?: "Erreur $code")
        }
    } catch (e: Exception) {
        false to (e.message ?: "Réseau indisponible")
    }
}

suspend fun BeerAPI.adminFeedbackList(
    limit: Int = 80,
    unreadOnly: Boolean = false,
    status: String? = null,
): AdminFeedbackListResponse = withContext(Dispatchers.IO) {
    var path = "api/admin/feedback?limit=${limit.coerceIn(1, 200)}"
    if (unreadOnly) path += "&unread=1"
    if (!status.isNullOrBlank()) path += "&status=${java.net.URLEncoder.encode(status, "UTF-8")}"
    val (body, code) = execute(requestBuilder(path).get().build())
    if (code !in 200..299) throw ApiException("Feedback admin indisponible", code)
    gson.fromJson(body, AdminFeedbackListResponse::class.java)
        ?: AdminFeedbackListResponse()
}

suspend fun BeerAPI.adminFeedbackStats(): AdminFeedbackStats? = try {
    adminFeedbackList(limit = 1).stats
} catch (_: Exception) {
    null
}

suspend fun BeerAPI.adminFeedbackMarkRead(id: Int, read: Boolean = true) {
    val json = gson.toJson(mapOf("read" to read))
    val (_, code) = execute(
        requestBuilder("api/admin/feedback/$id/read").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Marquage lu impossible", code)
}

suspend fun BeerAPI.adminFeedbackReadAll() {
    val (_, code) = execute(
        requestBuilder("api/admin/feedback/read-all").post("{}".toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Lecture globale impossible", code)
}

suspend fun BeerAPI.adminFeedbackResolve(id: Int, status: String, reply: String) {
    val json = gson.toJson(mapOf("status" to status, "reply" to reply))
    val (_, code) = execute(
        requestBuilder("api/admin/feedback/$id/resolve").post(json.toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Réponse impossible", code)
}

suspend fun BeerAPI.adminFeedbackReopen(id: Int) {
    val (_, code) = execute(
        requestBuilder("api/admin/feedback/$id/reopen").post("{}".toRequestBody(BeerAPI.JSON)).build()
    )
    if (code !in 200..299) throw ApiException("Réouverture impossible", code)
}

suspend fun BeerAPI.adminFeedbackDelete(id: Int) {
    val (_, code) = execute(requestBuilder("api/admin/feedback/$id").delete().build())
    if (code !in 200..299) throw ApiException("Suppression impossible", code)
}

suspend fun BeerAPI.feedbackReplies(unseenOnly: Boolean = true): List<AdminFeedbackItem> =
    withContext(Dispatchers.IO) {
        val path = "api/feedback/replies?unseen=${if (unseenOnly) "1" else "0"}&limit=20"
        val (body, code) = execute(requestBuilder(path).get().build())
        if (code !in 200..299) return@withContext emptyList()
        gson.fromJson(body, FeedbackRepliesResponse::class.java)?.items.orEmpty()
    }

suspend fun BeerAPI.markFeedbackRepliesSeen(ids: List<Int>) {
    try {
        val json = gson.toJson(mapOf("ids" to ids))
        execute(
            requestBuilder("api/feedback/replies/seen").post(json.toRequestBody(BeerAPI.JSON)).build()
        )
    } catch (_: Exception) {
    }
}
