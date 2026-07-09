package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

class BeerAPI private constructor(private val context: Context) {
    companion object {
        @Volatile
        private var INSTANCE: BeerAPI? = null

        fun getInstance(context: Context): BeerAPI {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: BeerAPI(context.applicationContext).also { INSTANCE = it }
            }
        }

        private const val NATIVE_CLIENT_HEADER = "X-PlexiBeer-Client"
        private const val NATIVE_CLIENT_VALUE = "native-android"
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }

    private val gson = Gson()

    // Relaxed timeouts matching iOS (important for LAN/VPN)
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val probeClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    private var baseURL: String = ServerSettings.effectiveBase

    fun setBaseURL(url: String) {
        baseURL = ServerSettings.normalizeInput(url)
    }

    fun useEffectiveBase() {
        baseURL = ServerSettings.effectiveBase
    }

    // Discover working endpoint (LAN first) - ported from iOS
    suspend fun discoverWorkingEndpoint(): String? = withContext(Dispatchers.IO) {
        val candidates = ServerSettings.candidateURLs
        for (candidate in candidates) {
            try {
                val healthUrl = ServerSettings.normalizeInput(candidate) + "api/health"
                val req = Request.Builder()
                    .url(healthUrl)
                    .get()
                    .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
                    .build()
                val resp = if (ServerSettings.isLanEndpoint(candidate)) probeClient else client
                val response = resp.newCall(req).execute()
                if (response.isSuccessful) {
                    setBaseURL(candidate)
                    return@withContext candidate
                }
            } catch (_: Exception) {}
        }
        null
    }

    private fun buildRequest(path: String, method: String = "GET", jsonBody: String? = null): Request {
        val url = baseURL + path.trimStart('/')
        val builder = Request.Builder()
            .url(url)
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)

        when (method.uppercase()) {
            "GET" -> builder.get()
            "POST" -> {
                val body = jsonBody?.toRequestBody(JSON) ?: "".toRequestBody(JSON)
                builder.post(body)
            }
            "DELETE" -> builder.delete()
            else -> builder.method(method, jsonBody?.toRequestBody(JSON))
        }
        return builder.build()
    }

    private suspend fun executeRequest(req: Request): String = withContext(Dispatchers.IO) {
        val resp = client.newCall(req).execute()
        val bodyStr = resp.body?.string() ?: "{}"
        if (resp.code == 403) throw Exception("Accès refusé — Wi-Fi maison ou VPN Plexi requis")
        if (!resp.isSuccessful) throw Exception("Erreur serveur: ${resp.code} $bodyStr")
        bodyStr
    }

    suspend fun healthCheck(): Boolean = withContext(Dispatchers.IO) {
        try {
            val req = buildRequest("/api/health")
            val resp = client.newCall(req).execute()
            resp.isSuccessful
        } catch (e: Exception) { false }
    }

    suspend fun login(username: String, password: String): LoginResponse = withContext(Dispatchers.IO) {
        val json = gson.toJson(mapOf("username" to username, "password" to password))
        val req = buildRequest("/api/login", "POST", json)
        val bodyStr = executeRequest(req)
        gson.fromJson(bodyStr, LoginResponse::class.java)
    }

    suspend fun me(): MeResponse = withContext(Dispatchers.IO) {
        val req = buildRequest("/api/me")
        val bodyStr = executeRequest(req)
        gson.fromJson(bodyStr, MeResponse::class.java)
    }

    suspend fun logout() {
        try { executeRequest(buildRequest("/api/logout", "POST")) } catch (_: Exception) {}
    }

    suspend fun lookup(barcode: String): LookupResponse = withContext(Dispatchers.IO) {
        val json = gson.toJson(mapOf("barcode" to barcode))
        val req = buildRequest("/api/lookup", "POST", json)
        val bodyStr = executeRequest(req)
        gson.fromJson(bodyStr, LookupResponse::class.java)
    }

    suspend fun checkins(limit: Int = 50): List<CheckinItem> = withContext(Dispatchers.IO) {
        val req = buildRequest("/api/checkins?limit=$limit")
        val bodyStr = executeRequest(req)
        val listType = object : com.google.gson.reflect.TypeToken<List<CheckinItem>>() {}.type
        gson.fromJson(bodyStr, listType)
    }

    suspend fun createCheckin(data: Map<String, Any?>): Map<String, Any?> = withContext(Dispatchers.IO) {
        val json = gson.toJson(data)
        val req = buildRequest("/api/checkins", "POST", json)
        val bodyStr = executeRequest(req)
        gson.fromJson(bodyStr, object : com.google.gson.reflect.TypeToken<Map<String, Any?>>() {}.type)
    }

    suspend fun deleteCheckin(id: Int) = withContext(Dispatchers.IO) {
        executeRequest(buildRequest("/api/checkins/$id", "DELETE"))
    }

    suspend fun uploadPhoto(checkinId: Int, photoFile: File) = withContext(Dispatchers.IO) {
        val requestBody = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("photo", photoFile.name, photoFile.asRequestBody("image/jpeg".toMediaType()))
            .build()
        val req = Request.Builder()
            .url(baseURL + "api/checkins/$checkinId/photo")
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .post(requestBody)
            .build()
        val resp = client.newCall(req).execute()
        if (!resp.isSuccessful) throw Exception("Upload photo failed")
        resp.body?.string()
    }

    suspend fun wishlist(): List<WishlistItem> = withContext(Dispatchers.IO) {
        val req = buildRequest("/api/wishlist")
        val bodyStr = executeRequest(req)
        val listType = object : com.google.gson.reflect.TypeToken<List<WishlistItem>>() {}.type
        gson.fromJson(bodyStr, listType)
    }

    suspend fun addWishlist(beerName: String, brewery: String, style: String, barcode: String = "") {
        val json = gson.toJson(mapOf("beer_name" to beerName, "brewery" to brewery, "style" to style, "barcode" to barcode))
        executeRequest(buildRequest("/api/wishlist", "POST", json))
    }

    suspend fun deleteWishlist(id: Int) {
        executeRequest(buildRequest("/api/wishlist/$id", "DELETE"))
    }

    suspend fun stats(): HistoryStats = withContext(Dispatchers.IO) {
        val req = buildRequest("/api/stats")
        val bodyStr = executeRequest(req)
        gson.fromJson(bodyStr, HistoryStats::class.java)
    }

    suspend fun styles(): List<StyleOption> = withContext(Dispatchers.IO) {
        val req = buildRequest("/api/styles")
        val bodyStr = executeRequest(req)
        val listType = object : com.google.gson.reflect.TypeToken<List<StyleOption>>() {}.type
        gson.fromJson(bodyStr, listType)
    }
}