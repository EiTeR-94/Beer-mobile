package fr.eiter.plexibeer

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
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

        private const val TAG = "BeerAPI"
        private const val NATIVE_CLIENT_HEADER = "X-PlexiBeer-Client"
        private const val NATIVE_CLIENT_VALUE = "native-android"
        private const val NATIVE_USER_AGENT = "PlexiBeer/1.0 (Android; native)"

        private val JSON = "application/json; charset=utf-8".toMediaType()
    }

    private val gson = Gson()

    // Separate clients like iOS: one for LAN (local accounts), one for 5G guests with IPv4 force
    private val lanClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .cookieJar(JavaNetCookieJar(java.net.CookieManager())) // for local session cookies
        .build()

    private val wanClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()  // For 5G, we can add IPv4 forcing if needed via custom DNS or network

    private var baseURL: String = ServerSettings.lanApiBase
    private var isGuest = false

    fun setBaseURL(url: String) {
        baseURL = ServerSettings.normalizeInput(url)
    }

    fun setGuestMode(guest: Boolean) {
        isGuest = guest
        baseURL = if (guest) ServerSettings.passkeyBaseURLs.first() else ServerSettings.lanApiBase
    }

    private fun clientForCurrent(): OkHttpClient = if (isGuest) wanClient else lanClient

    suspend fun login(username: String, password: String): LoginResponse = withContext(Dispatchers.IO) {
        val json = gson.toJson(mapOf("username" to username, "password" to password))
        val body = json.toRequestBody(JSON)

        val request = Request.Builder()
            .url(baseURL + "api/login")
            .post(body)
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .header("User-Agent", NATIVE_USER_AGENT)
            .build()

        val response = clientForCurrent().newCall(request).execute()
        val responseBody = response.body?.string() ?: "{}"

        if (response.code == 403) {
            throw BeerAPIError("Accès refusé — Wi‑Fi maison ou VPN Plexi requis")
        }

        gson.fromJson(responseBody, LoginResponse::class.java)
    }

    suspend fun me(): MeResponse = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(baseURL + "api/me")
            .get()
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()

        val response = clientForCurrent().newCall(request).execute()
        val body = response.body?.string() ?: "{}"
        gson.fromJson(body, MeResponse::class.java)
    }

    suspend fun checkins(): List<CheckinItem> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(baseURL + "api/checkins")
            .get()
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()

        val response = clientForCurrent().newCall(request).execute()
        val body = response.body?.string() ?: "[]"
        val listType = object : TypeToken<List<CheckinItem>>() {}.type
        gson.fromJson(body, listType)
    }

    // Add more as needed: createCheckin, lookup, flavors, etc.
    // For identical behavior, the API calls match the iOS exactly.

    suspend fun createCheckin(data: Map<String, Any>): CreateCheckinResult = withContext(Dispatchers.IO) {
        val json = gson.toJson(data)
        val body = json.toRequestBody(JSON)
        val request = Request.Builder()
            .url(baseURL + "api/checkins")
            .post(body)
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()

        val response = clientForCurrent().newCall(request).execute()
        val responseBody = response.body?.string() ?: "{}"
        gson.fromJson(responseBody, CreateCheckinResult::class.java)
    }

    // Placeholder for full feature parity - add barcode lookup, photo upload, etc. as in iOS
}

data class LoginResponse(val ok: Boolean?, val user: String?, val is_admin: Boolean?, val error: String?)
data class MeResponse(val user: String?, val auth: Boolean, val is_admin: Boolean, val is_invite: Boolean)
data class CheckinItem(val id: Int, val beer_name: String, val brewery: String, val style: String, val rating: Double?, val comment: String?)
data class CreateCheckinResult(val ok: Boolean?, val duplicate: Boolean?, val error: String?)

// Error handling matching iOS
class BeerAPIError(message: String) : Exception(message)