package fr.eiter.plexibeer

import fr.eiter.plexibeer.BeerAPI.ApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

suspend fun BeerAPI.login(username: String, password: String): LoginResponse = withContext(Dispatchers.IO) {
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
        .header(BeerAPI.NATIVE_CLIENT_HEADER, BeerAPI.NATIVE_CLIENT_VALUE)
        .header("User-Agent", BeerAPI.USER_AGENT_OWNER)
        .post(json.toRequestBody(BeerAPI.JSON))
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
suspend fun BeerAPI.joinInvite(inviteLink: String, email: String): NativeJoinResponse = withContext(Dispatchers.IO) {
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
                .header(BeerAPI.NATIVE_CLIENT_HEADER, BeerAPI.NATIVE_CLIENT_VALUE)
                .header("User-Agent", BeerAPI.USER_AGENT_INVITE)
                .header("X-Beer-Device", deviceId)
                .post(json.toRequestBody(BeerAPI.JSON))
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

suspend fun BeerAPI.me(): MeResponse {
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

suspend fun BeerAPI.tutorialSeen(): Boolean = withContext(Dispatchers.IO) {
    try {
        val (_, code) = execute(
            requestBuilder("api/tutorial-seen")
                .post("{}".toRequestBody(BeerAPI.JSON))
                .build()
        )
        code in 200..299
    } catch (_: Exception) {
        false
    }
}

suspend fun BeerAPI.logout() {
    try {
        execute(requestBuilder("api/logout").post(ByteArray(0).toRequestBody()).build())
    } catch (_: Exception) {
    }
    clearSession()
}
