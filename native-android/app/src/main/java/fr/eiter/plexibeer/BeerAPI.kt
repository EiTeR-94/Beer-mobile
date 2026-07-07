package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
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
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private var baseURL: String = ServerSettings.lanApiBase
    private var isGuest = false

    fun setBaseURL(url: String) {
        baseURL = ServerSettings.normalizeInput(url)
    }

    fun setGuestMode(guest: Boolean) {
        isGuest = guest
        baseURL = if (guest) ServerSettings.passkeyBaseURLs.first() else ServerSettings.lanApiBase
    }

    suspend fun login(username: String, password: String): LoginResponse = withContext(Dispatchers.IO) {
        val json = gson.toJson(mapOf("username" to username, "password" to password))
        val body = json.toRequestBody(JSON)
        val request = Request.Builder()
            .url(baseURL + "api/login")
            .post(body)
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()
        val response = client.newCall(request).execute()
        val bodyStr = response.body?.string() ?: "{}"
        if (response.code == 403) {
            throw Exception("Accès refusé — Wi‑Fi maison ou VPN Plexi requis")
        }
        gson.fromJson(bodyStr, LoginResponse::class.java)
    }

    suspend fun me(): MeResponse = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(baseURL + "api/me")
            .get()
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()
        val response = client.newCall(request).execute()
        val bodyStr = response.body?.string() ?: "{}"
        gson.fromJson(bodyStr, MeResponse::class.java)
    }

    suspend fun checkins(): List<CheckinItem> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(baseURL + "api/checkins")
            .get()
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()
        val response = client.newCall(request).execute()
        val bodyStr = response.body?.string() ?: "[]"
        val listType = object : com.google.gson.reflect.TypeToken<List<CheckinItem>>() {}.type
        gson.fromJson(bodyStr, listType)
    }

    suspend fun createCheckin(data: Map<String, Any>): CreateCheckinResult = withContext(Dispatchers.IO) {
        val json = gson.toJson(data)
        val body = json.toRequestBody(JSON)
        val request = Request.Builder()
            .url(baseURL + "api/checkins")
            .post(body)
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .build()
        val response = client.newCall(request).execute()
        val bodyStr = response.body?.string() ?: "{}"
        gson.fromJson(bodyStr, CreateCheckinResult::class.java)
    }
}

data class LoginResponse(val ok: Boolean?, val user: String?, val is_admin: Boolean?, val error: String?)
data class MeResponse(val user: String?, val auth: Boolean, val is_admin: Boolean, val is_invite: Boolean)
data class CheckinItem(val id: Int, val beer_name: String, val brewery: String, val style: String, val rating: Double?, val comment: String?)
data class CreateCheckinResult(val ok: Boolean?, val duplicate: Boolean?, val error: String?)