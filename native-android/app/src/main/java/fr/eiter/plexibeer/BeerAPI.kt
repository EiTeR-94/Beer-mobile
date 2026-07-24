package fr.eiter.plexibeer

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.TimeUnit

class BeerAPI private constructor(context: Context) {
    companion object {
        @Volatile private var INSTANCE: BeerAPI? = null

        fun getInstance(context: Context): BeerAPI =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: BeerAPI(context.applicationContext).also { INSTANCE = it }
            }

        private const val NATIVE_CLIENT_HEADER = "X-PlexiBeer-Client"
        private const val NATIVE_CLIENT_VALUE = "native-android"
        private const val USER_AGENT_OWNER = "PlexiBeer/1.1 (Android; native owner) [lan-vpn]"
        private const val USER_AGENT_INVITE = "PlexiBeer/1.1 (Android; native invite) [wan]"
        private val JSON = "application/json; charset=utf-8".toMediaType()

        /** Préfère IPv4 (4G Freebox AAAA souvent sans 443). */
        private val preferIpv4Dns = object : Dns {
            override fun lookup(hostname: String): List<InetAddress> {
                val all = Dns.SYSTEM.lookup(hostname)
                val v4 = all.filterIsInstance<Inet4Address>()
                if (v4.isEmpty()) return all
                return v4 + all.filter { it !is Inet4Address }
            }
        }
    }

    private val appContext = context.applicationContext
    private val gson = Gson()
    val cookieJar = SessionCookieJar(appContext)

    private var baseURL: String = ServerSettings.effectiveBase
    var activeEndpoint: String = baseURL
        private set

    val isInviteMode: Boolean
        get() = ServerSettings.inviteMode || InviteSessionStore.hasInviteSession(appContext)

    private fun buildClient(connectSec: Long, readSec: Long): OkHttpClient {
        val b = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .dns(preferIpv4Dns)
            .connectTimeout(connectSec, TimeUnit.SECONDS)
            .readTimeout(readSec, TimeUnit.SECONDS)
            .writeTimeout(readSec, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .addInterceptor { chain ->
                val req = chain.request()
                // Connexion directe IPv4 WAN : Host canonique pour nginx
                if (req.url.host == ServerSettings.WAN_IPV4) {
                    chain.proceed(
                        req.newBuilder().header("Host", ServerSettings.CANONICAL_HOST).build()
                    )
                } else {
                    chain.proceed(req)
                }
            }
        HomelabTls.applyTo(b)
        return b.build()
    }

    private val client = buildClient(30, 120)
    private val probeClient = buildClient(ServerSettings.LAN_PROBE_TIMEOUT_SEC, ServerSettings.LAN_PROBE_TIMEOUT_SEC + 4)

    fun setBaseURL(url: String) {
        baseURL = ServerSettings.normalizeInput(url)
        activeEndpoint = baseURL
        ServerSettings.setRuntimeBase(baseURL)
    }

    fun enableInviteMode(enabled: Boolean) {
        ServerSettings.inviteMode = enabled
        if (enabled) {
            val saved = InviteSessionStore.apiBase(appContext)
            setBaseURL(saved ?: ServerSettings.API_BASE_STRING)
        }
    }

    fun clearSession() {
        cookieJar.clear()
        BeerSessionStore.clear(appContext)
        InviteSessionStore.clear(appContext)
        ServerSettings.inviteMode = false
        ServerSettings.resetToLan()
        baseURL = ServerSettings.effectiveBase
        activeEndpoint = baseURL
    }

    private fun absUrl(path: String): String {
        val base = baseURL.trimEnd('/') + "/"
        val p = path.trimStart('/')
        return base + p
    }

    private fun applyHeaders(builder: Request.Builder) {
        builder.header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
        builder.header(
            "User-Agent",
            if (isInviteMode) USER_AGENT_INVITE else USER_AGENT_OWNER
        )
        val inviteToken = InviteSessionStore.accessToken(appContext)
        if (!inviteToken.isNullOrBlank()) {
            builder.header("Authorization", "Bearer $inviteToken")
            builder.header("X-Beer-Device", InviteSessionStore.deviceId(appContext))
        } else {
            // Force beer_session like iOS — critical when Set-Cookie Domain=FQDN vs LAN IP.
            cookieJar.beerSessionCookieHeader()?.let { cookie ->
                builder.header("Cookie", cookie)
            }
        }
    }

    private fun requestBuilder(path: String): Request.Builder {
        val b = Request.Builder().url(absUrl(path))
        applyHeaders(b)
        return b
    }

    class ApiException(message: String, val code: Int = 0) : Exception(message)

    private suspend fun execute(
        req: Request,
        probe: Boolean = false,
        allowUnauthorizedBody: Boolean = false
    ): Pair<String, Int> =
        withContext(Dispatchers.IO) {
            // Re-apply auth at send time (Bearer invite or cookie owner)
            val finalReq = req.newBuilder().also { b ->
                applyHeaders(b)
            }.build()
            val c = if (probe) probeClient else client
            c.newCall(finalReq).execute().use { resp ->
                // Always capture Set-Cookie (login / session refresh), even Domain-mismatched
                cookieJar.ingestResponse(resp)
                val body = resp.body?.string().orEmpty()
                // Login/public endpoints may return 401 with a JSON error body we must parse
                if (resp.code == 401 && !allowUnauthorizedBody) {
                    // 401 = session absente/expirée ; ne pas wipe sur 403 (wishlist etc. réservé owner)
                    if (isInviteMode) {
                        InviteSessionStore.clear(appContext)
                    }
                    throw ApiException("Session expirée — reconnecte-toi", 401)
                }
                if (resp.code == 403) {
                    val detail = try {
                        gson.fromJson(body, OkResponse::class.java)?.error
                    } catch (_: Exception) {
                        null
                    }.orEmpty()
                    val msg = if (isInviteMode) {
                        // Ne wipe la session que si le backend le dit explicitement
                        // (pas sur 403 nginx générique / feature owner-only)
                        val inviteDead = detail.contains("Invitation invalide", ignoreCase = true) ||
                            detail.contains("expir", ignoreCase = true)
                        if (inviteDead) {
                            InviteSessionStore.clear(appContext)
                            "Invitation invalide ou expirée — demande un nouveau lien"
                        } else {
                            detail.ifBlank {
                                "Accès refusé (invite) — réessaie ; si ça continue, rouvre le lien d'invitation"
                            }
                        }
                    } else {
                        "Accès refusé — Wi‑Fi maison ou VPN Plexi requis"
                    }
                    throw ApiException(msg, 403)
                }
                if (!resp.isSuccessful && resp.code !in listOf(401, 409)) {
                    // 409 handled by callers for duplicates
                    val err = try {
                        gson.fromJson(body, OkResponse::class.java)?.error
                    } catch (_: Exception) {
                        null
                    }
                    // Prefer server message over generic "Session expirée" for non-auth failures
                    throw ApiException(err ?: "Erreur serveur: ${resp.code}", resp.code)
                }
                body to resp.code
            }
        }

    suspend fun healthCheck(): Boolean = withContext(Dispatchers.IO) {
        try {
            val req = requestBuilder("api/health").get().build()
            client.newCall(req).execute().use { it.isSuccessful }
        } catch (_: Exception) {
            false
        }
    }

    suspend fun discoverWorkingEndpoint(): String? = withContext(Dispatchers.IO) {
        val original = baseURL
        for (candidate in ServerSettings.candidateURLs) {
            try {
                val healthUrl = ServerSettings.normalizeInput(candidate) + "api/health"
                val b = Request.Builder().url(healthUrl)
                applyHeaders(b)
                val c = if (ServerSettings.isLanEndpoint(candidate)) probeClient else client
                val ok = c.newCall(b.get().build()).execute().use { it.isSuccessful }
                if (ok) {
                    setBaseURL(candidate)
                    return@withContext candidate
                }
            } catch (_: Exception) {
                // try next
            }
        }
        baseURL = original
        null
    }

    suspend fun login(username: String, password: String): LoginResponse = withContext(Dispatchers.IO) {
        // Owner: LAN first ; clear invite mode
        enableInviteMode(false)
        InviteSessionStore.clear(appContext)
        setBaseURL(ServerSettings.LAN_API_BASE)
        discoverWorkingEndpoint()
        // Fresh login: drop previous token so we never mix sessions
        cookieJar.clear()
        val json = gson.toJson(mapOf("username" to username, "password" to password))
        // Build without Cookie header for login
        val req = Request.Builder()
            .url(absUrl("api/login"))
            .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
            .header("User-Agent", USER_AGENT_OWNER)
            .post(json.toRequestBody(JSON))
            .build()
        val (body, code) = execute(req, allowUnauthorizedBody = true)
        val decoded = gson.fromJson(body, LoginResponse::class.java)
            ?: throw ApiException("Réponse login invalide (HTTP $code)")
        if (code == 401 || code >= 400 || !decoded.ok) {
            throw ApiException(decoded.error ?: "Identifiants incorrects", code)
        }
        // Hard fail if session cookie was not captured (would break all subsequent API calls)
        if (!cookieJar.hasSession()) {
            throw ApiException(
                "Login OK mais cookie session absent (BEER_COOKIE_DOMAIN / Set-Cookie). Réessaie."
            )
        }
        decoded
    }

    /**
     * Activation invité WAN (4G/5G) — POST /api/native/join → Bearer.
     * @param inviteLink URL join complète ou token brut
     * @param email email pré-enregistré par l'admin (saisi par l'invité, pas d'indice UI)
     */
    suspend fun joinInvite(inviteLink: String, email: String): NativeJoinResponse = withContext(Dispatchers.IO) {
        val token = InviteSessionStore.parseInviteToken(inviteLink)
            ?: throw ApiException("Lien d'invitation invalide", 400)
        val emailClean = email.trim()
        if (emailClean.isEmpty() || !emailClean.contains("@")) {
            throw ApiException("Email requis", 400)
        }
        val deviceId = InviteSessionStore.deviceId(appContext)

        // Pas de cookies owner pendant l'activation
        cookieJar.clear()
        BeerSessionStore.clear(appContext)

        var lastError: Exception? = null
        // Beer prod vs Beerquest alpha : base déduite du lien (sinon candidates connus)
        val candidates = ServerSettings.basesFromInviteLink(inviteLink)
        for (candidate in candidates) {
            try {
                setBaseURL(candidate)
                enableInviteMode(true)
                val json = gson.toJson(
                    mapOf(
                        "token" to token,
                        "device_id" to deviceId,
                        "email" to emailClean,
                    )
                )
                val req = Request.Builder()
                    .url(absUrl("api/native/join"))
                    .header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
                    .header("User-Agent", USER_AGENT_INVITE)
                    .header("X-Beer-Device", deviceId)
                    .post(json.toRequestBody(JSON))
                    .build()
                val (body, code) = execute(req, allowUnauthorizedBody = true)
                val decoded = gson.fromJson(body, NativeJoinResponse::class.java)
                    ?: throw ApiException("Réponse join invalide (HTTP $code)", code)
                if (code == 429) {
                    throw ApiException("Trop de tentatives — réessaie dans une minute", 429)
                }
                if (code == 403 && decoded.error == "wrong_device") {
                    throw ApiException(
                        "Cette invitation est déjà liée à un autre téléphone",
                        403
                    )
                }
                if (code >= 400 || !decoded.ok || decoded.accessToken.isNullOrBlank()) {
                    throw ApiException(
                        when (decoded.error) {
                            "invalid" -> "Invitation invalide ou expirée"
                            "invalid_device" -> "Identifiant appareil invalide"
                            "disabled" -> "Invitations natives désactivées"
                            "email_required" -> "Email requis"
                            "wrong_email" -> "Email incorrect"
                            "rate_limit" -> "Trop de tentatives — réessaie dans une minute"
                            else -> decoded.error ?: "Activation impossible (HTTP $code)"
                        },
                        code
                    )
                }
                val boundDevice = decoded.deviceId ?: deviceId
                InviteSessionStore.save(
                    appContext,
                    accessToken = decoded.accessToken!!,
                    user = decoded.user ?: "invite",
                    label = decoded.label,
                    expiresAt = decoded.expiresAt,
                    deviceId = boundDevice,
                    apiBase = candidate
                )
                enableInviteMode(true)
                // Garder l'endpoint qui a fonctionné (beer ou beer-alpha)
                setBaseURL(candidate)
                return@withContext decoded
            } catch (e: Exception) {
                lastError = e
                if (e is ApiException && e.code in listOf(400, 403, 429, 503)) {
                    throw e
                }
                // essayer le prochain endpoint (FQDN puis IPv4)
            }
        }
        throw lastError ?: ApiException("Serveur injoignable en 4G/5G — réessaie", 0)
    }

    fun hasAnySession(): Boolean =
        cookieJar.hasSession() || InviteSessionStore.hasInviteSession(appContext)

    suspend fun me(): MeResponse {
        val (body, code) = execute(
            requestBuilder("api/me").get().build(),
            allowUnauthorizedBody = true
        )
        // 401 = révoqué / expiré (Bearer)
        if (code == 401) {
            if (isInviteMode) InviteSessionStore.clear(appContext)
            throw ApiException("Invitation révoquée ou expirée — demande un nouveau lien", 401)
        }
        val decoded = gson.fromJson(body, MeResponse::class.java)
            ?: throw ApiException("Réponse /me invalide", code)
        if (isInviteMode && decoded.user.isNullOrBlank()) {
            InviteSessionStore.clear(appContext)
            throw ApiException("Invitation révoquée ou expirée — demande un nouveau lien", 401)
        }
        return decoded
    }

    /** Beerquest state — enabled=false si RPG off / non autorisé. */
    suspend fun rpgMe(): RpgState = withContext(Dispatchers.IO) {
        try {
            val (body, code) = execute(
                requestBuilder("api/rpg/me").get().build(),
                allowUnauthorizedBody = true
            )
            if (code !in 200..299) return@withContext RpgState(enabled = false)
            gson.fromJson(body, RpgState::class.java) ?: RpgState(enabled = false)
        } catch (_: Exception) {
            RpgState(enabled = false)
        }
    }

    suspend fun rpgSetClass(classKey: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val json = gson.toJson(mapOf("class" to classKey))
            val (body, code) = execute(
                requestBuilder("api/rpg/class").post(json.toRequestBody(JSON)).build()
            )
            code in 200..299 && (gson.fromJson(body, OkResponse::class.java)?.ok == true)
        } catch (_: Exception) {
            false
        }
    }

    suspend fun rpgIntroSeen(): Boolean = withContext(Dispatchers.IO) {
        try {
            val (_, code) = execute(
                requestBuilder("api/rpg/intro-seen")
                    .post("{}".toRequestBody(JSON))
                    .build()
            )
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    suspend fun tutorialSeen(): Boolean = withContext(Dispatchers.IO) {
        try {
            val (_, code) = execute(
                requestBuilder("api/tutorial-seen")
                    .post("{}".toRequestBody(JSON))
                    .build()
            )
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    suspend fun adminRpgPlayers(): List<RpgAdminPlayer> = withContext(Dispatchers.IO) {
        try {
            val (body, code) = execute(requestBuilder("api/admin/rpg/players").get().build())
            if (code !in 200..299) return@withContext emptyList()
            gson.fromJson(body, RpgAdminPlayersResponse::class.java)?.players.orEmpty()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Liste joueurs + flags RPG (pour les toggles admin). */
    suspend fun adminRpgPlayersBundle(): RpgAdminPlayersResponse = withContext(Dispatchers.IO) {
        try {
            val (body, code) = execute(requestBuilder("api/admin/rpg/players").get().build())
            if (code !in 200..299) return@withContext RpgAdminPlayersResponse()
            gson.fromJson(body, RpgAdminPlayersResponse::class.java) ?: RpgAdminPlayersResponse()
        } catch (_: Exception) {
            RpgAdminPlayersResponse()
        }
    }

    suspend fun adminRpgGetSettings(): RpgAdminFlags? = withContext(Dispatchers.IO) {
        try {
            val (body, code) = execute(requestBuilder("api/admin/rpg/settings").get().build())
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminSettingsResponse::class.java)?.flags
        } catch (_: Exception) {
            null
        }
    }

    suspend fun adminRpgPatchSettings(payload: Map<String, Any?>): RpgAdminFlags? =
        withContext(Dispatchers.IO) {
            try {
                val json = gson.toJson(payload)
                val (body, code) = execute(
                    requestBuilder("api/admin/rpg/settings")
                        .patch(json.toRequestBody(JSON))
                        .build()
                )
                if (code !in 200..299) return@withContext null
                gson.fromJson(body, RpgAdminSettingsResponse::class.java)?.flags
            } catch (_: Exception) {
                null
            }
        }

    /**
     * @param allowed true=force ON, false=force OFF, null=auto (défaut allowlist/env)
     * Renvoie le détail complet à jour (le backend lève aussi la quarantaine si ON/Auto).
     */
    suspend fun adminRpgSetUserAllowed(username: String, allowed: Boolean?): RpgAdminPlayerDetail? =
        withContext(Dispatchers.IO) {
            try {
                val enc = java.net.URLEncoder.encode(username, "UTF-8")
                // null JSON explicite
                val json = if (allowed == null) {
                    """{"allowed":null}"""
                } else {
                    gson.toJson(mapOf("allowed" to allowed))
                }
                val (body, code) = execute(
                    requestBuilder("api/admin/rpg/settings/users/$enc")
                        .put(json.toRequestBody(JSON))
                        .build()
                )
                if (code !in 200..299) return@withContext null
                gson.fromJson(body, RpgAdminPlayerDetail::class.java)
            } catch (_: Exception) {
                null
            }
        }

    suspend fun adminRpgAdjustXp(username: String, delta: Int): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
        try {
            val json = gson.toJson(mapOf("delta" to delta))
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc/xp").post(json.toRequestBody(JSON)).build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

    suspend fun adminRpgResetDaily(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc/reset-daily")
                    .post(ByteArray(0).toRequestBody())
                    .build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

    /** GET détail complet d'un joueur (profil, badges, quêtes, événements, atlas…). */
    suspend fun adminRpgPlayer(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val (body, code) = execute(requestBuilder("api/admin/rpg/players/$enc").get().build())
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

    suspend fun adminRpgGrantBadge(username: String, badgeKey: String): RpgAdminBadgeActionResponse? =
        withContext(Dispatchers.IO) {
            try {
                val enc = java.net.URLEncoder.encode(username, "UTF-8")
                val json = gson.toJson(mapOf("badge_key" to badgeKey))
                val (body, code) = execute(
                    requestBuilder("api/admin/rpg/players/$enc/badges").post(json.toRequestBody(JSON)).build()
                )
                if (code !in 200..299) return@withContext null
                gson.fromJson(body, RpgAdminBadgeActionResponse::class.java)
            } catch (_: Exception) {
                null
            }
        }

    suspend fun adminRpgRevokeBadge(username: String, badgeKey: String): RpgAdminBadgeActionResponse? =
        withContext(Dispatchers.IO) {
            try {
                val encU = java.net.URLEncoder.encode(username, "UTF-8")
                val encB = java.net.URLEncoder.encode(badgeKey, "UTF-8")
                val (body, code) = execute(
                    requestBuilder("api/admin/rpg/players/$encU/badges/$encB").delete().build()
                )
                if (code !in 200..299) return@withContext null
                gson.fromJson(body, RpgAdminBadgeActionResponse::class.java)
            } catch (_: Exception) {
                null
            }
        }

    /** Efface tout le profil RPG (niveau/XP/badges/quêtes/historique) — garde le carnet de dégustations. */
    suspend fun adminRpgWipePlayer(username: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val (_, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc/wipe").post(ByteArray(0).toRequestBody()).build()
            )
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    /** Lève la quarantaine anti-triche (audit + override allowed → auto). */
    suspend fun adminRpgUnquarantine(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc/unquarantine").post(ByteArray(0).toRequestBody()).build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

    /** Dégustations d'un compte invité (lecture seule, admin). */
    suspend fun adminInviteCheckins(inviteId: Int, limit: Int = 30, offset: Int = 0): List<CheckinItem> =
        withContext(Dispatchers.IO) {
            try {
                val (body, code) = execute(
                    requestBuilder("api/invites/$inviteId/checkins?limit=$limit&offset=$offset").get().build()
                )
                if (code !in 200..299) return@withContext emptyList()
                val type = object : TypeToken<List<CheckinItem>>() {}.type
                gson.fromJson<List<CheckinItem>>(body, type) ?: emptyList()
            } catch (_: Exception) {
                emptyList()
            }
        }

    suspend fun logout() {
        try {
            execute(requestBuilder("api/logout").post(ByteArray(0).toRequestBody()).build())
        } catch (_: Exception) {
        }
        clearSession()
    }

    /** Feedback joueur (parité PWA « Un retour »). */
    suspend fun sendFeedback(
        message: String,
        category: String = "general",
        appVersion: String = "",
    ): Pair<Boolean, String?> {
        return try {
            val payload = mutableMapOf<String, Any>(
                "message" to message,
                "category" to category,
                "client_info" to "native-android",
                "page_path" to "native/android",
            )
            if (appVersion.isNotBlank()) payload["app_version"] = appVersion
            val json = gson.toJson(payload)
            val (body, code) = execute(
                requestBuilder("api/feedback").post(json.toRequestBody(JSON)).build()
            )
            if (code in 200..299) {
                true to null
            } else {
                val err = try {
                    @Suppress("UNCHECKED_CAST")
                    (gson.fromJson(body, Map::class.java) as? Map<String, Any>)
                        ?.get("detail")?.toString()
                } catch (_: Exception) {
                    null
                }
                false to (err ?: "Erreur $code")
            }
        } catch (e: Exception) {
            false to (e.message ?: "Réseau indisponible")
        }
    }

    suspend fun lookup(barcode: String): LookupResponse {
        val json = gson.toJson(mapOf("barcode" to barcode))
        val (body, _) = execute(requestBuilder("api/lookup").post(json.toRequestBody(JSON)).build())
        return gson.fromJson(body, LookupResponse::class.java)
    }

    suspend fun checkins(
        q: String = "",
        style: String = "",
        minRating: Double = 0.0,
        period: String = "",
        limit: Int = 10,
        offset: Int = 0
    ): List<CheckinItem> {
        val params = mutableListOf("limit=$limit", "offset=$offset")
        if (q.isNotEmpty()) params += "q=${java.net.URLEncoder.encode(q, "UTF-8")}"
        if (style.isNotEmpty()) params += "style=${java.net.URLEncoder.encode(style, "UTF-8")}"
        if (minRating > 0) params += "min_rating=$minRating"
        if (period.isNotEmpty()) params += "period=${java.net.URLEncoder.encode(period, "UTF-8")}"
        val (body, _) = execute(requestBuilder("api/checkins?${params.joinToString("&")}").get().build())
        val type = object : TypeToken<List<CheckinItem>>() {}.type
        return gson.fromJson(body, type) ?: emptyList()
    }

    suspend fun stats(): HistoryStats {
        val (body, _) = execute(requestBuilder("api/stats").get().build())
        return gson.fromJson(body, HistoryStats::class.java)
    }

    suspend fun coupleStats(): CoupleStats {
        val (body, _) = execute(requestBuilder("api/stats/couple").get().build())
        return gson.fromJson(body, CoupleStats::class.java)
    }

    suspend fun styles(): List<StyleOption> {
        return try {
            val (body, code) = execute(requestBuilder("api/styles").get().build())
            if (code == 401) return emptyList()
            val type = object : TypeToken<List<StyleOption>>() {}.type
            gson.fromJson(body, type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun version(): String {
        return try {
            val (body, _) = execute(requestBuilder("api/version").get().build())
            gson.fromJson(body, VersionResponse::class.java)?.version ?: "?"
        } catch (_: Exception) {
            "?"
        }
    }

    suspend fun wishlist(): List<WishlistItem> {
        val (body, _) = execute(requestBuilder("api/wishlist").get().build())
        val type = object : TypeToken<List<WishlistItem>>() {}.type
        return gson.fromJson(body, type) ?: emptyList()
    }

    suspend fun addWishlist(beerName: String, brewery: String, style: String = "Unknown", barcode: String = "") {
        val json = gson.toJson(
            mapOf(
                "beer_name" to beerName,
                "brewery" to brewery,
                "style" to style,
                "barcode" to barcode
            )
        )
        execute(requestBuilder("api/wishlist").post(json.toRequestBody(JSON)).build())
    }

    suspend fun deleteWishlist(id: Int) {
        execute(requestBuilder("api/wishlist/$id").delete().build())
    }

    suspend fun deleteCheckin(id: Int) {
        execute(requestBuilder("api/checkins/$id").delete().build())
    }

    suspend fun updateCheckin(
        id: Int,
        rating: Double? = null,
        flavors: List<String>? = null,
        hops: List<String>? = null,
        comment: String? = null,
        hiddenFromPartner: Boolean? = null,
        location: String? = null
    ) {
        val payload = mutableMapOf<String, Any?>()
        if (rating != null) payload["rating"] = rating
        if (flavors != null) payload["flavors"] = flavors
        if (hops != null) payload["hops"] = hops
        if (comment != null) payload["comment"] = comment
        if (location != null) payload["location"] = location.take(300)
        if (hiddenFromPartner != null) payload["hidden_from_partner"] = hiddenFromPartner
        val json = gson.toJson(payload)
        val req = requestBuilder("api/checkins/$id")
            .patch(json.toRequestBody(JSON))
            .build()
        execute(req)
    }

    suspend fun replaceCheckinPhoto(id: Int, jpeg: ByteArray) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart(
                "photo",
                "photo.jpg",
                jpeg.toRequestBody("image/jpeg".toMediaType())
            )
            .build()
        execute(requestBuilder("api/checkins/$id/photo").post(body).build())
    }

    suspend fun removeCheckinPhoto(id: Int) {
        execute(requestBuilder("api/checkins/$id/photo").delete().build())
    }

    suspend fun searchUntappd(query: String): UntappdSearchResponse {
        val q = java.net.URLEncoder.encode(query, "UTF-8")
        val (body, _) = execute(requestBuilder("api/untappd/search?q=$q&limit=5").get().build())
        return gson.fromJson(body, UntappdSearchResponse::class.java)
    }

    /** Backward-compatible brewery+name search used by wizard */
    suspend fun searchUntappd(brewery: String, name: String): UntappdSearchResponse {
        val q = listOf(brewery, name).filter { it.isNotBlank() }.joinToString(" ").trim()
        return if (q.isBlank()) UntappdSearchResponse(ok = false, error = "Requête vide")
        else searchUntappd(q)
    }

    suspend fun untappdFetch(
        bid: Int,
        barcode: String = "",
        beerName: String = "",
        brewery: String = ""
    ): LookupResponse {
        val json = gson.toJson(
            mapOf(
                "untappd_bid" to bid,
                "barcode" to barcode,
                "beer_name" to beerName,
                "brewery" to brewery
            )
        )
        val (body, _) = execute(requestBuilder("api/untappd/fetch").post(json.toRequestBody(JSON)).build())
        return gson.fromJson(body, LookupResponse::class.java)
    }

    suspend fun flavors(style: String, description: String = ""): FlavorsResponse {
        val s = java.net.URLEncoder.encode(style, "UTF-8")
        val d = java.net.URLEncoder.encode(description, "UTF-8")
        val (body, _) = execute(requestBuilder("api/flavors?style=$s&description=$d").get().build())
        return gson.fromJson(body, FlavorsResponse::class.java)
    }

    suspend fun flavorsAndHops(): FlavorsResponse = flavors(style = "", description = "")

    suspend fun addHop(name: String) {
        val json = gson.toJson(mapOf("name" to name))
        execute(requestBuilder("api/hops").post(json.toRequestBody(JSON)).build())
    }

    suspend fun scanPhoto(jpeg: ByteArray): LookupResponse {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart(
                "image",
                "scan.jpg",
                jpeg.toRequestBody("image/jpeg".toMediaType())
            )
            .build()
        val (respBody, _) = execute(requestBuilder("api/scan-photo").post(body).build())
        return gson.fromJson(respBody, LookupResponse::class.java)
    }

    suspend fun decodeBarcode(jpeg: ByteArray): DecodeBarcodeResponse {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart(
                "image",
                "scan.jpg",
                jpeg.toRequestBody("image/jpeg".toMediaType())
            )
            .build()
        val (respBody, _) = execute(requestBuilder("api/decode-barcode").post(body).build())
        return gson.fromJson(respBody, DecodeBarcodeResponse::class.java)
    }

    suspend fun createCheckin(
        barcode: String,
        beerName: String,
        brewery: String,
        style: String,
        abv: String,
        summary: String,
        rating: Double,
        flavors: List<String>,
        hops: List<String>,
        comment: String,
        untappdBid: String,
        force: Boolean,
        photoJPEG: ByteArray? = null,
        location: String = ""
    ): CreateCheckinResult = withContext(Dispatchers.IO) {
        val loc = location.trim().take(300)
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        builder.addFormDataPart("barcode", barcode)
        builder.addFormDataPart("beer_name", beerName)
        builder.addFormDataPart("brewery", brewery)
        builder.addFormDataPart("style", style.ifBlank { "Unknown" })
        builder.addFormDataPart("abv", abv)
        builder.addFormDataPart("summary", summary)
        builder.addFormDataPart("rating", rating.toString())
        builder.addFormDataPart("flavors", gson.toJson(flavors))
        builder.addFormDataPart("hops", gson.toJson(hops))
        builder.addFormDataPart("comment", comment.take(300))
        builder.addFormDataPart("location", loc)
        builder.addFormDataPart("untappd_bid", untappdBid)
        builder.addFormDataPart("force", if (force) "true" else "false")
        if (photoJPEG != null && photoJPEG.isNotEmpty()) {
            builder.addFormDataPart(
                "photo",
                "photo.jpg",
                photoJPEG.toRequestBody("image/jpeg".toMediaType())
            )
        }
        val req = requestBuilder("api/checkins").post(builder.build()).build()
        val (body, code) = execute(req)
        val decoded = gson.fromJson(body, CreateCheckinResult::class.java)
            ?: throw ApiException("Réponse création illisible")
        if (code == 409 || decoded.duplicate == true) return@withContext decoded
        if (decoded.ok != true && decoded.id == null) {
            throw ApiException(decoded.error ?: "Échec création")
        }
        decoded
    }

    /** Multipart convenience used by older wizard path */
    suspend fun createCheckinMultipart(
        beerName: String,
        brewery: String,
        style: String,
        rating: Double,
        comment: String?,
        photoFile: java.io.File? = null,
        barcode: String = "",
        untappdBid: Int? = null,
        flavors: List<String> = emptyList(),
        hops: List<String> = emptyList(),
        force: Boolean = false,
        location: String = ""
    ): Int {
        val bytes = photoFile?.takeIf { it.exists() }?.readBytes()
        val result = createCheckin(
            barcode = barcode,
            beerName = beerName,
            brewery = brewery,
            style = style,
            abv = "",
            summary = "",
            rating = rating,
            flavors = flavors,
            hops = hops,
            comment = comment.orEmpty(),
            untappdBid = untappdBid?.toString().orEmpty(),
            force = force,
            photoJPEG = bytes,
            location = location
        )
        if (result.duplicate == true) {
            throw ApiException(
                "duplicate|${result.previousCheckin?.beerName.orEmpty()}|${result.previousCheckin?.rating ?: 0}|${result.previousCheckin?.createdAt.orEmpty()}",
                409
            )
        }
        return result.id ?: 0
    }

    /**
     * Download internal asset with auth cookies. Tries LAN first then current base.
     * External http(s) URLs use plain client without cookie injection issues.
     */
    suspend fun downloadAsset(pathOrURL: String?): ByteArray = withContext(Dispatchers.IO) {
        val p = pathOrURL?.takeIf { it.isNotBlank() }
            ?: throw ApiException("URL asset invalide")
        if (p.startsWith("http://") || p.startsWith("https://")) {
            // external (Untappd labels etc.) — plain GET
            val plain = OkHttpClient.Builder()
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build()
            plain.newCall(Request.Builder().url(p).get().build()).execute().use { resp ->
                if (!resp.isSuccessful) throw ApiException("Fichier externe HTTP ${resp.code}")
                return@withContext resp.body?.bytes() ?: ByteArray(0)
            }
        }
        val candidates = listOfNotNull(
            ServerSettings.resolveAssetURL(p, ServerSettings.LAN_API_BASE),
            ServerSettings.resolveAssetURL(p, baseURL)
        ).distinct()
        var lastErr: Exception? = null
        for (url in candidates) {
            try {
                val b = Request.Builder().url(url)
                applyHeaders(b)
                client.newCall(b.get().build()).execute().use { resp ->
                    if (resp.code == 401) throw ApiException("Session expirée", 401)
                    if (resp.isSuccessful) {
                        return@withContext resp.body?.bytes() ?: ByteArray(0)
                    }
                    lastErr = ApiException("Fichier HTTP ${resp.code}")
                }
            } catch (e: Exception) {
                lastErr = e
            }
        }
        throw (lastErr ?: ApiException("Asset introuvable"))
    }

    suspend fun patchnotes(): PatchnotesResponse {
        val (body, _) = execute(requestBuilder("api/admin/patchnotes").get().build())
        return gson.fromJson(body, PatchnotesResponse::class.java)
    }

    suspend fun saveProduct(
        barcode: String,
        beerName: String,
        brewery: String,
        style: String
    ): LookupResponse {
        val json = gson.toJson(
            mapOf(
                "barcode" to barcode,
                "beer_name" to beerName,
                "brewery" to brewery,
                "style" to style
            )
        )
        val (body, code) = execute(
            requestBuilder("api/products/save").post(json.toRequestBody(JSON)).build()
        )
        val decoded = gson.fromJson(body, LookupResponse::class.java)
        if (code >= 400 || decoded.ok == false) {
            throw ApiException(decoded.error ?: "Sauvegarde produit impossible", code)
        }
        return decoded
    }

    suspend fun linkProduct(
        bid: Int,
        barcode: String,
        beerName: String,
        brewery: String
    ): LookupResponse {
        val json = gson.toJson(
            mapOf(
                "untappd_bid" to bid,
                "barcode" to barcode,
                "beer_name" to beerName,
                "brewery" to brewery
            )
        )
        val (body, code) = execute(
            requestBuilder("api/products/link").post(json.toRequestBody(JSON)).build()
        )
        val decoded = gson.fromJson(body, LookupResponse::class.java)
        if (code >= 400 || decoded.ok == false) {
            throw ApiException(decoded.error ?: "Liaison impossible", code)
        }
        return decoded
    }

    // ── Admin comptes / invites / outils (parité iOS) ────────────────────────

    suspend fun adminUsers(): List<AdminUser> = withContext(Dispatchers.IO) {
        val (body, code) = execute(requestBuilder("api/admin/users").get().build())
        if (code !in 200..299) return@withContext emptyList()
        val type = object : TypeToken<List<AdminUser>>() {}.type
        gson.fromJson<List<AdminUser>>(body, type) ?: emptyList()
    }

    suspend fun adminCreateUser(username: String, password: String, isAdmin: Boolean) {
        val json = gson.toJson(
            mapOf("username" to username, "password" to password, "is_admin" to isAdmin)
        )
        val (_, code) = execute(
            requestBuilder("api/admin/users").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Création compte impossible", code)
    }

    suspend fun adminDeleteUser(username: String) {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (_, code) = execute(requestBuilder("api/admin/users/$enc").delete().build())
        if (code !in 200..299) throw ApiException("Suppression impossible", code)
    }

    suspend fun adminSetAdmin(username: String, isAdmin: Boolean) {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val json = gson.toJson(mapOf("is_admin" to isAdmin))
        val (_, code) = execute(
            requestBuilder("api/admin/users/$enc").patch(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Changement admin impossible", code)
    }

    suspend fun adminSetPassword(username: String, password: String) {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val json = gson.toJson(mapOf("password" to password))
        val (_, code) = execute(
            requestBuilder("api/admin/users/$enc").patch(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Mot de passe non mis à jour", code)
    }

    suspend fun adminInvites(): List<InviteItem> = withContext(Dispatchers.IO) {
        val (body, code) = execute(requestBuilder("api/invites").get().build())
        if (code !in 200..299) return@withContext emptyList()
        val type = object : TypeToken<List<InviteItem>>() {}.type
        gson.fromJson<List<InviteItem>>(body, type) ?: emptyList()
    }

    suspend fun adminCreateInvite(label: String, email: String, validity: String = "7d"): CreateInviteResponse {
        val json = gson.toJson(
            mapOf("label" to label, "email" to email, "validity" to validity)
        )
        val (body, code) = execute(
            requestBuilder("api/invites").post(json.toRequestBody(JSON)).build()
        )
        val decoded = gson.fromJson(body, CreateInviteResponse::class.java)
            ?: CreateInviteResponse(ok = false, error = "Réponse invalide")
        if (code !in 200..299) throw ApiException(decoded.error ?: "Création invite impossible", code)
        return decoded
    }

    suspend fun adminExtendInvite(id: Int, validity: String) {
        val json = gson.toJson(mapOf("validity" to validity))
        val (_, code) = execute(
            requestBuilder("api/invites/$id/extend").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Prolongation impossible", code)
    }

    suspend fun adminReissueInvite(id: Int): String? {
        val (body, code) = execute(
            requestBuilder("api/invites/$id/reissue").post("{}".toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Réémission impossible", code)
        return gson.fromJson(body, CreateInviteResponse::class.java)?.url
    }

    suspend fun adminRevokeInvite(id: Int) {
        val (_, code) = execute(requestBuilder("api/invites/$id").delete().build())
        if (code !in 200..299) throw ApiException("Révocation impossible", code)
    }

    suspend fun adminCleanupPhotos(): String {
        val (body, code) = execute(
            requestBuilder("api/admin/photos/cleanup").post("{}".toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Nettoyage impossible", code)
        val d = gson.fromJson(body, CleanupPhotosResponse::class.java)
        return d?.message
            ?: d?.detail
            ?: (d?.removed?.let { "Supprimé : $it photo(s)" })
            ?: "Photos nettoyées"
    }

    suspend fun adminReferentials(): ReferentialsResponse = withContext(Dispatchers.IO) {
        val (body, code) = execute(requestBuilder("api/admin/referentials").get().build())
        if (code !in 200..299) return@withContext ReferentialsResponse()
        gson.fromJson(body, ReferentialsResponse::class.java) ?: ReferentialsResponse()
    }

    suspend fun adminAddStyle(name: String) {
        val json = gson.toJson(mapOf("name" to name))
        val (_, code) = execute(
            requestBuilder("api/styles").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Ajout style impossible", code)
    }

    suspend fun adminDeleteStyle(name: String) {
        val enc = java.net.URLEncoder.encode(name, "UTF-8")
        val (_, code) = execute(requestBuilder("api/styles/$enc").delete().build())
        if (code !in 200..299) throw ApiException("Suppression style impossible", code)
    }

    suspend fun adminAddHop(name: String) {
        val json = gson.toJson(mapOf("name" to name))
        val (_, code) = execute(
            requestBuilder("api/hops").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Ajout houblon impossible", code)
    }

    suspend fun adminDeleteHop(name: String) {
        val enc = java.net.URLEncoder.encode(name, "UTF-8")
        val (_, code) = execute(requestBuilder("api/hops/$enc").delete().build())
        if (code !in 200..299) throw ApiException("Suppression houblon impossible", code)
    }

    suspend fun adminAddFlavor(name: String) {
        val json = gson.toJson(mapOf("name" to name))
        val (_, code) = execute(
            requestBuilder("api/flavors/custom").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Ajout goût impossible", code)
    }

    suspend fun adminDeleteFlavor(name: String) {
        val enc = java.net.URLEncoder.encode(name, "UTF-8")
        val (_, code) = execute(requestBuilder("api/flavors/custom/$enc").delete().build())
        if (code !in 200..299) throw ApiException("Suppression goût impossible", code)
    }

    // ── Feedback admin + réponses joueur ────────────────────────────────────

    suspend fun adminFeedbackList(
        limit: Int = 80,
        unreadOnly: Boolean = false,
        status: String? = null,
    ): AdminFeedbackListResponse = withContext(Dispatchers.IO) {
        var path = "api/admin/feedback?limit=${limit.coerceIn(1, 200)}"
        if (unreadOnly) path += "&unread=1"
        if (!status.isNullOrBlank()) path += "&status=${java.net.URLEncoder.encode(status, "UTF-8")}"
        val (body, code) = execute(requestBuilder(path).get().build())
        if (code !in 200..299) throw ApiException("Feedback admin indisponible", code)
        gson.fromJson(body, AdminFeedbackListResponse::class.java)
            ?: AdminFeedbackListResponse()
    }

    suspend fun adminFeedbackStats(): AdminFeedbackStats? = try {
        adminFeedbackList(limit = 1).stats
    } catch (_: Exception) {
        null
    }

    suspend fun adminFeedbackMarkRead(id: Int, read: Boolean = true) {
        val json = gson.toJson(mapOf("read" to read))
        val (_, code) = execute(
            requestBuilder("api/admin/feedback/$id/read").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Marquage lu impossible", code)
    }

    suspend fun adminFeedbackReadAll() {
        val (_, code) = execute(
            requestBuilder("api/admin/feedback/read-all").post("{}".toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Lecture globale impossible", code)
    }

    suspend fun adminFeedbackResolve(id: Int, status: String, reply: String) {
        val json = gson.toJson(mapOf("status" to status, "reply" to reply))
        val (_, code) = execute(
            requestBuilder("api/admin/feedback/$id/resolve").post(json.toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Réponse impossible", code)
    }

    suspend fun adminFeedbackReopen(id: Int) {
        val (_, code) = execute(
            requestBuilder("api/admin/feedback/$id/reopen").post("{}".toRequestBody(JSON)).build()
        )
        if (code !in 200..299) throw ApiException("Réouverture impossible", code)
    }

    suspend fun adminFeedbackDelete(id: Int) {
        val (_, code) = execute(requestBuilder("api/admin/feedback/$id").delete().build())
        if (code !in 200..299) throw ApiException("Suppression impossible", code)
    }

    suspend fun feedbackReplies(unseenOnly: Boolean = true): List<AdminFeedbackItem> =
        withContext(Dispatchers.IO) {
            val path = "api/feedback/replies?unseen=${if (unseenOnly) "1" else "0"}&limit=20"
            val (body, code) = execute(requestBuilder(path).get().build())
            if (code !in 200..299) return@withContext emptyList()
            gson.fromJson(body, FeedbackRepliesResponse::class.java)?.items.orEmpty()
        }

    suspend fun markFeedbackRepliesSeen(ids: List<Int>) {
        try {
            val json = gson.toJson(mapOf("ids" to ids))
            execute(
                requestBuilder("api/feedback/replies/seen").post(json.toRequestBody(JSON)).build()
            )
        } catch (_: Exception) {
        }
    }

    // ── RPG admin enrichi ───────────────────────────────────────────────────

    suspend fun adminRpgPatchPlayer(username: String, payload: Map<String, Any?>): RpgAdminPlayerDetail? =
        withContext(Dispatchers.IO) {
            try {
                val enc = java.net.URLEncoder.encode(username, "UTF-8")
                val json = gson.toJson(payload)
                val (body, code) = execute(
                    requestBuilder("api/admin/rpg/players/$enc")
                        .patch(json.toRequestBody(JSON))
                        .build()
                )
                if (code !in 200..299) return@withContext null
                gson.fromJson(body, RpgAdminPlayerDetail::class.java)
            } catch (_: Exception) {
                null
            }
        }

    // ── Versions portail ────────────────────────────────────────────────────

    suspend fun fetchMobileVersions(): MobileVersionsManifest? = withContext(Dispatchers.IO) {
        try {
            val url = ServerSettings.versionsURL
            val req = Request.Builder().url(url).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string().orEmpty()
                gson.fromJson(body, MobileVersionsManifest::class.java)
            }
        } catch (_: Exception) {
            null
        }
    }
}
