package fr.eiter.plexibeer

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class AppViewModel(app: Application) : AndroidViewModel(app) {
    val api = BeerAPI.getInstance(app)
    val imageCache = ImageCache.getInstance(app)
    val listCache = OfflineCache(app)
    val offline = OfflineQueue(app)

    var user by mutableStateOf<String?>(null)
        private set
    var isAdmin by mutableStateOf(false)
        private set
    var isInvite by mutableStateOf(false)
        private set
    var inviteLabel by mutableStateOf<String?>(null)
        private set
    /** Lien d'invitation reçu via deep link (préremplit l'écran Invitation). */
    var pendingInviteLink by mutableStateOf<String?>(null)
        private set
    var isLoggedIn by mutableStateOf(false)
        private set
    var isLoading by mutableStateOf(true)
        private set
    var networkStatus by mutableStateOf(NetworkStatus.ONLINE)
        private set
    var serverVersion by mutableStateOf("")
        private set
    var toast by mutableStateOf<ToastPayload?>(null)
        private set
    var wizardStep by mutableIntStateOf(1)
    var wizardProduct by mutableStateOf<BeerProduct?>(null)
    var sheet by mutableStateOf<BeerSheet?>(null)
    var selectedCheckin by mutableStateOf<CheckinItem?>(null)
    var editingCheckin by mutableStateOf<CheckinItem?>(null)
    var lastEndpointLatencyMs by mutableStateOf<Long?>(null)
        private set

    /** Badge « En attente » — state Compose (pas juste un getter). */
    var pendingCount by mutableIntStateOf(0)
        private set
    var pendingItems by mutableStateOf<List<PendingCheckin>>(emptyList())
        private set
    var pendingDeletes by mutableStateOf<List<Int>>(emptyList())
        private set

    /** Beerquest — null = pas encore chargé / off */
    var rpgState by mutableStateOf<RpgState?>(null)
        private set
    var lastRpgLoot by mutableStateOf<RpgLoot?>(null)
        private set
    var rpgCelebration by mutableStateOf<RpgCelebration?>(null)
        private set
    var showRpgIntro by mutableStateOf(false)
        private set
    var requestOpenGrimoire by mutableStateOf(false)

    /** Tuto « Comment ça marche » — vu côté serveur (défaut true tant que /api/me pas encore répondu). */
    var tutorialSeen by mutableStateOf(true)
        private set
    /** Demande d'ouvrir le tuto auto (1ʳᵉ connexion ou toggle « revoir »). */
    var showTutorial by mutableStateOf(false)
        private set

    /** Réponses admin feedback non vues (popup login, parité iOS/web). */
    var pendingFeedbackReplies by mutableStateOf<List<AdminFeedbackItem>>(emptyList())
        private set
    var feedbackReplyIndex by mutableIntStateOf(0)
        private set

    /** Versions portail (bannière update). */
    var latestAndroidVersion by mutableStateOf<String?>(null)
        private set
    var latestIosVersion by mutableStateOf<String?>(null)
        private set

    /** versionName APK (ex. 4.4.24) — pas la webapp, pas le versionCode. */
    val appVersion: String
        get() = try {
            val p = getApplication<Application>().packageManager
                .getPackageInfo(getApplication<Application>().packageName, 0)
            p.versionName ?: "?"
        } catch (_: Exception) {
            "?"
        }

    val needsAppUpdate: Boolean
        get() {
            val latest = latestAndroidVersion ?: return false
            if (appVersion == "?" || latest.isBlank()) return false
            return beerVersionCompare(appVersion, latest) < 0
        }

    /** Check MAJ en cours. */
    var isRefreshing by mutableStateOf(false)
        private set

    val currentFeedbackReply: AdminFeedbackItem?
        get() = pendingFeedbackReplies.getOrNull(feedbackReplyIndex)

    val rpgActive: Boolean
        get() = rpgState?.enabled == true && rpgState?.ui == true && rpgState?.profile != null

    private val celebQueue = ArrayDeque<RpgCelebration>()
    private var celebBusy = false
    private var celebJob: Job? = null
    private var toastJob: Job? = null
    private var syncInProgress = false
    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null
    private var lastOfflineToastAt = 0L

    init {
        // Listener APRÈS init des states Compose — sinon crash immédiat au launch
        // (viewModelScope Main.immediate pendant le constructeur).
        offline.setOnChanged {
            try {
                refreshOfflineUi()
            } catch (_: Exception) {
            }
        }
        refreshOfflineUi()
        viewModelScope.launch {
            try {
                bootstrap()
            } catch (e: Exception) {
                isLoading = false
                networkStatus = NetworkStatus.OFFLINE
                restoreOfflineSessionIfNeeded()
                showToast(
                    "Démarrage hors ligne",
                    ToastPayload.Variant.WARN,
                    detail = e.message?.take(80),
                    durationMs = 4000
                )
            }
        }
        try {
            registerConnectivity()
        } catch (_: Exception) {
        }
    }

    override fun onCleared() {
        super.onCleared()
        unregisterConnectivity()
    }

    private fun refreshOfflineUi() {
        pendingCount = offline.pendingCount
        pendingItems = offline.items
        pendingDeletes = offline.pendingDeletes
    }

    private fun registerConnectivity() {
        val cm = getApplication<Application>().getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                viewModelScope.launch { probeAndSync() }
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val ok = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                if (ok) {
                    viewModelScope.launch { probeAndSync() }
                }
            }

            override fun onLost(network: Network) {
                if (!isNetworkAvailable()) {
                    networkStatus = NetworkStatus.OFFLINE
                    maybeToastOffline()
                }
            }
        }
        connectivityCallback = cb
        try {
            cm.registerDefaultNetworkCallback(cb)
        } catch (_: Exception) {
        }
    }

    private fun unregisterConnectivity() {
        val cm = getApplication<Application>().getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivityCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
    }

    fun isNetworkAvailable(): Boolean {
        val cm = getApplication<Application>().getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(net) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    /** true si on peut tenter l'API (pas OFFLINE pur). */
    fun isEffectivelyOnline(): Boolean = networkStatus == NetworkStatus.ONLINE

    /**
     * @param silent si true : pas d’écran de chargement plein (refresh in-app).
     */
    suspend fun bootstrap(silent: Boolean = false) {
        if (!silent) isLoading = true
        try {
            if (!isNetworkAvailable()) {
                networkStatus = NetworkStatus.OFFLINE
                restoreOfflineSessionIfNeeded()
                if (isLoggedIn && !silent) {
                    showToast(
                        "Mode hors ligne",
                        ToastPayload.Variant.INFO,
                        detail = "Tes notes seront sync au retour réseau",
                        durationMs = 3500
                    )
                }
                return
            }
            val t0 = System.currentTimeMillis()
            val ep = api.discoverWorkingEndpoint()
            lastEndpointLatencyMs = System.currentTimeMillis() - t0
            if (ep == null) {
                networkStatus = NetworkStatus.SERVER_UNREACHABLE
                restoreOfflineSessionIfNeeded()
                if (isLoggedIn && !silent) {
                    showToast(
                        "Serveur injoignable",
                        ToastPayload.Variant.WARN,
                        detail = "Cache local + file d'attente actifs",
                        durationMs = 3500
                    )
                }
                return
            }
            networkStatus = NetworkStatus.ONLINE
            // Session invité (Bearer) prioritaire si présente
            if (InviteSessionStore.hasInviteSession(getApplication())) {
                api.enableInviteMode(true)
                try {
                    val me = api.me()
                    if (!me.user.isNullOrBlank()) {
                        applySession(
                            me.user!!,
                            admin = false,
                            loggedIn = true,
                            invite = true,
                            label = InviteSessionStore.label(getApplication())
                        )
                        serverVersion = try {
                            api.version()
                        } catch (_: Exception) {
                            ""
                        }
                        syncPending()
                        prewarmRecentPhotos()
                        listCache.prune(16)
                        return
                    }
                    api.clearSession()
                } catch (e: Exception) {
                    val code = (e as? BeerAPI.ApiException)?.code ?: 0
                    // 401 = token mort ; 403 peut être transitoire / feature — garder le Bearer
                    if (code == 401) {
                        api.clearSession()
                    } else {
                        networkStatus = NetworkStatus.SERVER_UNREACHABLE
                        restoreOfflineSessionIfNeeded()
                        return
                    }
                }
            } else if (api.cookieJar.hasSession()) {
                try {
                    val me = api.me()
                    if (!me.user.isNullOrBlank()) {
                        applySession(me.user!!, me.isAdmin, true, invite = me.isInvite)
                        serverVersion = try {
                            api.version()
                        } catch (_: Exception) {
                            ""
                        }
                        syncPending()
                        prewarmRecentPhotos()
                        listCache.prune(16)
                        return
                    }
                    api.clearSession()
                    BeerSessionStore.clear(getApplication())
                } catch (e: Exception) {
                    val code = (e as? BeerAPI.ApiException)?.code ?: 0
                    if (code == 401) {
                        api.clearSession()
                        BeerSessionStore.clear(getApplication())
                    } else {
                        networkStatus = NetworkStatus.SERVER_UNREACHABLE
                        restoreOfflineSessionIfNeeded()
                        return
                    }
                }
            }
            restoreOfflineSessionIfNeeded()
        } finally {
            if (!silent) isLoading = false
        }
    }

    private fun restoreOfflineSessionIfNeeded() {
        val restored = BeerSessionStore.restore(getApplication()) ?: return
        val hasAuth = api.cookieJar.hasSession() ||
            InviteSessionStore.hasInviteSession(getApplication()) ||
            networkStatus != NetworkStatus.ONLINE
        if (hasAuth) {
            applySession(
                restored.user,
                restored.isAdmin,
                true,
                invite = restored.isInvite,
                label = InviteSessionStore.label(getApplication())
            )
            if (restored.isInvite) api.enableInviteMode(true)
        }
    }

    fun refreshRpg() {
        if (!isLoggedIn || networkStatus != NetworkStatus.ONLINE) return
        viewModelScope.launch {
            try {
                val st = api.rpgMe()
                rpgState = st
                maybeShowRpgIntro(st)
            } catch (_: Exception) {
                // keep previous state
            }
        }
    }

    private fun maybeShowRpgIntro(st: RpgState) {
        val p = st.profile
        if (st.enabled && st.ui && p != null && !p.introSeen) {
            showRpgIntro = true
        } else if (p?.introSeen == true) {
            showRpgIntro = false
        }
    }

    fun dismissRpgIntro(openGrimoire: Boolean = false) {
        showRpgIntro = false
        val prev = rpgState
        if (prev?.profile != null) {
            rpgState = prev.copy(profile = prev.profile.copy(introSeen = true))
        }
        viewModelScope.launch {
            try { api.rpgIntroSeen() } catch (_: Exception) {}
            refreshRpg()
        }
        if (openGrimoire) requestOpenGrimoire = true
    }

    fun consumeOpenGrimoireRequest() {
        requestOpenGrimoire = false
    }

    fun consumeShowTutorialRequest() {
        showTutorial = false
    }

    fun handleRpgLoot(loot: RpgLoot?) {
        if (loot == null) return
        lastRpgLoot = loot
        // Optimistic HUD update
        val prev = rpgState
        if (prev?.profile != null) {
            rpgState = prev.copy(
                profile = prev.profile.copy(
                    level = loot.level,
                    xp = loot.xp,
                    title = loot.title ?: prev.profile.title,
                    progressPct = loot.progressPct,
                    xpToNext = loot.xpToNext,
                    streakDays = loot.streakDays ?: prev.profile.streakDays
                )
            )
        }
        val bits = mutableListOf<String>()
        if (loot.levelUp) bits.add("LEVEL UP → ${loot.level}")
        if (loot.xpGained != 0) bits.add("+${loot.xpGained} XP")
        loot.badgesEarned.firstOrNull()?.let { bits.add("${it.icon ?: "🏅"} ${it.name}") }
        loot.questsCompleted.firstOrNull()?.let { bits.add("📜 ${it.title}") }
        if (loot.dailySoftCapped) {
            val cap = loot.dailySoftCap ?: "?"
            val day = loot.dailyXp ?: cap
            bits.add("⛔ soft-cap $day/$cap")
        }
        val hasCeleb = loot.levelUp || loot.badgesEarned.isNotEmpty()
        val msg = when {
            loot.levelUp -> loot.phraseLevelUp ?: loot.phrase ?: "Niveau ${loot.level} !"
            loot.dailySoftCapped && !loot.softCapMessage.isNullOrBlank() -> loot.softCapMessage!!
            loot.dailySoftCapped -> loot.phrase
                ?: "Plus d’XP aujourd’hui (soft-cap). Reviens demain."
            loot.xpGained > 0 -> loot.phrase ?: "Butin +${loot.xpGained} XP"
            else -> loot.phrase ?: "Noté"
        }
        showToast(
            msg,
            if (hasCeleb) ToastPayload.Variant.SUCCESS else ToastPayload.Variant.INFO,
            detail = bits.joinToString(" · ").ifBlank { null },
            label = "Beerquest",
            durationMs = when {
                hasCeleb -> 2200
                loot.dailySoftCapped -> 5600
                else -> 3800
            }
        )
        enqueueCelebrations(loot)
        refreshRpg()
    }

    private fun enqueueCelebrations(loot: RpgLoot) {
        if (loot.levelUp) celebQueue.addLast(RpgCelebration.LevelUp(loot))
        loot.badgesEarned.forEach { celebQueue.addLast(RpgCelebration.BadgeUnlock(it)) }
        if (celebQueue.isEmpty()) return
        celebJob?.cancel()
        celebJob = viewModelScope.launch {
            delay(1300)
            pumpCelebrationQueue()
        }
    }

    private fun pumpCelebrationQueue() {
        if (celebBusy) return
        val next = celebQueue.removeFirstOrNull() ?: return
        celebBusy = true
        hapticTick()
        rpgCelebration = next
    }

    fun dismissRpgCelebration(openGrimoire: Boolean = false) {
        rpgCelebration = null
        celebBusy = false
        if (openGrimoire) requestOpenGrimoire = true
        viewModelScope.launch {
            delay(280)
            pumpCelebrationQueue()
        }
    }

    fun equipRpgClass(key: String, onDone: (Boolean) -> Unit = {}) {
        viewModelScope.launch {
            val ok = try {
                api.rpgSetClass(key)
            } catch (_: Exception) {
                false
            }
            if (ok) {
                refreshRpg()
                showToast("Classe équipée", ToastPayload.Variant.SUCCESS, label = "Beerquest")
            } else {
                showToast("Impossible d’équiper", ToastPayload.Variant.ERROR, label = "Beerquest")
            }
            onDone(ok)
        }
    }

    private fun clearRpgUiState() {
        rpgState = null
        lastRpgLoot = null
        rpgCelebration = null
        showRpgIntro = false
        celebQueue.clear()
        celebBusy = false
        celebJob?.cancel()
    }

    private fun applySession(
        userName: String?,
        admin: Boolean,
        loggedIn: Boolean,
        invite: Boolean = false,
        label: String? = null
    ) {
        user = userName
        isAdmin = admin && !invite
        isInvite = invite
        inviteLabel = label
        isLoggedIn = loggedIn
        if (loggedIn && userName != null) {
            BeerSessionStore.save(getApplication(), userName, admin && !invite, invite)
            refreshRpg()
            viewModelScope.launch {
                checkFeedbackReplies()
                refreshMobileVersions()
                checkTutorialSeen()
            }
        } else {
            clearRpgUiState()
            pendingFeedbackReplies = emptyList()
            feedbackReplyIndex = 0
            tutorialSeen = true
            showTutorial = false
        }
    }

    suspend fun checkFeedbackReplies() {
        if (!isLoggedIn) return
        try {
            val items = withContext(Dispatchers.IO) { api.feedbackReplies(unseenOnly = true) }
            pendingFeedbackReplies = items
            feedbackReplyIndex = 0
        } catch (_: Exception) {
        }
    }

    /** Charge le flag tuto (parité PWA loadSession) et déclenche l'auto-ouverture à la 1ʳᵉ connexion. */
    suspend fun checkTutorialSeen() {
        if (!isLoggedIn) return
        try {
            val me = withContext(Dispatchers.IO) { api.me() }
            val seen = me.tutorialSeen ?: true
            tutorialSeen = seen
            if (!seen) {
                // Léger délai : laisse l'intro Beerquest (RPG) s'afficher en priorité si due.
                delay(1200)
                if (isLoggedIn && !tutorialSeen) {
                    showTutorial = true
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Marque le tuto vu côté serveur (fermeture panneau, 1ʳᵉ connexion ou rejoué via toggle). */
    fun markTutorialSeen() {
        if (tutorialSeen) return
        tutorialSeen = true
        viewModelScope.launch {
            try { api.tutorialSeen() } catch (_: Exception) {}
        }
    }

    fun advanceFeedbackReply() {
        if (feedbackReplyIndex + 1 < pendingFeedbackReplies.size) {
            feedbackReplyIndex++
        } else {
            val ids = pendingFeedbackReplies.mapNotNull { it.id }
            pendingFeedbackReplies = emptyList()
            feedbackReplyIndex = 0
            viewModelScope.launch {
                withContext(Dispatchers.IO) { api.markFeedbackRepliesSeen(ids) }
            }
        }
    }

    suspend fun refreshMobileVersions() {
        try {
            val m = withContext(Dispatchers.IO) { api.fetchMobileVersions() } ?: return
            latestAndroidVersion = m.android
            latestIosVersion = m.ios
        } catch (_: Exception) {
        }
    }

    /**
     * Check MAJ : versions portail + sync léger, sans quitter l'app.
     */
    fun refreshApp(showToastOnDone: Boolean = true) {
        if (isRefreshing) return
        viewModelScope.launch {
            isRefreshing = true
            try {
                bootstrap(silent = true)
                if (isLoggedIn) {
                    refreshMobileVersions()
                    refreshRpg()
                    checkFeedbackReplies()
                    syncPending()
                } else {
                    refreshMobileVersions()
                }
                if (showToastOnDone) {
                    when {
                        needsAppUpdate -> showToast(
                            "MAJ APK disponible",
                            ToastPayload.Variant.WARN,
                            detail = "v$appVersion → v${latestAndroidVersion ?: "?"}",
                            durationMs = 4000
                        )
                        networkStatus != NetworkStatus.ONLINE -> showToast(
                            "Check MAJ (hors ligne / serveur)",
                            ToastPayload.Variant.INFO,
                            durationMs = 2500
                        )
                        else -> showToast(
                            "APK à jour",
                            ToastPayload.Variant.SUCCESS,
                            detail = "v$appVersion",
                            durationMs = 2200
                        )
                    }
                }
            } catch (e: Exception) {
                if (showToastOnDone) {
                    showToast(
                        "Check MAJ impossible",
                        ToastPayload.Variant.ERROR,
                        detail = e.message?.take(80),
                        durationMs = 3500
                    )
                }
            } finally {
                isRefreshing = false
            }
        }
    }

    /** Au retour foreground : check maj + sync léger (sans toast bruyant). */
    fun onAppResumed() {
        if (!isLoggedIn || isRefreshing) return
        viewModelScope.launch {
            try {
                refreshMobileVersions()
                if (networkStatus == NetworkStatus.ONLINE) {
                    syncPending()
                }
            } catch (_: Exception) {
            }
        }
    }

    fun showToast(
        message: String,
        variant: ToastPayload.Variant = ToastPayload.Variant.INFO,
        detail: String? = null,
        label: String? = null,
        durationMs: Long = 2800
    ) {
        toastJob?.cancel()
        toast = ToastPayload(message, variant, detail, label)
        toastJob = viewModelScope.launch {
            delay(durationMs)
            toast = null
        }
    }

    fun hideToast() {
        toastJob?.cancel()
        toast = null
    }

    private fun maybeToastOffline() {
        val now = System.currentTimeMillis()
        if (now - lastOfflineToastAt < 15_000) return
        lastOfflineToastAt = now
        if (isLoggedIn) {
            showToast(
                "Réseau perdu",
                ToastPayload.Variant.WARN,
                detail = "Tu peux continuer à noter — sync plus tard",
                durationMs = 3200
            )
        }
    }

    fun hapticTick() {
        try {
            val ctx = getApplication<Application>()
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(12, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(12)
            }
        } catch (_: Exception) {
        }
    }

    fun login(username: String, password: String, onDone: (Result<Unit>) -> Unit) {
        viewModelScope.launch {
            try {
                BeerSessionStore.clear(getApplication())
                InviteSessionStore.clear(getApplication())
                api.setBaseURL(ServerSettings.LAN_API_BASE)
                val resp = api.login(username, password)
                val me = try {
                    api.me()
                } catch (e: Exception) {
                    throw Exception(
                        "Session non utilisable après login: ${e.message ?: "inconnu"}",
                        e
                    )
                }
                applySession(
                    resp.user ?: me.user ?: username,
                    resp.isAdmin ?: me.isAdmin,
                    true,
                    invite = false
                )
                networkStatus = NetworkStatus.ONLINE
                hideToast()
                serverVersion = try {
                    api.version()
                } catch (_: Exception) {
                    ""
                }
                syncPending()
                prewarmRecentPhotos()
                onDone(Result.success(Unit))
            } catch (e: Exception) {
                onDone(Result.failure(e))
            }
        }
    }

    fun offerInviteLink(link: String) {
        pendingInviteLink = link.trim().ifBlank { null }
    }

    fun consumePendingInviteLink(): String? {
        val v = pendingInviteLink
        pendingInviteLink = null
        return v
    }

    fun joinInvite(inviteLink: String, email: String, onDone: (Result<Unit>) -> Unit) {
        viewModelScope.launch {
            try {
                val resp = api.joinInvite(inviteLink, email)
                pendingInviteLink = null
                applySession(
                    resp.user ?: "invite",
                    admin = false,
                    loggedIn = true,
                    invite = true,
                    label = resp.label
                )
                networkStatus = NetworkStatus.ONLINE
                hideToast()
                serverVersion = try {
                    api.version()
                } catch (_: Exception) {
                    ""
                }
                // Même toast que iOS 4.2.7 (bannière succès)
                kotlinx.coroutines.delay(350)
                val name = (resp.label ?: resp.user ?: "").trim()
                val hello = if (name.isEmpty()) "Bienvenue !" else "Bienvenue, $name !"
                showToast(
                    hello,
                    ToastPayload.Variant.SUCCESS,
                    detail = "Compte invité prêt — 4G/5G OK",
                    label = "Invitation",
                    durationMs = 3200
                )
                syncPending()
                prewarmRecentPhotos()
                onDone(Result.success(Unit))
            } catch (e: Exception) {
                onDone(Result.failure(e))
            }
        }
    }

    /**
     * Déconnexion effective — après confirmation UI (comme iOS).
     * Pas de toast : l’alerte système gère l’avertissement invité.
     */
    fun sendFeedback(message: String, category: String, onDone: (Boolean) -> Unit = {}) {
        viewModelScope.launch {
            // Version APK (pas webapp) pour le feedback admin
            val ver = appVersion.takeIf { it != "?" && it.isNotBlank() } ?: ""
            val (ok, err) = withContext(Dispatchers.IO) {
                api.sendFeedback(message, category, ver)
            }
            if (ok) {
                showToast("Merci ! Feedback envoyé.", ToastPayload.Variant.SUCCESS, label = "Feedback")
            } else {
                showToast(err ?: "Envoi impossible", ToastPayload.Variant.ERROR, label = "Feedback")
            }
            onDone(ok)
        }
    }

    fun logout() {
        viewModelScope.launch {
            val wasInvite = isInvite || InviteSessionStore.hasInviteSession(getApplication())
            hideToast()
            try {
                if (!wasInvite) {
                    api.logout()
                } else {
                    api.clearSession()
                }
            } catch (_: Exception) {
                api.clearSession()
            }
            user = null
            isAdmin = false
            isInvite = false
            inviteLabel = null
            isLoggedIn = false
            BeerSessionStore.clear(getApplication())
            InviteSessionStore.clear(getApplication())
            networkStatus = NetworkStatus.ONLINE
            sheet = null
        }
    }

    fun openSheet(s: BeerSheet) {
        sheet = s
    }

    fun closeSheet() {
        if (sheet == BeerSheet.TUTORIAL) markTutorialSeen()
        sheet = null
        selectedCheckin = null
        editingCheckin = null
    }

    fun startRetaste(item: CheckinItem, step: Int = 2) {
        wizardProduct = BeerProduct.fromCheckin(item)
        wizardStep = step
        sheet = null
        selectedCheckin = null
    }

    fun startQuickRate(item: CheckinItem) {
        wizardProduct = BeerProduct.fromCheckin(item)
        wizardStep = 3
        sheet = null
    }

    fun startWishlistTaste(item: WishlistItem) {
        wizardProduct = BeerProduct.fromWishlist(item)
        wizardStep = 1
        sheet = null
    }

    fun clearWizardPrefill() {
        wizardProduct = null
        wizardStep = 1
    }

    fun removePending(id: String) {
        offline.remove(id)
        showToast("Retiré de la file", ToastPayload.Variant.INFO)
    }

    fun removePendingDelete(id: Int) {
        offline.removePendingDelete(id)
    }

    fun requestSync() {
        viewModelScope.launch { probeAndSync() }
    }

    private suspend fun probeAndSync() {
        if (!isNetworkAvailable()) {
            networkStatus = NetworkStatus.OFFLINE
            return
        }
        val t0 = System.currentTimeMillis()
        val ep = api.discoverWorkingEndpoint()
        lastEndpointLatencyMs = System.currentTimeMillis() - t0
        networkStatus = if (ep != null) NetworkStatus.ONLINE else NetworkStatus.SERVER_UNREACHABLE
        if (isLoggedIn && networkStatus == NetworkStatus.ONLINE) {
            syncPending()
            prewarmRecentPhotos()
        }
    }

    suspend fun syncPending() {
        if (!isLoggedIn || networkStatus != NetworkStatus.ONLINE || syncInProgress) return
        if (offline.pendingCount == 0) return
        syncInProgress = true
        try {
            val n = offline.flush(api)
            if (n > 0) {
                showToast("$n action(s) synchronisée(s)", ToastPayload.Variant.SUCCESS)
                listCache.invalidateHistory()
            }
        } finally {
            syncInProgress = false
            refreshOfflineUi()
        }
    }

    /** Précharge les photos récentes pour la galerie hors ligne (best effort). */
    fun prewarmRecentPhotos() {
        if (!isLoggedIn || networkStatus != NetworkStatus.ONLINE) return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val recent = api.checkins(limit = 24, offset = 0)
                listCache.saveCheckins(recent)
                for (item in recent) {
                    val p = item.photoURL ?: continue
                    if (imageCache.has(p)) continue
                    try {
                        val bytes = api.downloadAsset(p)
                        imageCache.put(p, bytes)
                    } catch (_: Exception) {
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Save checkin with offline fallback.
     * Returns status string; "duplicate|..." on duplicate.
     */
    suspend fun saveCheckin(
        product: BeerProduct,
        rating: Double,
        flavors: List<String>,
        hops: List<String>,
        comment: String,
        photoFile: File?,
        force: Boolean,
        location: String = ""
    ): String {
        val loc = location.trim().take(300)
        val compressedPhoto = photoFile?.takeIf { it.exists() }?.let { f ->
            try {
                ImageUtils.compressFile(f)
            } catch (_: Exception) {
                f
            }
        }
        val photoPath = compressedPhoto?.takeIf { it.exists() }?.absolutePath
        val pending = PendingCheckin(
            barcode = product.barcode,
            beerName = product.beerName,
            brewery = product.brewery,
            style = product.style,
            abv = product.abv?.toString().orEmpty(),
            summary = product.summary,
            rating = rating,
            flavors = flavors,
            hops = hops,
            comment = comment,
            untappdBid = product.untappdBid?.toString().orEmpty(),
            force = force,
            photoPath = photoPath,
            location = loc.ifBlank { null }
        )

        val offlineNow = networkStatus != NetworkStatus.ONLINE || !isNetworkAvailable()
        if (offlineNow) {
            offline.enqueue(pending)
            return "Enregistré sur l'appareil — sync au retour réseau"
        }

        return try {
            val bytes = compressedPhoto?.takeIf { it.exists() }?.let {
                ImageUtils.compressJPEG(it.readBytes())
            }
            val result = api.createCheckin(
                barcode = pending.barcode,
                beerName = pending.beerName,
                brewery = pending.brewery,
                style = pending.style,
                abv = pending.abv,
                summary = pending.summary,
                rating = pending.rating,
                flavors = flavors,
                hops = hops,
                comment = pending.comment,
                untappdBid = pending.untappdBid,
                force = force,
                photoJPEG = bytes,
                location = loc
            )
            if (result.duplicate == true) {
                val pc = result.previousCheckin
                return "duplicate|${pc?.beerName ?: product.beerName}|${pc?.rating ?: 0}|${pc?.createdAt.orEmpty()}"
            }
            if (result.ok == true || result.id != null) {
                hapticTick()
                listCache.invalidateHistory()
                // Cache photo locale si on vient d'uploader
                if (bytes != null && result.id != null) {
                    // path unknown until reload — prewarm list later
                    viewModelScope.launch { prewarmRecentPhotos() }
                }
                handleRpgLoot(result.rpg)
                return "Enregistré ✓"
            }
            throw BeerAPI.ApiException(result.error ?: "Échec")
        } catch (e: Exception) {
            if (isNetworkFailure(e)) {
                offline.enqueue(pending)
                networkStatus = NetworkStatus.SERVER_UNREACHABLE
                return "Enregistré sur l'appareil — sync au retour réseau"
            }
            throw e
        }
    }

    fun enqueueDeleteCheckin(id: Int) {
        offline.enqueueDelete(id)
        listCache.invalidateHistory()
        showToast("Suppression en file — sync au retour réseau", ToastPayload.Variant.INFO)
    }

    private fun isNetworkFailure(e: Exception): Boolean {
        val msg = e.message.orEmpty()
        if (e is java.net.UnknownHostException ||
            e is java.net.SocketTimeoutException ||
            e is java.io.IOException
        ) {
            return true
        }
        // Ne pas traiter 401/403 comme réseau
        if (e is BeerAPI.ApiException && e.code in listOf(401, 403, 400, 409, 422)) {
            return false
        }
        return msg.contains("Timeout", true) ||
            msg.contains("Unable to resolve", true) ||
            msg.contains("Failed to connect", true) ||
            msg.contains("Connection", true) ||
            msg.contains("Connection reset", true) ||
            msg.contains("Software caused connection", true) ||
            msg.contains("Network is unreachable", true) ||
            msg.contains("SSL", true) && msg.contains("fail", true)
    }
}
