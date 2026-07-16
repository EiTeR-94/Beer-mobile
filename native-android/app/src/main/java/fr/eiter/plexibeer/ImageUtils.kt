package fr.eiter.plexibeer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import java.io.File

/** Mirrors iOS BeerImageUtils.compressJPEG */
object ImageUtils {
    fun compressJPEG(input: ByteArray, maxDimension: Int = 1600, quality: Int = 82): ByteArray {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(input, 0, input.size, opts)
        val w = opts.outWidth
        val h = opts.outHeight
        if (w <= 0 || h <= 0) return input

        var sample = 1
        val maxSide = maxOf(w, h)
        while (maxSide / sample > maxDimension * 2) sample *= 2

        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = BitmapFactory.decodeByteArray(input, 0, input.size, decodeOpts) ?: return input
        val scaled = if (maxOf(bmp.width, bmp.height) > maxDimension) {
            val scale = maxDimension.toFloat() / maxOf(bmp.width, bmp.height)
            val nw = (bmp.width * scale).toInt().coerceAtLeast(1)
            val nh = (bmp.height * scale).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(bmp, nw, nh, true).also {
                if (it !== bmp) bmp.recycle()
            }
        } else bmp

        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
        if (scaled !== bmp) scaled.recycle()
        return out.toByteArray()
    }

    fun compressFile(file: File, maxDimension: Int = 1600, quality: Int = 82): File {
        val bytes = compressJPEG(file.readBytes(), maxDimension, quality)
        val out = File(file.parentFile, "compressed_${file.name}")
        out.writeBytes(bytes)
        return out
    }
}
