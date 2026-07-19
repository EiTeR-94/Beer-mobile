package fr.eiter.plexibeer

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import java.security.SecureRandom
import java.util.UUID

/**
 * Session invité APK — Bearer device-bound (WAN 4G/5G).
 * device_id stable généré une fois et renvoyé à chaque /api/native/join.
 */
object InviteSessionStore {
    private const val TAG = "InviteSession"
    private const val PREFS = "beer_invite_session_v1"
    private const val KEY_TOKEN = "access_token"
    private const val KEY_DEVICE = "device_id"
    private const val KEY_USER = "user"
    private const val KEY_LABEL = "label"
    private const val KEY_EXPIRES = "expires_at"
    private const val KEY_ACTIVE = "active"
    /** Base API (beer/ ou beer-alpha/) pour rester sur le bon backend après restart. */
    private const val KEY_API_BASE = "api_base"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Identifiant appareil stable (16–64 chars url-safe). */
    fun deviceId(context: Context): String {
        val p = prefs(context)
        val existing = p.getString(KEY_DEVICE, null)?.takeIf { it.length in 16..64 }
        if (existing != null) return existing
        val raw = ByteArray(24)
        SecureRandom().nextBytes(raw)
        val id = Base64.encodeToString(raw, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            .take(32)
            .ifBlank { "d" + UUID.randomUUID().toString().replace("-", "").take(31) }
        p.edit().putString(KEY_DEVICE, id).apply()
        Log.i(TAG, "generated device_id len=${id.length}")
        return id
    }

    fun hasInviteSession(context: Context): Boolean {
        val p = prefs(context)
        return p.getBoolean(KEY_ACTIVE, false) &&
            !p.getString(KEY_TOKEN, null).isNullOrBlank()
    }

    fun accessToken(context: Context): String? =
        prefs(context).getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }

    fun username(context: Context): String? =
        prefs(context).getString(KEY_USER, null)

    fun label(context: Context): String? =
        prefs(context).getString(KEY_LABEL, null)

    fun expiresAt(context: Context): String? =
        prefs(context).getString(KEY_EXPIRES, null)

    fun apiBase(context: Context): String? =
        prefs(context).getString(KEY_API_BASE, null)?.takeIf { it.isNotBlank() }

    fun save(
        context: Context,
        accessToken: String,
        user: String,
        label: String?,
        expiresAt: String?,
        deviceId: String,
        apiBase: String? = null
    ) {
        val ed = prefs(context).edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_TOKEN, accessToken)
            .putString(KEY_USER, user)
            .putString(KEY_LABEL, label)
            .putString(KEY_EXPIRES, expiresAt)
            .putString(KEY_DEVICE, deviceId)
        if (!apiBase.isNullOrBlank()) {
            ed.putString(KEY_API_BASE, ServerSettings.normalizeInput(apiBase))
        }
        ed.apply()
        Log.i(TAG, "invite session saved user=$user base=${apiBase ?: "?"}")
    }

    fun clear(context: Context) {
        val device = prefs(context).getString(KEY_DEVICE, null)
        prefs(context).edit().clear().apply()
        // Conserver le device_id pour rebind / réactivation
        if (!device.isNullOrBlank()) {
            prefs(context).edit().putString(KEY_DEVICE, device).apply()
        }
        Log.i(TAG, "invite session cleared (device kept)")
    }

    /** Extrait le token d'invite depuis une URL join ou un token brut. */
    fun parseInviteToken(raw: String): String? {
        val s = raw.trim()
        if (s.isEmpty()) return null
        // https://eiter.freeboxos.fr/beer/join/TOKEN
        val joinIdx = s.indexOf("/join/")
        if (joinIdx >= 0) {
            val after = s.substring(joinIdx + "/join/".length)
            val token = after.substringBefore('?').substringBefore('#').substringBefore('/').trim()
            return token.takeIf { it.length in 24..64 && it.matches(Regex("^[A-Za-z0-9_-]+$")) }
        }
        return s.takeIf { it.length in 24..64 && it.matches(Regex("^[A-Za-z0-9_-]+$")) }
    }
}
