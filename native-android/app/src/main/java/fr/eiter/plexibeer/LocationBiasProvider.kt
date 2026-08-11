package fr.eiter.plexibeer

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.core.content.ContextCompat

/**
 * Biais de proximité (lat/lon approx.) pour la recherche de lieu OSM/Photon.
 * Best-effort : `getLastKnownLocation` (pas de dépendance Play Services), jamais bloquant.
 */
object LocationBiasProvider {
    var lat: Double? = null
        private set
    var lon: Double? = null
        private set

    fun refresh(context: Context) {
        val hasPermission =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            val loc = providers.firstNotNullOfOrNull { manager.getLastKnownLocation(it) }
            if (loc != null) {
                lat = loc.latitude
                lon = loc.longitude
            }
        } catch (e: SecurityException) {
            // Permission révoquée entre-temps : pas bloquant.
        }
    }
}
