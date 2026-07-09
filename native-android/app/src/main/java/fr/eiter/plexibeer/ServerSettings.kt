package fr.eiter.plexibeer

object ServerSettings {
    const val CANONICAL_HOST = "eiter.freeboxos.fr"
    const val WAN_IPV4 = "82.64.151.113"

    const val API_BASE_STRING = "https://$CANONICAL_HOST/beer/"

    val apiBase: String get() = API_BASE_STRING

    // Owner only: LAN / VPN path (direct IP for reliability, same as iOS fixes)
    const val LAN_API_BASE = "https://192.168.1.50:8444/beer/"

    // Runtime override for easy testing on emulators / different machines (Windows, etc.)
    // Default = LAN. Change via UI in test stub or call setRuntimeBase(...)
    @Volatile
    private var runtimeBase: String? = null

    val effectiveBase: String
        get() = runtimeBase ?: LAN_API_BASE

    val candidateURLs: List<String> = listOf(LAN_API_BASE, apiBase)

    // No guest/passkey paths in native (owner-only). PWA web for invites.
    val passkeyBaseURLs: List<String> = listOf(apiBase)

    fun isLanEndpoint(url: String): Boolean {
        return url.contains(":8444")
    }

    fun normalizeInput(raw: String): String {
        var s = raw.trim().trimEnd('/')
        return "$s/"
    }

    /** For testing on emulator or other setups. Pass null or empty to reset to LAN. */
    fun setRuntimeBase(url: String?) {
        runtimeBase = if (url.isNullOrBlank()) null else normalizeInput(url)
    }

    fun resetToLan() {
        runtimeBase = null
    }

    fun useEffectiveBaseIfNeeded() {
        // Default to LAN for real devices and emulators on same network
        if (runtimeBase == null) {
            // already using LAN_API_BASE via effectiveBase
        }
    }
}