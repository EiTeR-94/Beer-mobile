package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * File offline (créations + suppressions), persistée disque.
 * [onChanged] notifie l'UI (badge « En attente ») après chaque mutation.
 */
class OfflineQueue(
    context: Context,
    private val onChanged: (() -> Unit)? = null
) {
    private val dir = File(context.applicationContext.filesDir, "offline").apply { mkdirs() }
    private val createsFile = File(dir, "pending-checkins.json")
    private val deletesFile = File(dir, "pending-deletes.json")
    private val photosDir = File(dir, "photos").apply { mkdirs() }
    private val gson = Gson()
    private val lock = Any()

    @Volatile
    var items: List<PendingCheckin> = emptyList()
        private set

    @Volatile
    var pendingDeletes: List<Int> = emptyList()
        private set

    val pendingCount: Int get() = items.size + pendingDeletes.size

    init {
        load()
    }

    fun load() {
        synchronized(lock) {
            items = readList(createsFile)
            pendingDeletes = readIntList(deletesFile)
        }
        notifyChanged()
    }

    fun enqueue(item: PendingCheckin) {
        synchronized(lock) {
            if (items.any {
                    it.beerName == item.beerName &&
                        it.rating == item.rating &&
                        it.comment == item.comment &&
                        kotlin.math.abs(it.createdAtMs - item.createdAtMs) < 180_000
                }) return
            var final = item
            val src = item.photoPath?.let { File(it) }
            if (src != null && src.exists()) {
                val dest = File(photosDir, "${item.id}.jpg")
                try {
                    src.copyTo(dest, overwrite = true)
                    final = item.copy(photoPath = dest.absolutePath)
                } catch (_: Exception) {
                    // keep original path
                }
            }
            items = items + final
            persistCreates()
        }
        notifyChanged()
    }

    fun remove(id: String) {
        synchronized(lock) {
            val removed = items.filter { it.id == id }
            items = items.filterNot { it.id == id }
            removed.forEach { p ->
                p.photoPath?.let { path ->
                    try {
                        File(path).delete()
                    } catch (_: Exception) {
                    }
                }
            }
            persistCreates()
        }
        notifyChanged()
    }

    fun enqueueDelete(checkinId: Int) {
        synchronized(lock) {
            if (checkinId !in pendingDeletes) {
                pendingDeletes = pendingDeletes + checkinId
                persistDeletes()
            }
        }
        notifyChanged()
    }

    fun removePendingDelete(checkinId: Int) {
        synchronized(lock) {
            pendingDeletes = pendingDeletes.filterNot { it == checkinId }
            persistDeletes()
        }
        notifyChanged()
    }

    /**
     * Envoie les actions en attente. Retourne le nombre d'actions réussies.
     * S'arrête au premier échec réseau (les suivantes restent en file).
     */
    suspend fun flush(api: BeerAPI): Int {
        var okCount = 0
        val creates = synchronized(lock) { items.toList() }
        for (item in creates) {
            try {
                val photoBytes = item.photoPath?.let { path ->
                    val f = File(path)
                    if (f.exists()) f.readBytes() else null
                }
                val photoCompressed = photoBytes?.let { ImageUtils.compressJPEG(it) }
                val result = api.createCheckin(
                    barcode = item.barcode,
                    beerName = item.beerName,
                    brewery = item.brewery,
                    style = item.style,
                    abv = item.abv,
                    summary = item.summary,
                    rating = item.rating,
                    flavors = item.flavors,
                    hops = item.hops,
                    comment = item.comment,
                    untappdBid = item.untappdBid,
                    force = item.force,
                    photoJPEG = photoCompressed,
                    location = item.location.orEmpty()
                )
                // Succès ou doublon déjà traité côté serveur → sortir de la file
                if (result.ok == true || result.id != null || result.duplicate == true) {
                    remove(item.id)
                    okCount++
                } else {
                    break
                }
            } catch (_: Exception) {
                break
            }
        }
        val deletes = synchronized(lock) { pendingDeletes.toList() }
        for (id in deletes) {
            try {
                api.deleteCheckin(id)
                removePendingDelete(id)
                okCount++
            } catch (_: Exception) {
                break
            }
        }
        return okCount
    }

    private fun notifyChanged() {
        try {
            onChanged?.invoke()
        } catch (_: Exception) {
        }
    }

    private fun persistCreates() {
        try {
            createsFile.writeText(gson.toJson(items))
        } catch (_: Exception) {
        }
    }

    private fun persistDeletes() {
        try {
            deletesFile.writeText(gson.toJson(pendingDeletes))
        } catch (_: Exception) {
        }
    }

    private fun readList(file: File): List<PendingCheckin> {
        if (!file.exists()) return emptyList()
        return try {
            val type = object : TypeToken<List<PendingCheckin>>() {}.type
            gson.fromJson(file.readText(), type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readIntList(file: File): List<Int> {
        if (!file.exists()) return emptyList()
        return try {
            val type = object : TypeToken<List<Int>>() {}.type
            gson.fromJson(file.readText(), type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }
}
