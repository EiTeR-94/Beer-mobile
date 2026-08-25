package fr.eiter.plexibeer

import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

suspend fun BeerAPI.version(): String {
    return try {
        val (body, _) = execute(requestBuilder("api/version").get().build())
        gson.fromJson(body, VersionResponse::class.java)?.version ?: "?"
    } catch (_: Exception) {
        "?"
    }
}

/**
 * Download internal asset with auth cookies. Tries LAN first then current base.
 * External http(s) URLs use plain client without cookie injection issues.
 */
suspend fun BeerAPI.downloadAsset(pathOrURL: String?): ByteArray = withContext(Dispatchers.IO) {
    val p = pathOrURL?.takeIf { it.isNotBlank() }
        ?: throw ApiException("URL asset invalide")
    if (p.startsWith("http://") || p.startsWith("https://")) {
        // external (Untappd labels etc.) — plain GET
        val plain = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
        plain.newCall(Request.Builder().url(p).get().build()).execute().use { resp ->
            if (!resp.isSuccessful) throw ApiException("Fichier externe HTTP ${resp.code}")
            return@withContext resp.body?.bytes() ?: ByteArray(0)
        }
    }
    val candidates = listOfNotNull(
        ServerSettings.resolveAssetURL(p, ServerSettings.LAN_API_BASE),
        ServerSettings.resolveAssetURL(p, baseURL)
    ).distinct()
    var lastErr: Exception? = null
    for (url in candidates) {
        try {
            val b = Request.Builder().url(url)
            applyHeaders(b)
            client.newCall(b.get().build()).execute().use { resp ->
                if (resp.code == 401) throw ApiException("Session expirée", 401)
                if (resp.isSuccessful) {
                    return@withContext resp.body?.bytes() ?: ByteArray(0)
                }
                lastErr = ApiException("Fichier HTTP ${resp.code}")
            }
        } catch (e: Exception) {
            lastErr = e
        }
    }
    throw (lastErr ?: ApiException("Asset introuvable"))
}

suspend fun BeerAPI.patchnotes(): PatchnotesResponse {
    val (body, _) = execute(requestBuilder("api/admin/patchnotes").get().build())
    return gson.fromJson(body, PatchnotesResponse::class.java)
}

suspend fun BeerAPI.fetchMobileVersions(): MobileVersionsManifest? = withContext(Dispatchers.IO) {
    try {
        val url = ServerSettings.versionsURL
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return@withContext null
            val body = resp.body?.string().orEmpty()
            gson.fromJson(body, MobileVersionsManifest::class.java)
        }
    } catch (_: Exception) {
        null
    }
}
