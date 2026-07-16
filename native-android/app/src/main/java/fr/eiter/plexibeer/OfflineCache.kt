package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Cache lecture hors ligne (historique, stats, galerie, wishlist, cadeaux, styles).
 * Enveloppe avec timestamp comme iOS BeerOfflineCache.
 */
class OfflineCache(context: Context) {
    private val dir = File(context.applicationContext.filesDir, "offline-cache").apply { mkdirs() }
    private val gson = Gson()

    companion object {
        const val KEY_CHECKINS = "history_checkins"
        const val KEY_STATS = "history_stats"
        const val KEY_COUPLE = "gifts"
        const val KEY_WISHLIST = "wishlist"
        const val KEY_STYLES = "styles"
        /** 7 jours — bars / week-end sans ouvrir l'app */
        const val MAX_AGE_MS = 7L * 24 * 3600 * 1000
        /** 24 h pour stats (moins critiques) */
        const val MAX_AGE_STATS_MS = 24L * 3600 * 1000
    }

    private data class Envelope(
        val savedAtMs: Long = System.currentTimeMillis(),
        val payloadJson: String = ""
    )

    fun saveCheckins(items: List<CheckinItem>) = save(KEY_CHECKINS, items)
    fun loadCheckins(maxAgeMs: Long = MAX_AGE_MS): List<CheckinItem> =
        loadList(KEY_CHECKINS, maxAgeMs) ?: emptyList()

    fun saveStats(stats: HistoryStats) = save(KEY_STATS, stats)
    fun loadStats(maxAgeMs: Long = MAX_AGE_STATS_MS): HistoryStats? =
        loadOne(KEY_STATS, HistoryStats::class.java, maxAgeMs)

    fun saveCouple(stats: CoupleStats) = save(KEY_COUPLE, stats)
    fun loadCouple(maxAgeMs: Long = MAX_AGE_MS): CoupleStats? =
        loadOne(KEY_COUPLE, CoupleStats::class.java, maxAgeMs)

    fun saveWishlist(items: List<WishlistItem>) = save(KEY_WISHLIST, items)
    fun loadWishlist(maxAgeMs: Long = MAX_AGE_MS): List<WishlistItem> =
        loadList(KEY_WISHLIST, maxAgeMs) ?: emptyList()

    fun saveStyles(items: List<StyleOption>) = save(KEY_STYLES, items)
    fun loadStyles(maxAgeMs: Long = MAX_AGE_MS): List<StyleOption> =
        loadList(KEY_STYLES, maxAgeMs) ?: emptyList()

    fun remove(key: String) {
        try {
            File(dir, "$key.json").delete()
        } catch (_: Exception) {
        }
    }

    fun invalidateHistory() {
        remove(KEY_CHECKINS)
        remove(KEY_STATS)
    }

    fun prune(maxFiles: Int = 20) {
        try {
            val files = dir.listFiles()?.sortedByDescending { it.lastModified() } ?: return
            files.drop(maxFiles).forEach { it.delete() }
        } catch (_: Exception) {
        }
    }

    private fun save(name: String, obj: Any) {
        try {
            val env = Envelope(
                savedAtMs = System.currentTimeMillis(),
                payloadJson = gson.toJson(obj)
            )
            File(dir, "$name.json").writeText(gson.toJson(env))
        } catch (_: Exception) {
        }
    }

    private fun readEnvelope(name: String, maxAgeMs: Long?): Envelope? {
        val f = File(dir, "$name.json")
        if (!f.exists()) return null
        return try {
            val env = gson.fromJson(f.readText(), Envelope::class.java) ?: return null
            if (maxAgeMs != null && System.currentTimeMillis() - env.savedAtMs > maxAgeMs) {
                f.delete()
                return null
            }
            if (env.payloadJson.isBlank()) return null
            env
        } catch (_: Exception) {
            // Legacy format: raw JSON without envelope
            try {
                val raw = f.readText()
                if (raw.isBlank()) return null
                Envelope(savedAtMs = f.lastModified(), payloadJson = raw)
            } catch (_: Exception) {
                null
            }
        }
    }

    private inline fun <reified T> loadList(name: String, maxAgeMs: Long?): List<T>? {
        val env = readEnvelope(name, maxAgeMs) ?: return null
        return try {
            val type = object : TypeToken<List<T>>() {}.type
            gson.fromJson(env.payloadJson, type)
        } catch (_: Exception) {
            null
        }
    }

    private fun <T> loadOne(name: String, clazz: Class<T>, maxAgeMs: Long?): T? {
        val env = readEnvelope(name, maxAgeMs) ?: return null
        return try {
            gson.fromJson(env.payloadJson, clazz)
        } catch (_: Exception) {
            null
        }
    }
}
