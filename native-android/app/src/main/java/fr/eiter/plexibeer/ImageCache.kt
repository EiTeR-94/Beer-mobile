package fr.eiter.plexibeer

import android.content.Context
import java.io.File
import java.security.MessageDigest

/**
 * Cache disque des photos serveur (chemins relatifs type photos/xxx.jpg).
 * Permet d'afficher la galerie / historique hors ligne après un passage en ligne.
 */
class ImageCache private constructor(context: Context) {
    private val dir = File(context.applicationContext.filesDir, "image-cache").apply { mkdirs() }

    companion object {
        @Volatile private var INSTANCE: ImageCache? = null

        fun getInstance(context: Context): ImageCache =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: ImageCache(context.applicationContext).also { INSTANCE = it }
            }

        private const val MAX_FILES = 120
    }

    fun get(path: String?): ByteArray? {
        if (path.isNullOrBlank()) return null
        val f = fileFor(path)
        if (!f.exists() || f.length() == 0L) return null
        return try {
            f.readBytes()
        } catch (_: Exception) {
            null
        }
    }

    fun put(path: String?, bytes: ByteArray?) {
        if (path.isNullOrBlank() || bytes == null || bytes.isEmpty()) return
        try {
            val f = fileFor(path)
            f.writeBytes(bytes)
            pruneIfNeeded()
        } catch (_: Exception) {
        }
    }

    fun has(path: String?): Boolean {
        if (path.isNullOrBlank()) return false
        val f = fileFor(path)
        return f.exists() && f.length() > 0
    }

    fun pruneIfNeeded(maxFiles: Int = MAX_FILES) {
        try {
            val files = dir.listFiles() ?: return
            if (files.size <= maxFiles) return
            files.sortedBy { it.lastModified() }
                .take(files.size - maxFiles)
                .forEach { it.delete() }
        } catch (_: Exception) {
        }
    }

    private fun fileFor(path: String): File {
        val name = path.substringAfterLast('/').ifBlank { path }
        val safe = name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val hash = sha1(path).take(10)
        return File(dir, "${hash}_$safe")
    }

    private fun sha1(s: String): String {
        return try {
            val d = MessageDigest.getInstance("SHA-1").digest(s.toByteArray())
            d.joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            s.hashCode().toUInt().toString(16)
        }
    }
}
