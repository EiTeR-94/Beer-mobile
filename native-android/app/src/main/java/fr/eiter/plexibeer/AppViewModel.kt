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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

class AppViewModel(app: Application) : AndroidViewModel(app) {
    val api = BeerAPI.getInstance(app)
    val offline = OfflineQueue(app)

    var user by mutableStateOf<String?>(null)
        private set
    var isAdmin by mutableStateOf(false)
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

    val pendingCount: Int get() = offline.pendingCount
    val pendingItems: List<PendingCheckin> get() = offline.items
    val pendingDeletes: List<Int> get() = offline.pendingDeletes

    private var toastJob: Job? = null
    private var syncInProgress = false
    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null

    init {
        viewModelScope.launch { bootstrap() }
        registerConnectivity()
    }

    override fun onCleared() {
        super.onCleared()
        unregisterConnectivity()
    }

    private fun registerConnectivity() {
        val cm = getApplication<Application>().getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                viewModelScope.launch {
                    probeAndSync()
                }
            }

            override fun onLost(network: Network) {
                networkStatus = NetworkStatus.OFFLINE
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

    private fun isNetworkAvailable(): Boolean {
        val cm = getApplication<Application>().getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(net) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    suspend fun bootstrap() {
        isLoading = true
        try {
            if (!isNetworkAvailable()) {
                networkStatus = NetworkStatus.OFFLINE
                restoreOfflineSessionIfNeeded()
                return
            }
            val t0 = System.currentTimeMillis()
            val ep = api.discoverWorkingEndpoint()
            lastEndpointLatencyMs = System.currentTimeMillis() - t0
            if (ep == null) {
                networkStatus = NetworkStatus.SERVER_UNREACHABLE
                restoreOfflineSessionIfNeeded()
                return
            }
            networkStatus = NetworkStatus.ONLINE
            if (api.cookieJar.hasSession()) {
                try {
                    val me = api.me()
                    // api/me: "auth" = auth enabled on server, not "logged in". Trust user field.
                    if (!me.user.isNullOrBlank()) {
                        applySession(me.user!!, me.isAdmin, true)
                        serverVersion = try {
                            api.version()
                        } catch (_: Exception) {
                            ""
                        }
                        syncPending()
                        return
                    }
                    // Server says not authenticated despite cookie
                    api.clearSession()
                    BeerSessionStore.clear(getApplication())
                } catch (e: Exception) {
                    val code = (e as? BeerAPI.ApiException)?.code ?: 0
                    if (code == 401) {
                        // Real session death
                        api.clearSession()
                        BeerSessionStore.clear(getApplication())
                    } else {
                        // Network/SSL: keep cookie + restore identity offline
                        networkStatus = NetworkStatus.SERVER_UNREACHABLE
                        restoreOfflineSessionIfNeeded()
                        return
                    }
                }
            }
            restoreOfflineSessionIfNeeded()
        } finally {
            isLoading = false
        }
    }

    private fun restoreOfflineSessionIfNeeded() {
        val restored = BeerSessionStore.restore(getApplication()) ?: return
        // With valid cookie: stay logged in even if me() couldn't run
        // Without cookie but offline: still show UI for cache browsing
        if (api.cookieJar.hasSession() || networkStatus != NetworkStatus.ONLINE) {
            applySession(restored.first, restored.second, true)
        }
    }

    private fun applySession(userName: String?, admin: Boolean, loggedIn: Boolean) {
        user = userName
        isAdmin = admin
        isLoggedIn = loggedIn
        if (loggedIn && userName != null) {
            BeerSessionStore.save(getApplication(), userName, admin)
        }
    }

    fun showToast(message: String, variant: ToastPayload.Variant = ToastPayload.Variant.INFO, detail: String? = null, durationMs: Long = 2800) {
        toastJob?.cancel()
        toast = ToastPayload(message, variant, detail)
        toastJob = viewModelScope.launch {
            delay(durationMs)
            toast = null
        }
    }

    fun hideToast() {
        toastJob?.cancel()
        toast = null
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
                // api.login clears cookie jar itself then captures Set-Cookie
                api.setBaseURL(ServerSettings.LAN_API_BASE)
                val resp = api.login(username, password)
                // Verify session works immediately (same as iOS post-login me())
                val me = try {
                    api.me()
                } catch (e: Exception) {
                    // Cookie present but me() failed — surface real error
                    throw Exception(
                        "Session non utilisable après login: ${e.message ?: "inconnu"}",
                        e
                    )
                }
                applySession(
                    resp.user ?: me.user ?: username,
                    resp.isAdmin ?: me.isAdmin,
                    true
                )
                networkStatus = NetworkStatus.ONLINE
                hideToast()
                serverVersion = try {
                    api.version()
                } catch (_: Exception) {
                    ""
                }
                syncPending()
                onDone(Result.success(Unit))
            } catch (e: Exception) {
                onDone(Result.failure(e))
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            try {
                api.logout()
            } catch (_: Exception) {
            }
            user = null
            isAdmin = false
            isLoggedIn = false
            BeerSessionStore.clear(getApplication())
            hideToast()
            sheet = null
        }
    }

    fun openSheet(s: BeerSheet) {
        sheet = s
    }

    fun closeSheet() {
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
        // trigger recomposition
        showToast("File mise à jour", ToastPayload.Variant.INFO)
    }

    fun removePendingDelete(id: Int) {
        offline.removePendingDelete(id)
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
            }
        } finally {
            syncInProgress = false
        }
    }

    /**
     * Save checkin with offline fallback — mirrors AppModel.saveCheckin.
     * Returns status string; "duplicate|..." on duplicate.
     */
    suspend fun saveCheckin(
        product: BeerProduct,
        rating: Double,
        flavors: List<String>,
        hops: List<String>,
        comment: String,
        photoFile: File?,
        force: Boolean
    ): String {
        // Compress before offline enqueue so flush doesn't upload multi-MB originals
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
            photoPath = photoPath
        )

        if (networkStatus != NetworkStatus.ONLINE || !isNetworkAvailable()) {
            offline.enqueue(pending)
            return "Enregistré sur l'appareil — sync au retour réseau"
        }

        try {
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
                photoJPEG = bytes
            )
            if (result.duplicate == true) {
                val pc = result.previousCheckin
                return "duplicate|${pc?.beerName ?: product.beerName}|${pc?.rating ?: 0}|${pc?.createdAt.orEmpty()}"
            }
            if (result.ok == true || result.id != null) {
                hapticTick()
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

    private fun isNetworkFailure(e: Exception): Boolean {
        val msg = e.message.orEmpty()
        if (e is java.net.UnknownHostException || e is java.net.SocketTimeoutException || e is java.io.IOException) {
            return true
        }
        return msg.contains("Timeout", true) ||
            msg.contains("Unable to resolve", true) ||
            msg.contains("Failed to connect", true) ||
            msg.contains("Connection", true)
    }
}
