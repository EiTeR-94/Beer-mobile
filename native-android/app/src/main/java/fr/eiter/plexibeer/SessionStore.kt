package fr.eiter.plexibeer

import android.content.Context
import android.content.SharedPreferences
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent cookie jar for beer_session (+ any other cookies),
 * mirroring iOS HTTPCookieStorage + explicit login Set-Cookie handling.
 */
class SessionCookieJar(context: Context) : CookieJar {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("beer_session_cookies", Context.MODE_PRIVATE)

    private val lock = Any()
    private val store = mutableMapOf<String, MutableList<Cookie>>() // host -> cookies

    init {
        load()
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        synchronized(lock) {
            val host = url.host
            val list = store.getOrPut(host) { mutableListOf() }
            for (c in cookies) {
                list.removeAll { it.name == c.name }
                // expired cookie => remove
                if (c.expiresAt > System.currentTimeMillis()) {
                    list.add(c)
                }
            }
            // Also index under LAN IP / domain so cookie works across candidates
            for (alias in aliasHosts(host)) {
                if (alias == host) continue
                val al = store.getOrPut(alias) { mutableListOf() }
                for (c in cookies) {
                    al.removeAll { it.name == c.name }
                    if (c.expiresAt > System.currentTimeMillis()) {
                        val rebuilt = try {
                            Cookie.Builder()
                                .name(c.name)
                                .value(c.value)
                                .path(c.path)
                                .expiresAt(c.expiresAt)
                                .apply {
                                    if (c.secure) secure()
                                    if (c.httpOnly) httpOnly()
                                    hostOnlyDomain(alias)
                                }
                                .build()
                        } catch (_: Exception) {
                            c
                        }
                        al.add(rebuilt)
                    }
                }
            }
            persist()
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            val result = mutableListOf<Cookie>()
            val hosts = linkedSetOf(url.host).apply { addAll(aliasHosts(url.host)) }
            for (h in hosts) {
                val list = store[h] ?: continue
                list.removeAll { it.expiresAt <= now }
                for (c in list) {
                    // Prefer exact host match; always inject beer_session
                    if (c.name == "beer_session" || c.matches(url) || ServerSettings.isLanHost(url.host)) {
                        if (result.none { it.name == c.name }) {
                            result.add(c)
                        }
                    }
                }
            }
            // Force beer_session header path: ensure cookie present even if domain mismatch
            if (result.none { it.name == "beer_session" }) {
                findBeerSession()?.let { result.add(it) }
            }
            return result
        }
    }

    fun beerSessionCookieHeader(): String? {
        synchronized(lock) {
            return findBeerSession()?.let { "beer_session=${it.value}" }
        }
    }

    fun hasSession(): Boolean = beerSessionCookieHeader() != null

    fun clear() {
        synchronized(lock) {
            store.clear()
            prefs.edit().clear().apply()
        }
    }

    private fun findBeerSession(): Cookie? {
        val now = System.currentTimeMillis()
        for ((_, list) in store) {
            val c = list.firstOrNull { it.name == "beer_session" && it.expiresAt > now }
            if (c != null) return c
        }
        return null
    }

    private fun aliasHosts(host: String): List<String> {
        return listOf(
            host,
            "192.168.1.50",
            ServerSettings.CANONICAL_HOST,
            ServerSettings.WAN_IPV4
        ).distinct()
    }

    private fun persist() {
        val arr = JSONArray()
        for ((host, list) in store) {
            for (c in list) {
                val o = JSONObject()
                o.put("host", host)
                o.put("name", c.name)
                o.put("value", c.value)
                o.put("path", c.path)
                o.put("secure", c.secure)
                o.put("httpOnly", c.httpOnly)
                o.put("expiresAt", c.expiresAt)
                o.put("hostOnly", c.hostOnly)
                o.put("domain", c.domain)
                arr.put(o)
            }
        }
        prefs.edit().putString("cookies", arr.toString()).apply()
    }

    private fun load() {
        val raw = prefs.getString("cookies", null) ?: return
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val host = o.getString("host")
                val builder = Cookie.Builder()
                    .name(o.getString("name"))
                    .value(o.getString("value"))
                    .path(o.optString("path", "/"))
                    .expiresAt(o.optLong("expiresAt", Long.MAX_VALUE / 2))
                if (o.optBoolean("secure", true)) builder.secure()
                if (o.optBoolean("httpOnly", true)) builder.httpOnly()
                val domain = o.optString("domain", host)
                try {
                    if (o.optBoolean("hostOnly", true)) builder.hostOnlyDomain(host)
                    else builder.domain(domain)
                } catch (_: Exception) {
                    try {
                        builder.hostOnlyDomain(host)
                    } catch (_: Exception) {
                        continue
                    }
                }
                val cookie = try {
                    builder.build()
                } catch (_: Exception) {
                    continue
                }
                store.getOrPut(host) { mutableListOf() }.add(cookie)
            }
        } catch (_: Exception) {
            // corrupt store
            prefs.edit().clear().apply()
        }
    }
}

/** Lightweight identity restore (username / admin) like BeerSessionStore. */
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
