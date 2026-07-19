package fr.eiter.plexibeer

object ServerSettings {
    const val CANONICAL_HOST = "eiter.freeboxos.fr"
    const val WAN_IPV4 = "82.64.151.113"
    const val API_BASE_STRING = "https://$CANONICAL_HOST/beer/"
    /** Fallback 4G si AAAA Freebox casse le TLS (IPv4 + SNI host). */
    const val WAN_IPV4_API_BASE = "https://$WAN_IPV4/beer/"
    const val LAN_API_BASE = "https://192.168.1.50:8444/beer/"
    /** Beerquest alpha (clone isolé) — invites IPA/APK */
    const val ALPHA_API_BASE_STRING = "https://$CANONICAL_HOST/beer-alpha/"
    const val ALPHA_WAN_IPV4_API_BASE = "https://$WAN_IPV4/beer-alpha/"
    const val LAN_PROBE_TIMEOUT_SEC = 15L

    @Volatile
    private var runtimeBase: String? = null

    /** Mode invité : forcer WAN (jamais LAN Freebox). */
    @Volatile
    var inviteMode: Boolean = false

    val effectiveBase: String
        get() = when {
            inviteMode -> runtimeBase?.takeIf { !isLanEndpoint(it) } ?: API_BASE_STRING
            else -> runtimeBase ?: LAN_API_BASE
        }

    val candidateURLs: List<String>
        get() = if (inviteMode) {
            // Prefer last successful runtime base (prod beer or beer-alpha)
            val primary = runtimeBase?.takeIf { !isLanEndpoint(it) } ?: API_BASE_STRING
            val alt = if (isAlphaBase(primary)) {
                listOf(primary, ALPHA_WAN_IPV4_API_BASE)
            } else {
                listOf(primary, WAN_IPV4_API_BASE)
            }
            alt.distinct()
        } else {
            listOf(LAN_API_BASE, API_BASE_STRING)
        }

    val inviteCandidateURLs: List<String>
        get() = listOf(API_BASE_STRING, WAN_IPV4_API_BASE, ALPHA_API_BASE_STRING, ALPHA_WAN_IPV4_API_BASE)

    fun isAlphaBase(url: String): Boolean =
        url.contains("/beer-alpha")

    /**
     * Déduit la base API depuis un lien d'invitation.
     * https://host/beer-alpha/join/TOKEN → https://host/beer-alpha/
     * https://host/beer/join/TOKEN → https://host/beer/
     */
    fun basesFromInviteLink(link: String): List<String> {
        val s = link.trim()
        val joinIdx = s.indexOf("/join/")
        if (joinIdx < 0) return inviteCandidateURLs
        val prefix = s.substring(0, joinIdx).trimEnd('/')
        // prefix = https://host[/path]
        val isAlpha = prefix.endsWith("/beer-alpha") || prefix.contains("/beer-alpha")
        return if (isAlpha) {
            listOf(ALPHA_API_BASE_STRING, ALPHA_WAN_IPV4_API_BASE)
        } else {
            listOf(API_BASE_STRING, WAN_IPV4_API_BASE)
        }
    }

    fun isLanEndpoint(url: String): Boolean = url.contains(":8444")

    fun isLanHost(host: String): Boolean {
        if (host.startsWith("192.168.")) return true
        if (host.startsWith("10.")) return true
        // 172.16.0.0 – 172.31.255.255
        if (host.startsWith("172.")) {
            val second = host.split('.').getOrNull(1)?.toIntOrNull() ?: return false
            return second in 16..31
        }
        return false
    }

    fun normalizeInput(raw: String): String {
        var s = raw.trim().trimEnd('/')
        return "$s/"
    }

    fun setRuntimeBase(url: String?) {
        runtimeBase = if (url.isNullOrBlank()) null else normalizeInput(url)
    }

    fun resetToLan() {
        runtimeBase = null
    }

    fun useEffectiveBaseIfNeeded() {
        // Default is LAN via effectiveBase
    }

    /** Origin without path: https://host:port */
    fun serverOrigin(fromBase: String = effectiveBase): String {
        val base = normalizeInput(fromBase).trimEnd('/')
        // strip trailing app root (/beer or /beer-alpha)
        return when {
            base.endsWith("/beer-alpha") -> base.removeSuffix("/beer-alpha")
            base.endsWith("/beer") -> base.removeSuffix("/beer")
            else -> base
        }
    }

    /**
     * Resolve photo/static asset path like iOS ServerSettings.resolveAssetURL.
     * Relative paths become origin + path.
     */
    fun resolveAssetURL(path: String?, base: String = effectiveBase): String? {
        if (path.isNullOrBlank()) return null
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        val origin = serverOrigin(base)
        val p = if (path.startsWith("/")) path else "/$path"
        // server serves photos under /beer/photos/, /beer-alpha/photos/ or absolute /photos/
        return if (
            p.startsWith("/beer/") ||
            p.startsWith("/beer-alpha/") ||
            p.startsWith("/static/") ||
            p.startsWith("/photos/")
        ) {
            origin + p
        } else if (p.startsWith("/")) {
            // relative to beer root often "photos/xxx"
            val beerRoot = normalizeInput(base).trimEnd('/')
            "$beerRoot$p"
        } else {
            val beerRoot = normalizeInput(base).trimEnd('/')
            "$beerRoot/$path"
        }
    }

    /** Gift photo_path is often a bare filename or path — match iOS lastPathComponent handling. */
    fun giftPhotoPath(photoPath: String?): String? {
        if (photoPath.isNullOrBlank()) return null
        val name = photoPath.substringAfterLast('/')
        val root = if (isAlphaBase(effectiveBase)) "/beer-alpha" else "/beer"
        return "$root/photos/$name"
    }
}
