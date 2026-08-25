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

        internal const val NATIVE_CLIENT_HEADER = "X-PlexiBeer-Client"
        internal const val NATIVE_CLIENT_VALUE = "native-android"
        internal const val USER_AGENT_OWNER = "PlexiBeer/1.1 (Android; native owner) [lan-vpn]"
        internal const val USER_AGENT_INVITE = "PlexiBeer/1.1 (Android; native invite) [wan]"
        internal val JSON = "application/json; charset=utf-8".toMediaType()

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

    internal val appContext = context.applicationContext
    internal val gson = Gson()
    val cookieJar = SessionCookieJar(appContext)

    internal var baseURL: String = ServerSettings.effectiveBase
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

    internal val client = buildClient(30, 120)
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

    internal fun absUrl(path: String): String {
        val base = baseURL.trimEnd('/') + "/"
        val p = path.trimStart('/')
        return base + p
    }

    internal fun applyHeaders(builder: Request.Builder) {
        builder.header(NATIVE_CLIENT_HEADER, NATIVE_CLIENT_VALUE)
        builder.header(
            "User-Agent",
            if (isInviteMode) USER_AGENT_INVITE else USER_AGENT_OWNER
        )
        builder.header("X-App-Version", BuildConfig.VERSION_NAME)
        builder.header("X-App-Platform", "android")
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

    internal fun requestBuilder(path: String): Request.Builder {
        val b = Request.Builder().url(absUrl(path))
        applyHeaders(b)
        return b
    }

    class ApiException(message: String, val code: Int = 0) : Exception(message)

    internal suspend fun execute(
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
                // Always capture Set-Cookie (login / session refresh), même Domain-mismatched
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

    fun hasAnySession(): Boolean =
        cookieJar.hasSession() || InviteSessionStore.hasInviteSession(appContext)
}
