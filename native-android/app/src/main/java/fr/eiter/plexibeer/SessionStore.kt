package fr.eiter.plexibeer

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.Response

/**
 * Session beer_session — miroir iOS (HTTPCookieStorage + force Cookie header).
 *
 * Problème serveur : BEER_COOKIE_DOMAIN=eiter.freeboxos.fr
 * → Set-Cookie Domain=eiter.freeboxos.fr même si on login sur 192.168.1.50
 * → OkHttp rejette le cookie (domain ≠ host IP) avant CookieJar.
 *
 * Solution : parser Set-Cookie à la main, stocker le token, l'injecter sur chaque requête.
 */
class SessionCookieJar(context: Context) : CookieJar {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val lock = Any()

    @Volatile
    private var token: String? = null

    @Volatile
    private var cookiePath: String = "/beer"

    init {
        token = prefs.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }
        cookiePath = prefs.getString(KEY_PATH, "/beer") ?: "/beer"
        if (token != null) {
            Log.i(TAG, "session restored from prefs (token len=${token!!.length}, path=$cookiePath)")
        }
    }

    fun hasSession(): Boolean = !token.isNullOrBlank()

    fun beerSessionCookieHeader(): String? {
        val t = token ?: return null
        return "beer_session=$t"
    }

    fun sessionToken(): String? = token

    fun clear() {
        synchronized(lock) {
            token = null
            cookiePath = "/beer"
            prefs.edit().clear().apply()
            Log.i(TAG, "session cleared")
        }
    }

    /**
     * Parse raw Set-Cookie headers (call on every successful login / any response).
     * Does NOT depend on OkHttp domain matching.
     */
    fun ingestSetCookieHeaders(headers: List<String>) {
        if (headers.isEmpty()) return
        synchronized(lock) {
            for (raw in headers) {
                // "beer_session=xxx; path=/beer; ... Domain=..."
                val nameValue = raw.substringBefore(';').trim()
                val eq = nameValue.indexOf('=')
                if (eq <= 0) continue
                val name = nameValue.substring(0, eq).trim()
                val value = nameValue.substring(eq + 1).trim()
                if (name != COOKIE_NAME || value.isEmpty()) continue

                // empty value / delete cookie
                if (value == "null" || value.length < 8) {
                    // short values might be delete markers
                    val maxAge = Regex("""(?i)max-age=(\d+)""").find(raw)?.groupValues?.get(1)?.toLongOrNull()
                    if (maxAge == 0L || value.isEmpty()) {
                        token = null
                        prefs.edit().remove(KEY_TOKEN).apply()
                        Log.i(TAG, "session cookie deleted via Set-Cookie")
                        continue
                    }
                }

                token = value
                val pathMatch = Regex("""(?i);\s*path=([^;]+)""").find(raw)
                if (pathMatch != null) {
                    cookiePath = pathMatch.groupValues[1].trim().ifBlank { "/beer" }
                }
                prefs.edit()
                    .putString(KEY_TOKEN, value)
                    .putString(KEY_PATH, cookiePath)
                    .apply()
                Log.i(TAG, "session cookie saved (len=${value.length}, path=$cookiePath)")
            }
        }
    }

    /** Convenience: read Set-Cookie from OkHttp Response */
    fun ingestResponse(response: Response) {
        ingestSetCookieHeaders(response.headers("Set-Cookie"))
    }

    fun saveToken(value: String, path: String = cookiePath) {
        synchronized(lock) {
            token = value
            cookiePath = path.ifBlank { "/beer" }
            prefs.edit()
                .putString(KEY_TOKEN, value)
                .putString(KEY_PATH, cookiePath)
                .apply()
        }
    }

    /**
     * CookieJar contract: always emit beer_session for our hosts so OkHttp
     * attaches it even if Domain on server cookie wouldn't match LAN IP.
     */
    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        // Secondary path — usually empty for Domain-mismatched cookies.
        for (c in cookies) {
            if (c.name == COOKIE_NAME && c.value.isNotBlank()) {
                saveToken(c.value, c.path)
            }
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val t = token ?: return emptyList()
        if (!isBeerHost(url.host)) return emptyList()
        return try {
            val builder = Cookie.Builder()
                .name(COOKIE_NAME)
                .value(t)
                .path(normalizePath(cookiePath))
                .hostOnlyDomain(url.host)
                .expiresAt(System.currentTimeMillis() + THIRTY_DAYS_MS)
            // Always mark secure for HTTPS beer endpoints
            if (url.isHttps) builder.secure()
            builder.httpOnly()
            listOf(builder.build())
        } catch (e: Exception) {
            Log.w(TAG, "build cookie for ${url.host}: ${e.message}")
            emptyList()
        }
    }

    private fun normalizePath(p: String): String {
        val s = p.trim().ifBlank { "/beer" }
        return if (s.startsWith("/")) s else "/$s"
    }

    private fun isBeerHost(host: String): Boolean {
        return host == "192.168.1.50" ||
            host == ServerSettings.CANONICAL_HOST ||
            host == ServerSettings.WAN_IPV4 ||
            host.endsWith("freeboxos.fr") ||
            ServerSettings.isLanHost(host)
    }

    companion object {
        private const val TAG = "BeerSession"
        private const val PREFS = "beer_session_v2"
        private const val KEY_TOKEN = "beer_session_token"
        private const val KEY_PATH = "beer_session_path"
        private const val COOKIE_NAME = "beer_session"
        private const val THIRTY_DAYS_MS = 30L * 24 * 3600 * 1000
    }
}

/** Lightweight identity restore (username / admin) like BeerSessionStore iOS. */
object BeerSessionStore {
    private const val PREFS = "beer_session_identity"

    fun save(context: Context, user: String, isAdmin: Boolean) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("user", user)
            .putBoolean("is_admin", isAdmin)
            .putBoolean("logged_in", true)
            .apply()
    }

    fun restore(context: Context): Triple<String, Boolean, Boolean>? {
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!p.getBoolean("logged_in", false)) return null
        val user = p.getString("user", null) ?: return null
        return Triple(user, p.getBoolean("is_admin", false), true)
    }

    fun clear(context: Context) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().clear().apply()
    }
}
