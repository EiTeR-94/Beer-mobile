package fr.eiter.plexibeer

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.concurrent.ConcurrentHashMap

/**
 * SharedPreferences chiffrées au repos (AES256-GCM via Android Keystore), avec
 * migration one-shot depuis un store en clair du même type (nom différent —
 * jamais le même nom qu'un store chiffré, pour ne pas mélanger clair/chiffré
 * dans le même fichier). Même pattern que VivinoTokenStore (WeenoBis).
 */
object SecurePrefs {
    private const val TAG = "SecurePrefs"
    private val cache = ConcurrentHashMap<String, SharedPreferences>()

    @Volatile
    private var masterKey: MasterKey? = null

    private fun masterKey(ctx: Context): MasterKey {
        masterKey?.let { return it }
        synchronized(this) {
            masterKey?.let { return it }
            val mk = MasterKey.Builder(ctx.applicationContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            masterKey = mk
            return mk
        }
    }

    /**
     * Ouvre (ou crée) le store chiffré [securedName], en migrant une seule fois
     * les valeurs de l'ancien store en clair [legacyName] si celui-ci contient
     * encore des données, puis l'efface.
     */
    fun open(context: Context, securedName: String, legacyName: String): SharedPreferences {
        cache[securedName]?.let { return it }
        synchronized(this) {
            cache[securedName]?.let { return it }
            val app = context.applicationContext
            val prefs = EncryptedSharedPreferences.create(
                app,
                securedName,
                masterKey(app),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            migrateLegacy(app, legacyName, prefs)
            cache[securedName] = prefs
            return prefs
        }
    }

    private fun migrateLegacy(app: Context, legacyName: String, secure: SharedPreferences) {
        val legacy = app.getSharedPreferences(legacyName, Context.MODE_PRIVATE)
        val all = legacy.all
        if (all.isEmpty()) return
        try {
            val ed = secure.edit()
            for ((k, v) in all) {
                when (v) {
                    is String -> ed.putString(k, v)
                    is Boolean -> ed.putBoolean(k, v)
                    is Int -> ed.putInt(k, v)
                    is Long -> ed.putLong(k, v)
                    is Float -> ed.putFloat(k, v)
                    is Set<*> -> @Suppress("UNCHECKED_CAST") ed.putStringSet(k, v as Set<String>)
                }
            }
            ed.apply()
            legacy.edit().clear().apply()
            Log.i(TAG, "migrated $legacyName -> encrypted store (${all.size} clé(s))")
        } catch (e: Exception) {
            // Ne jamais logger les valeurs elles-mêmes
            Log.w(TAG, "migration failed for $legacyName: ${e.javaClass.simpleName}")
        }
    }
}
