package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/** Lightweight disk cache for read-only browsing offline (mirrors BeerOfflineCache spirit). */
class OfflineCache(context: Context) {
    private val dir = File(context.applicationContext.filesDir, "cache").apply { mkdirs() }
    private val gson = Gson()

    fun saveCheckins(items: List<CheckinItem>) = write("checkins.json", items)
    fun loadCheckins(): List<CheckinItem> {
        val f = File(dir, "checkins.json")
        if (!f.exists()) return emptyList()
        return try {
            val type = object : TypeToken<List<CheckinItem>>() {}.type
            gson.fromJson(f.readText(), type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveStats(stats: HistoryStats) = write("stats.json", stats)
    fun loadStats(): HistoryStats? = readOne("stats.json", HistoryStats::class.java)

    fun saveCouple(stats: CoupleStats) = write("couple.json", stats)
    fun loadCouple(): CoupleStats? = readOne("couple.json", CoupleStats::class.java)

    fun saveWishlist(items: List<WishlistItem>) = write("wishlist.json", items)
    fun loadWishlist(): List<WishlistItem> {
        val f = File(dir, "wishlist.json")
        if (!f.exists()) return emptyList()
        return try {
            val type = object : TypeToken<List<WishlistItem>>() {}.type
            gson.fromJson(f.readText(), type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun write(name: String, obj: Any) {
        try {
            File(dir, name).writeText(gson.toJson(obj))
        } catch (_: Exception) {
        }
    }

    private fun <T> readOne(name: String, clazz: Class<T>): T? {
        val f = File(dir, name)
        if (!f.exists()) return null
        return try {
            gson.fromJson(f.readText(), clazz)
        } catch (_: Exception) {
            null
        }
    }
}
