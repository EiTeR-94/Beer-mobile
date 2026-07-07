package fr.eiter.plexibeer

object ServerSettings {
    const val CANONICAL_HOST = "eiter.freeboxos.fr"
    const val WAN_IPV4 = "82.64.151.113"

    const val API_BASE_STRING = "https://$CANONICAL_HOST/beer/"

    val apiBase: String get() = API_BASE_STRING

    // For local accounts on WiFi/VPN - direct or domain:8444
    // Using direct IP for reliability like the iOS fix
    const val LAN_API_BASE = "https://192.168.1.50:8444/beer/"

    val candidateURLs: List<String> = listOf(LAN_API_BASE, apiBase)

    // For guests on 5G
    val passkeyBaseURLs: List<String> = listOf(apiBase)

    fun isLanEndpoint(url: String): Boolean {
        return url.contains(":8444")
    }

    fun normalizeInput(raw: String): String {
        var s = raw.trim().trimEnd('/')
        return "$s/"
    }
}