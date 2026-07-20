package fr.eiter.plexibeer.ui

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume

@Composable
fun BeerApp(vm: AppViewModel) {
    val context = LocalContext.current
    Box(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
    ) {
        when {
            vm.isLoading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = BeerColors.accent)
                }
            }
            !vm.isLoggedIn -> LoginScreen(vm)
            else -> MainScreen(vm)
        }
        // Bannière haut d'écran = iOS (tap ou × pour fermer)
        ToastOverlay(toast = vm.toast, onDismiss = { vm.hideToast() })
        // Beerquest intro + célébrations (au-dessus du toast)
        if (vm.isLoggedIn) {
            RpgCelebrationOverlay(vm)
        }
    }
}

/** Lit le presse-papiers et ne garde qu'un lien/token d'invitation Beer valide (comme iOS). */
private fun readInviteFromClipboard(context: Context): String? {
    return try {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val raw = cm?.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString()
            ?.trim().orEmpty()
        if (raw.isEmpty()) return null
        if (InviteSessionStore.parseInviteToken(raw) != null) return raw
        // Cherche une URL join dans un texte plus large
        val re = Regex("""https?://[^\s]+/beer(?:-alpha)?/join/[A-Za-z0-9_-]{24,}""")
        val m = re.find(raw)?.value
        if (m != null && InviteSessionStore.parseInviteToken(m) != null) m else null
    } catch (_: Exception) {
        null
    }
}

private fun shortInvitePreview(raw: String): String {
    val t = InviteSessionStore.parseInviteToken(raw)
    return if (t != null && t.length >= 16) {
        "Token : ${t.take(10)}…${t.takeLast(6)}"
    } else {
        raw.take(48) + if (raw.length > 48) "…" else ""
    }
}

@Composable
private fun LoginScreen(vm: AppViewModel) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val deepLink = vm.pendingInviteLink
    var mode by remember(deepLink) { mutableStateOf(if (deepLink != null) "invite" else "owner") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var inviteLink by remember(deepLink) { mutableStateOf(deepLink.orEmpty()) }
    var inviteEmail by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var clipboardHint by remember { mutableStateOf<String?>(null) }
    var showManual by remember { mutableStateOf(false) }

    fun doJoin(link: String) {
        val email = inviteEmail.trim()
        if (email.isEmpty() || !email.contains("@")) {
            error = "Entre l'email que tu as donné pour l'invitation"
            return
        }
        busy = true
        error = null
        vm.joinInvite(link, email) { result ->
            busy = false
            result.onFailure { e -> error = e.message ?: "Activation impossible" }
        }
    }

    fun applyClipboard(autoActivate: Boolean) {
        val clip = readInviteFromClipboard(context)
        if (clip == null) {
            clipboardHint = null
            if (autoActivate) {
                error = "Aucun lien d'invitation dans le presse‑papiers — copie le lien reçu puis réessaie"
            }
            return
        }
        inviteLink = clip
        clipboardHint = "Lien d'invitation prêt — entre ton email puis active"
        error = null
        // Jamais d'auto-activation : l'email doit être saisi explicitement
    }

    // Deep link → préremplit le lien, l'invité saisit l'email puis active
    LaunchedEffect(deepLink) {
        if (!deepLink.isNullOrBlank()) {
            mode = "invite"
            inviteLink = deepLink
            error = null
            clipboardHint = "Lien reçu — entre ton email pour activer"
        }
    }

    // Au premier affichage : si le presse-papiers a déjà un lien join → onglet Invitation
    LaunchedEffect(Unit) {
        if (!deepLink.isNullOrBlank()) return@LaunchedEffect
        val clip = readInviteFromClipboard(context)
        if (clip != null) {
            mode = "invite"
            inviteLink = clip
            clipboardHint = "Lien d'invitation détecté dans le presse‑papiers"
        }
    }

    // Au retour sur l'app (depuis WhatsApp) : relire le presse-papiers si vide
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && mode == "invite" && !busy && inviteLink.isBlank()) {
                applyClipboard(autoActivate = false)
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    Column(
        Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(48.dp))
        Text("🍺", fontSize = 48.sp)
        Text("Beer Log", style = MaterialTheme.typography.headlineLarge, color = BeerColors.text)
        Text("Journal de dégustation privé", color = BeerColors.muted, fontSize = 13.sp)
        Spacer(Modifier.height(20.dp))

        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            BeerGhostButton(
                if (mode == "owner") "• Compte" else "Compte",
                { mode = "owner"; error = null },
                Modifier.weight(1f)
            )
            BeerGhostButton(
                if (mode == "invite") "• Invitation" else "Invitation",
                {
                    mode = "invite"
                    error = null
                    applyClipboard(autoActivate = false)
                },
                Modifier.weight(1f)
            )
        }
        Spacer(Modifier.height(20.dp))

        if (mode == "owner") {
            BeerField("Utilisateur", username, { username = it }, "ton compte")
            Spacer(Modifier.height(10.dp))
            Column(Modifier.fillMaxWidth()) {
                Text("Mot de passe", color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.padding(bottom = 4.dp))
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = BeerColors.text,
                        unfocusedTextColor = BeerColors.text,
                        focusedBorderColor = BeerColors.accent,
                        unfocusedBorderColor = BeerColors.border,
                        cursorColor = BeerColors.accent,
                        focusedContainerColor = BeerColors.fieldBg,
                        unfocusedContainerColor = BeerColors.fieldBg
                    ),
                    shape = RoundedCornerShape(10.dp)
                )
            }
            Spacer(Modifier.height(16.dp))
            error?.let {
                Text(it, color = BeerColors.error, fontSize = 13.sp, modifier = Modifier.padding(bottom = 8.dp))
            }
            BeerPrimaryButton(
                title = if (busy) "Connexion…" else "Se connecter",
                enabled = username.isNotBlank() && password.isNotBlank() && !busy,
                busy = busy
            ) {
                busy = true
                error = null
                vm.login(username.trim(), password) { result ->
                    busy = false
                    result.onFailure { e -> error = e.message ?: "Connexion impossible" }
                }
            }
            Spacer(Modifier.height(12.dp))
            Text("Wi‑Fi maison ou VPN Plexi requis", color = BeerColors.muted, fontSize = 11.sp)
        } else {
            // ——— Invitation : lien + email (pas d'indice UI) ———
            Text(
                "Copie le lien reçu, entre l'email que tu as donné, puis active. Aucun indice d'email dans l'app.",
                color = BeerColors.muted,
                fontSize = 13.sp,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(12.dp))
            BeerSecondaryButton(
                title = "Coller le lien depuis le presse‑papiers",
                enabled = !busy
            ) {
                applyClipboard(autoActivate = false)
            }
            clipboardHint?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = BeerColors.ok, fontSize = 12.sp, modifier = Modifier.fillMaxWidth())
            }
            if (inviteLink.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    shortInvitePreview(inviteLink),
                    color = BeerColors.muted,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Spacer(Modifier.height(12.dp))
            Text("Ton email", color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.padding(bottom = 4.dp))
            OutlinedTextField(
                value = inviteEmail,
                onValueChange = { inviteEmail = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                placeholder = {
                    Text("celui que tu as donné", color = BeerColors.muted, fontSize = 12.sp)
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = BeerColors.text,
                    unfocusedTextColor = BeerColors.text,
                    focusedBorderColor = BeerColors.accent,
                    unfocusedBorderColor = BeerColors.border,
                    cursorColor = BeerColors.accent,
                    focusedContainerColor = BeerColors.fieldBg,
                    unfocusedContainerColor = BeerColors.fieldBg
                ),
                shape = RoundedCornerShape(10.dp)
            )
            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = BeerColors.error, fontSize = 13.sp, modifier = Modifier.fillMaxWidth())
            }
            Spacer(Modifier.height(12.dp))
            BeerPrimaryButton(
                title = if (busy) "Activation…" else "Activer l'invitation",
                enabled = inviteLink.isNotBlank() && inviteEmail.isNotBlank() && !busy,
                busy = busy
            ) {
                doJoin(inviteLink.trim())
            }
            Spacer(Modifier.height(12.dp))
            Text(
                if (showManual) "▾ Saisie manuelle du lien" else "▸ Saisie manuelle du lien (rare)",
                color = BeerColors.muted,
                fontSize = 12.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showManual = !showManual }
                    .padding(vertical = 4.dp)
            )
            if (showManual) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = inviteLink,
                    onValueChange = { inviteLink = it },
                    singleLine = false,
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text("https://eiter.freeboxos.fr/beer/join/…", color = BeerColors.muted, fontSize = 12.sp)
                    },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = BeerColors.text,
                        unfocusedTextColor = BeerColors.text,
                        focusedBorderColor = BeerColors.accent,
                        unfocusedBorderColor = BeerColors.border,
                        cursorColor = BeerColors.accent,
                        focusedContainerColor = BeerColors.fieldBg,
                        unfocusedContainerColor = BeerColors.fieldBg
                    ),
                    shape = RoundedCornerShape(10.dp)
                )
            }
            Spacer(Modifier.height(12.dp))
            Text("1 téléphone · email requis · 4G/5G OK", color = BeerColors.muted, fontSize = 11.sp)
        }
        Spacer(Modifier.height(16.dp))
        Text("Scan · photo · note · historique", color = BeerColors.muted, fontSize = 12.sp)
    }
}

@Composable
private fun MainScreen(vm: AppViewModel) {
    BackHandler(enabled = vm.sheet != null) { vm.closeSheet() }

    var showAccountMenu by remember { mutableStateOf(false) }
    var showLogoutConfirm by remember { mutableStateOf(false) }
    var showFeedback by remember { mutableStateOf(false) }

    LaunchedEffect(vm.requestOpenGrimoire) {
        if (vm.requestOpenGrimoire) {
            vm.consumeOpenGrimoireRequest()
            vm.refreshRpg()
            vm.openSheet(BeerSheet.GRIMOIRE)
        }
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            // Header compact — actions dans « Mon compte » (parité PWA)
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Beer Quest", style = MaterialTheme.typography.headlineSmall, color = BeerColors.text)
                        Text(
                            if (vm.serverVersion.isNotBlank()) "v${vm.serverVersion} · scan · photo · note"
                            else "scan · photo · note",
                            color = BeerColors.muted,
                            fontSize = 12.sp
                        )
                    }
                    OutlinedButton(
                        onClick = { showAccountMenu = true },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = BeerColors.text),
                        border = BorderStroke(1.dp, BeerColors.border),
                        shape = RoundedCornerShape(10.dp),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                    ) {
                        Text("Mon compte", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    }
                }
                Spacer(Modifier.height(8.dp))
                if (vm.needsAppUpdate) {
                    AppUpdateBanner(
                        current = vm.appVersion,
                        latest = vm.latestAndroidVersion ?: "?",
                        portalUrl = ServerSettings.portalURL
                    )
                    Spacer(Modifier.height(8.dp))
                }
                // Beerquest HUD (raccourci grimoire, comme PWA)
                vm.rpgState?.profile?.takeIf { vm.rpgActive }?.let { profile ->
                    BqHudBar(profile) {
                        vm.refreshRpg()
                        vm.openSheet(BeerSheet.GRIMOIRE)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }

            if (vm.networkStatus != NetworkStatus.ONLINE || vm.pendingCount > 0) {
                Box(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
                    NetworkStatusBar(vm.networkStatus, vm.pendingCount, vm.lastEndpointLatencyMs)
                }
                if (vm.networkStatus != NetworkStatus.ONLINE && vm.pendingCount > 0) {
                    Text(
                        "Mode offline — ${vm.pendingCount} en file, sync auto au retour réseau",
                        color = BeerColors.muted,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp)
                    )
                }
            }

            BeerStepNav(vm.wizardStep) { vm.wizardStep = it }

            Box(Modifier.weight(1f)) {
                BeerWizard(vm)
            }
        }

        if (showAccountMenu) {
            AccountMenuOverlay(
                vm = vm,
                onDismiss = { showAccountMenu = false },
                onOpen = { sheet ->
                    showAccountMenu = false
                    when (sheet) {
                        BeerSheet.GRIMOIRE -> {
                            vm.refreshRpg()
                            vm.openSheet(sheet)
                        }
                        else -> vm.openSheet(sheet)
                    }
                },
                onFeedback = {
                    showAccountMenu = false
                    showFeedback = true
                },
                onLogout = {
                    showAccountMenu = false
                    showLogoutConfirm = true
                }
            )
        }

        if (showFeedback) {
            FeedbackDialog(
                onDismiss = { showFeedback = false },
                onSend = { msg, cat ->
                    vm.sendFeedback(msg, cat) { ok ->
                        if (ok) showFeedback = false
                    }
                }
            )
        }

        // Popup réponses admin feedback (parité iOS/web)
        vm.currentFeedbackReply?.let { item ->
            FeedbackReplyDialog(
                item = item,
                index = vm.feedbackReplyIndex,
                total = vm.pendingFeedbackReplies.size,
                onNext = { vm.advanceFeedbackReply() }
            )
        }

        if (showLogoutConfirm) {
            val invite = vm.isInvite
            AlertDialog(
                onDismissRequest = { showLogoutConfirm = false },
                title = { Text("Se déconnecter ?") },
                text = {
                    Text(
                        if (invite) {
                            "Tu perds l'accès sur cet appareil. Il faudra un nouveau lien d'invitation pour revenir."
                        } else {
                            "Tu devras te reconnecter (Wi‑Fi maison ou VPN) pour accéder à Beer Log."
                        }
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showLogoutConfirm = false
                        vm.logout()
                    }) {
                        Text("Se déconnecter", color = BeerColors.error)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showLogoutConfirm = false }) {
                        Text("Annuler")
                    }
                }
            )
        }

        // Sheets as full-screen overlays
        when (vm.sheet) {
            BeerSheet.HISTORY -> HistorySheet(vm)
            BeerSheet.GALLERY -> GallerySheet(vm)
            BeerSheet.WISHLIST -> WishlistSheet(vm)
            BeerSheet.GIFTS -> GiftsSheet(vm)
            BeerSheet.PENDING -> PendingSheet(vm)
            BeerSheet.DETAIL -> vm.selectedCheckin?.let { CheckinDetailSheet(vm, it) }
            BeerSheet.EDIT -> vm.editingCheckin?.let { CheckinEditSheet(vm, it) }
            BeerSheet.PATCHNOTES -> PatchnotesSheet(vm)
            BeerSheet.ADMIN -> AdminSheet(vm)
            BeerSheet.GRIMOIRE -> GrimoireSheet(vm)
            BeerSheet.RPG_ADMIN -> RpgAdminSheet(vm)
            null -> {}
        }
    }
}

@Composable
private fun AccountMenuOverlay(
    vm: AppViewModel,
    onDismiss: () -> Unit,
    onOpen: (BeerSheet) -> Unit,
    onFeedback: () -> Unit,
    onLogout: () -> Unit,
) {
    BackHandler(onBack = onDismiss)
    val config = LocalConfiguration.current
    // Plafond écran uniquement si le contenu dépasse — sinon hauteur = contenu (sous Déconnexion)
    val maxPanelH = minOf(config.screenHeightDp * 0.72f, (config.screenHeightDp - 72).toFloat()).dp
    val maxPanelW = minOf(320, config.screenWidthDp - 60).coerceAtLeast(240).dp

    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable(onClick = onDismiss)
        )
        // wrapContentHeight : pas de vide sous Déconnexion ; heightIn max seulement si trop long
        Column(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 56.dp, end = 12.dp)
                .width(maxPanelW)
                .wrapContentHeight()
                .heightIn(max = maxPanelH)
                .clip(RoundedCornerShape(16.dp))
                .border(1.dp, BeerColors.border, RoundedCornerShape(16.dp))
                .background(BeerColors.card)
                .verticalScroll(rememberScrollState(), enabled = true)
                .padding(horizontal = 10.dp, vertical = 12.dp)
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 4.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "Connecté",
                        color = BeerColors.muted,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        when {
                            vm.isInvite -> vm.inviteLabel?.let { "invité · $it" } ?: "invité"
                            else -> vm.user ?: "—"
                        },
                        color = BeerColors.text,
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp
                    )
                }
                Text(
                    "×",
                    color = BeerColors.muted,
                    fontSize = 20.sp,
                    modifier = Modifier
                        .clickable(onClick = onDismiss)
                        .padding(4.dp)
                )
            }
            Spacer(Modifier.height(6.dp))

            AccountSection("Journal")
            AccountMenuItem("📜 Historique") { onOpen(BeerSheet.HISTORY) }
            if (!vm.isInvite) {
                AccountMenuItem("🍺 À boire") { onOpen(BeerSheet.WISHLIST) }
                AccountMenuItem("🎁 Idées cadeaux") { onOpen(BeerSheet.GIFTS) }
            }
            if (vm.rpgActive) {
                AccountMenuItem("📖 Grimoire") { onOpen(BeerSheet.GRIMOIRE) }
            }
            if (vm.pendingCount > 0) {
                AccountMenuItem("⏳ En attente (${vm.pendingCount})") { onOpen(BeerSheet.PENDING) }
            }

            AccountSection("Parler à l’admin")
            AccountMenuItem("💬 Un retour") { onFeedback() }

            if (vm.isAdmin) {
                AccountSection("Admin")
                AccountMenuItem("⚙️ Administration") { onOpen(BeerSheet.ADMIN) }
                if (vm.rpgActive) {
                    AccountMenuItem("⚔ Beerquest") { onOpen(BeerSheet.RPG_ADMIN) }
                }
                AccountMenuItem("📝 Patch notes") { onOpen(BeerSheet.PATCHNOTES) }
            }

            AccountSection("Session")
            AccountMenuItem("Déconnexion", danger = true) { onLogout() }
        }
    }
}

@Composable
private fun AccountSection(title: String) {
    Text(
        title,
        color = BeerColors.muted,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 6.dp, top = 10.dp, bottom = 4.dp)
    )
}

@Composable
private fun AccountMenuItem(label: String, danger: Boolean = false, onClick: () -> Unit) {
    Text(
        label,
        color = if (danger) BeerColors.error else BeerColors.text,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 11.dp)
    )
}

@Composable
private fun AppUpdateBanner(current: String, latest: String, portalUrl: String) {
    val ctx = LocalContext.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(BeerColors.accent.copy(alpha = 0.12f))
            .border(1.dp, BeerColors.accent.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
            .clickable {
                try {
                    ctx.startActivity(
                        android.content.Intent(
                            android.content.Intent.ACTION_VIEW,
                            android.net.Uri.parse(portalUrl)
                        )
                    )
                } catch (_: Exception) {
                }
            }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                "⬆️ Mise à jour APK disponible",
                color = BeerColors.accent,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp
            )
            Text(
                "v$current → v$latest — tape pour le portail",
                color = BeerColors.muted,
                fontSize = 11.sp
            )
        }
        Text("→", color = BeerColors.accent, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun FeedbackReplyDialog(
    item: AdminFeedbackItem,
    index: Int,
    total: Int,
    onNext: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { /* forcer Compris */ },
        title = {
            Text(
                if (item.isRejected) "Feedback refusé" else "Feedback mis en place",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column {
                Text(
                    item.displayStatus,
                    color = BeerColors.accent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(6.dp))
                item.message?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        "Tu avais écrit : « ${it.take(220)}${if (it.length > 220) "…" else ""} »",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(6.dp))
                }
                Text(
                    item.adminReply
                        ?: if (item.isRejected) "Ta demande n'a pas été retenue."
                        else "Ta demande a été prise en compte.",
                    color = BeerColors.text,
                    fontSize = 14.sp
                )
                if (total > 1) {
                    Spacer(Modifier.height(8.dp))
                    Text("${index + 1} / $total", color = BeerColors.muted, fontSize = 11.sp)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onNext) {
                Text(if (index + 1 < total) "Suivant" else "Compris", color = BeerColors.accent)
            }
        },
        containerColor = BeerColors.card
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FeedbackDialog(
    onDismiss: () -> Unit,
    onSend: (message: String, category: String) -> Unit,
) {
    var message by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("general") }
    var sending by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val scrollState = rememberScrollState()
    val bringIntoView = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    val categories = listOf(
        "general" to "Avis général",
        "bug" to "Bug",
        "idea" to "Idée",
        "ux" to "Interface",
        "rpg" to "RPG",
        "other" to "Autre",
    )

    fun hideKeyboard() {
        focusManager.clearFocus(force = true)
        keyboard?.hide()
    }

    // Dialog + imePadding (pas ModalBottomSheet) : le champ reste au-dessus du clavier
    Dialog(
        onDismissRequest = {
            if (!sending) {
                hideKeyboard()
                onDismiss()
            }
        },
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = true,
            dismissOnBackPress = !sending,
            dismissOnClickOutside = !sending,
        ),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable(enabled = !sending) {
                    hideKeyboard()
                    onDismiss()
                }
                .imePadding()
                .navigationBarsPadding()
                .statusBarsPadding()
        ) {
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
                    .background(BeerColors.bg)
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                    ) { /* absorbe les taps pour ne pas fermer */ }
                    .verticalScroll(scrollState)
                    .padding(horizontal = 16.dp)
                    .padding(top = 12.dp, bottom = 20.dp)
            ) {
                Box(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .width(36.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(BeerColors.muted.copy(alpha = 0.45f))
                )
                Spacer(Modifier.height(12.dp))
                Text("💬 Feedback", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Spacer(Modifier.height(6.dp))
                Text(
                    "Dis-nous ce qui va, ce qui coince ou une idée. Seul l’admin le lit.",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
                Spacer(Modifier.height(12.dp))
                Text("C’est plutôt…", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                categories.chunked(3).forEach { row ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        row.forEach { (key, label) ->
                            val on = category == key
                            Text(
                                label,
                                color = if (on) Color.Black else BeerColors.text,
                                fontSize = 12.sp,
                                fontWeight = if (on) FontWeight.Bold else FontWeight.SemiBold,
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (on) BeerColors.accent else BeerColors.card)
                                    .border(
                                        1.dp,
                                        if (on) BeerColors.accent else BeerColors.border,
                                        RoundedCornerShape(10.dp)
                                    )
                                    .clickable {
                                        category = key
                                        hideKeyboard()
                                    }
                                    .padding(vertical = 8.dp),
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center
                            )
                        }
                        repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                    Spacer(Modifier.height(6.dp))
                }
                Spacer(Modifier.height(8.dp))
                Text("Ton message", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = message,
                    onValueChange = { if (it.length <= 1200) message = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 100.dp, max = 160.dp)
                        .bringIntoViewRequester(bringIntoView)
                        .onFocusEvent { state ->
                            if (state.isFocused) {
                                scope.launch {
                                    delay(280)
                                    bringIntoView.bringIntoView()
                                    scrollState.animateScrollTo(scrollState.maxValue)
                                }
                            }
                        },
                    placeholder = { Text("Écris librement…", color = BeerColors.muted) },
                    maxLines = 6,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        imeAction = androidx.compose.ui.text.input.ImeAction.Done
                    ),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                        onDone = { hideKeyboard() }
                    ),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = BeerColors.text,
                        unfocusedTextColor = BeerColors.text,
                        focusedBorderColor = BeerColors.accent,
                        unfocusedBorderColor = BeerColors.border,
                        cursorColor = BeerColors.accent,
                        focusedContainerColor = BeerColors.card,
                        unfocusedContainerColor = BeerColors.card,
                    )
                )
                Row(
                    Modifier.fillMaxWidth().padding(top = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = { hideKeyboard() }) {
                        Text("Masquer le clavier", color = BeerColors.accent, fontSize = 12.sp)
                    }
                    Text(
                        "${message.length.coerceAtMost(1200)}/1200",
                        color = BeerColors.muted,
                        fontSize = 11.sp
                    )
                }
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            hideKeyboard()
                            if (!sending) onDismiss()
                        },
                        enabled = !sending,
                        modifier = Modifier.weight(1f),
                        border = BorderStroke(1.dp, BeerColors.border)
                    ) {
                        Text("Annuler", color = BeerColors.muted)
                    }
                    Button(
                        onClick = {
                            if (message.trim().length < 3 || sending) return@Button
                            hideKeyboard()
                            sending = true
                            onSend(message.trim(), category)
                        },
                        enabled = message.trim().length >= 3 && !sending,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)
                    ) {
                        Text(
                            if (sending) "…" else "Envoyer",
                            color = Color.Black,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

// ───────────────────────── Wizard ─────────────────────────

@Composable
private fun BeerWizard(vm: AppViewModel) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = vm.api

    var product by remember { mutableStateOf<BeerProduct?>(null) }
    var scanStatus by remember { mutableStateOf("Cadre le code-barres dans le rectangle") }
    var busy by remember { mutableStateOf(false) }
    var untappdBrewery by remember { mutableStateOf("") }
    var untappdName by remember { mutableStateOf("") }
    var untappdResults by remember { mutableStateOf(listOf<UntappdHit>()) }
    var untappdError by remember { mutableStateOf<String?>(null) }
    var showManual by remember { mutableStateOf(false) }
    var showEanManual by remember { mutableStateOf(false) }
    var manualEan by remember { mutableStateOf("") }
    var manualName by remember { mutableStateOf("") }
    var manualBrewery by remember { mutableStateOf("") }
    var manualStyle by remember { mutableStateOf("") }
    var customStyle by remember { mutableStateOf("") }
    var styleOptions by remember { mutableStateOf(listOf<StyleOption>()) }
    var photoFile by remember { mutableStateOf<File?>(null) }
    /** Lieu / lien de dégustation (optionnel) — saisi à l'étape Photo, comme iOS. */
    var location by remember { mutableStateOf("") }
    var rating by remember { mutableFloatStateOf(3f) }
    var comment by remember { mutableStateOf("") }
    var flavors by remember { mutableStateOf(setOf<String>()) }
    var hops by remember { mutableStateOf(setOf<String>()) }
    var flavorTags by remember { mutableStateOf(listOf<String>()) }
    var hopTags by remember { mutableStateOf(listOf<String>()) }
    var showFlavors by remember { mutableStateOf(true) }
    var showHops by remember { mutableStateOf(true) }
    var customFlavor by remember { mutableStateOf("") }
    var customHop by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var showDuplicate by remember { mutableStateOf(false) }
    var duplicateDetail by remember { mutableStateOf("") }
    var pendingCapture by remember { mutableStateOf<File?>(null) }
    var captureMode by remember { mutableStateOf("photo") } // photo | scan
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }

    // Apply prefill from retaste / wishlist
    LaunchedEffect(vm.wizardProduct) {
        vm.wizardProduct?.let {
            product = it
            scanStatus = "Prérempli ✓"
        }
    }

    LaunchedEffect(Unit) {
        styleOptions = api.styles()
    }

    LaunchedEffect(vm.wizardStep, product) {
        if (vm.wizardStep == 3 && product != null) {
            try {
                val fh = api.flavors(product!!.displayStyle, product!!.summary)
                flavorTags = (fh.suggestedFlavors ?: fh.flavors).orEmpty()
                hopTags = (fh.suggestedHops ?: fh.hops).orEmpty()
                showFlavors = fh.showFlavorsBlock != false
                showHops = fh.showHopsBlock != false
            } catch (_: Exception) {
            }
        }
    }

    fun resetWizard() {
        product = null
        scanStatus = "Cadre le code-barres dans le rectangle"
        photoFile = null
        location = ""
        rating = 3f
        comment = ""
        flavors = emptySet()
        hops = emptySet()
        untappdResults = emptyList()
        untappdError = null
        manualEan = ""
        manualName = ""
        manualBrewery = ""
        manualStyle = ""
        customStyle = ""
        vm.clearWizardPrefill()
        vm.wizardStep = 1
    }

    val eanLookupMutex = remember { Mutex() }

    /** Lookup EAN après lecture live ou photo (mutex = pas de double lookup en cascade). */
    suspend fun lookupScannedEan(rawCode: String, fromLive: Boolean) {
        val digits = rawCode.filter { it.isDigit() }
        if (digits.length < 8) {
            scanStatus = "Code trop court"
            return
        }
        if (!eanLookupMutex.tryLock()) return
        busy = true
        manualEan = digits
        scanStatus = "Recherche…"
        try {
            val res = api.lookup(digits)
            if (res.ok) {
                product = res.asProduct(digits)
                scanStatus = "Bière identifiée ✓"
                vm.showToast(
                    "Code-barres lu ✓",
                    ToastPayload.Variant.SUCCESS,
                    digits,
                    label = if (fromLive) "Scan" else "Photo",
                )
            } else {
                scanStatus = res.error ?: "Scanné $digits (introuvable)"
                product = BeerProduct(barcode = digits, beerName = "")
                vm.showToast(
                    "Code lu — introuvable",
                    ToastPayload.Variant.WARN,
                    digits,
                    label = if (fromLive) "Scan" else "Photo",
                )
            }
        } catch (e: Exception) {
            scanStatus = e.message ?: "Erreur"
        } finally {
            busy = false
            eanLookupMutex.unlock()
        }
    }

    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val f = pendingCapture
        pendingCapture = null
        if (!ok || f == null) return@rememberLauncherForActivityResult
        if (captureMode == "photo") {
            photoFile = f
            vm.showToast("Photo prête ✓", ToastPayload.Variant.SUCCESS)
        } else {
            scope.launch {
                // busy coupe le live scan pendant le décodage photo
                busy = true
                scanStatus = "Décodage photo…"
                var decoded: String? = null
                var serverProduct: BeerProduct? = null
                var decodeError: String? = null
                try {
                    val jpeg = ImageUtils.compressJPEG(f.readBytes())
                    val mlCode = tryMlKitBarcode(context, f)?.filter { it.isDigit() }
                    if (!mlCode.isNullOrBlank() && mlCode.length >= 8) {
                        decoded = mlCode
                    } else {
                        val scan = api.scanPhoto(jpeg)
                        if (scan.ok) {
                            val digits = scan.barcode.orEmpty().filter { it.isDigit() }
                            if (digits.length >= 8) {
                                decoded = digits
                            } else {
                                serverProduct = scan.asProduct(digits)
                            }
                        } else {
                            decodeError = scan.error ?: "Code illisible"
                        }
                    }
                } catch (e: Exception) {
                    decodeError = e.message ?: "Erreur scan"
                } finally {
                    busy = false
                    try { f.delete() } catch (_: Exception) {}
                }

                when {
                    decoded != null -> lookupScannedEan(decoded!!, fromLive = false)
                    serverProduct != null -> {
                        product = serverProduct
                        scanStatus = "Bière identifiée ✓"
                        vm.showToast("Code-barres lu ✓", ToastPayload.Variant.SUCCESS)
                    }
                    decodeError != null -> scanStatus = decodeError!!
                }
            }
        }
    }

    fun launchCamera(mode: String) {
        captureMode = mode
        if (!hasCameraPermission) {
            vm.showToast("Autorise la caméra puis réessaie", ToastPayload.Variant.WARN)
            return
        }
        try {
            val dir = File(context.cacheDir, "beer").apply { mkdirs() }
            val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val f = File(dir, "${mode}_$ts.jpg")
            val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", f)
            pendingCapture = f
            takePicture.launch(uri)
        } catch (e: Exception) {
            vm.showToast("Caméra: ${e.message}", ToastPayload.Variant.ERROR)
        }
    }

    /** pendingCamAction: null = live only, "scan"|"photo" = open still camera after grant */
    var pendingCamAction by remember { mutableStateOf<String?>(null) }

    val camPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCameraPermission = granted
        val action = pendingCamAction
        pendingCamAction = null
        if (!granted) {
            vm.showToast("Permission caméra refusée", ToastPayload.Variant.ERROR)
            return@rememberLauncherForActivityResult
        }
        if (action == "scan" || action == "photo") {
            launchCamera(action)
        }
        // sinon : scan live s'active tout seul via recomposition
    }

    fun ensureCamera(mode: String) {
        captureMode = mode
        if (hasCameraPermission) {
            launchCamera(mode)
        } else {
            pendingCamAction = mode
            camPerm.launch(Manifest.permission.CAMERA)
        }
    }

    fun ensureLiveCameraPermission() {
        if (hasCameraPermission) return
        pendingCamAction = null
        camPerm.launch(Manifest.permission.CAMERA)
    }

    // Demande caméra dès l'étape scan (comme iOS)
    LaunchedEffect(vm.wizardStep) {
        if (vm.wizardStep == 1 && !hasCameraPermission) {
            ensureLiveCameraPermission()
        }
    }

    suspend fun doSave(force: Boolean) {
        val p = product ?: return
        if (p.beerName.isBlank()) {
            vm.showToast("Nom de bière requis", ToastPayload.Variant.WARN)
            return
        }
        saving = true
        try {
            val msg = vm.saveCheckin(
                product = p,
                rating = rating.toDouble(),
                flavors = flavors.toList(),
                hops = hops.toList(),
                comment = comment,
                photoFile = photoFile,
                force = force,
                location = location
            )
            if (msg.startsWith("duplicate|")) {
                val parts = msg.split("|")
                duplicateDetail = "Déjà notée: ${parts.getOrNull(1)} ★${parts.getOrNull(2)} (${parts.getOrNull(3)})"
                showDuplicate = true
            } else {
                vm.showToast(msg, ToastPayload.Variant.SUCCESS)
                resetWizard()
            }
        } catch (e: Exception) {
            vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
        } finally {
            saving = false
        }
    }

    if (showDuplicate) {
        AlertDialog(
            onDismissRequest = { showDuplicate = false },
            title = { Text("Déjà dégustée") },
            text = {
                Text(
                    if (duplicateDetail.isBlank()) "Ajouter cette nouvelle note à ton historique ?"
                    else duplicateDetail
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDuplicate = false
                    scope.launch { doSave(force = true) }
                }) { Text("Noter à nouveau") }
            },
            dismissButton = {
                TextButton(onClick = { showDuplicate = false }) { Text("Annuler") }
            }
        )
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        when (vm.wizardStep) {
            1 -> {
                BeerLead("Scan EAN optionnel — ou cherche directement sur Untappd.")

                // Scan live auto (parité iOS) + bouton photo secours
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(BeerColors.photoBg)
                        .border(1.dp, BeerColors.border, RoundedCornerShape(16.dp))
                ) {
                    if (hasCameraPermission) {
                        LiveBarcodeScanner(
                            enabled = !busy && vm.wizardStep == 1,
                            onCode = { code ->
                                scope.launch { lookupScannedEan(code, fromLive = true) }
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        Column(
                            Modifier
                                .fillMaxSize()
                                .clickable { ensureLiveCameraPermission() },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Text("📷", fontSize = 32.sp)
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "Autoriser la caméra pour le scan auto",
                                color = BeerColors.muted,
                                fontSize = 13.sp,
                            )
                        }
                    }

                    // Bouton photo (fallback comme iOS « Prendre photo »)
                    OutlinedButton(
                        onClick = { ensureCamera("scan") },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 12.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = BeerColors.card.copy(alpha = 0.92f),
                            contentColor = BeerColors.text,
                        ),
                        border = BorderStroke(1.dp, BeerColors.border),
                        shape = RoundedCornerShape(10.dp),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text("Prendre photo", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }

                    if (busy) {
                        CircularProgressIndicator(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(12.dp)
                                .size(22.dp),
                            color = BeerColors.accent,
                            strokeWidth = 2.dp,
                        )
                    }
                }
                Text(
                    scanStatus,
                    color = BeerColors.muted,
                    fontSize = 13.sp,
                    modifier = Modifier.fillMaxWidth(),
                )

                BeerCard {
                    Text("Chercher sur Untappd", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Top 5 résultats. Utilise Brasserie + Nom pour affiner.",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    BeerField("Brasserie (optionnel)", untappdBrewery, { untappdBrewery = it }, "ex. Les Intenables")
                    Spacer(Modifier.height(6.dp))
                    BeerField("Nom de la bière", untappdName, { untappdName = it }, "ex. Mama Whipa")
                    Spacer(Modifier.height(8.dp))
                    BeerPrimaryButton(
                        title = if (busy) "Recherche…" else "Chercher sur Untappd",
                        enabled = untappdName.length >= 2 || untappdBrewery.length >= 2,
                        busy = busy
                    ) {
                        scope.launch {
                            busy = true
                            untappdError = null
                            try {
                                val q = listOf(untappdBrewery, untappdName).filter { it.isNotBlank() }.joinToString(" ")
                                val resp = api.searchUntappd(q)
                                untappdResults = resp.results.orEmpty()
                                if (untappdResults.isEmpty()) untappdError = resp.error ?: "Aucun résultat"
                            } catch (e: Exception) {
                                untappdError = e.message
                            } finally {
                                busy = false
                            }
                        }
                    }
                    untappdError?.let { Text(it, color = BeerColors.error, fontSize = 12.sp) }
                    untappdResults.forEach { hit ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
                                .clickable {
                                    scope.launch {
                                        busy = true
                                        try {
                                            val fetched = api.untappdFetch(
                                                bid = hit.bid,
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty()
                                            )
                                            product = if (fetched.ok) {
                                                fetched.asProduct("").let { pr ->
                                                    if (pr.untappdBid == null) pr.copy(untappdBid = hit.bid) else pr
                                                }
                                            } else BeerProduct(
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty(),
                                                style = hit.styleFr ?: "Unknown",
                                                untappdBid = hit.bid
                                            )
                                            // Link EAN ↔ Untappd when we already scanned a barcode (iOS linkProduct)
                                            val bc = product?.barcode?.filter { it.isDigit() }.orEmpty()
                                            if (bc.length >= 8) {
                                                try {
                                                    api.linkProduct(
                                                        bid = hit.bid,
                                                        barcode = bc,
                                                        beerName = product!!.beerName,
                                                        brewery = product!!.brewery
                                                    )
                                                } catch (_: Exception) {
                                                }
                                            }
                                            scanStatus = "Untappd ✓"
                                            untappdResults = emptyList()
                                            vm.showToast("Bière sélectionnée ✓", ToastPayload.Variant.SUCCESS)
                                        } catch (e: Exception) {
                                            product = BeerProduct(
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty(),
                                                style = hit.styleFr ?: "Unknown",
                                                untappdBid = hit.bid
                                            )
                                            scanStatus = "Untappd ✓ (sans fetch)"
                                            untappdResults = emptyList()
                                        } finally {
                                            busy = false
                                        }
                                    }
                                }
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (!hit.photoURL.isNullOrBlank()) {
                                AsyncImage(
                                    model = hit.photoURL,
                                    contentDescription = null,
                                    modifier = Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)),
                                    contentScale = ContentScale.Crop
                                )
                                Spacer(Modifier.width(10.dp))
                            }
                            Column(Modifier.weight(1f)) {
                                Text(hit.beerName, color = BeerColors.text, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                Text(
                                    listOfNotNull(hit.brewery, hit.styleFr).joinToString(" · "),
                                    color = BeerColors.muted,
                                    fontSize = 11.sp
                                )
                            }
                            Text("›", color = BeerColors.muted)
                        }
                    }
                }

                // Manual entry
                BeerCard {
                    Text(
                        if (showManual) "▼ Saisie manuelle (secours)" else "▶ Saisie manuelle (secours)",
                        color = BeerColors.muted,
                        modifier = Modifier.clickable { showManual = !showManual }
                    )
                    if (showManual) {
                        Spacer(Modifier.height(8.dp))
                        BeerField("Nom de la bière", manualName, { manualName = it })
                        Spacer(Modifier.height(6.dp))
                        BeerField("Brasserie", manualBrewery, { manualBrewery = it })
                        Spacer(Modifier.height(6.dp))
                        BeerField("Style", manualStyle, { manualStyle = it }, "ex. IPA")
                        if (styleOptions.isNotEmpty()) {
                            Text("Styles serveur: tape le nom exact ou libre", color = BeerColors.muted, fontSize = 11.sp)
                        }
                        Spacer(Modifier.height(8.dp))
                        BeerSecondaryButton("Continuer") {
                            if (manualName.isBlank()) {
                                vm.showToast("Nom requis", ToastPayload.Variant.WARN)
                            } else {
                                val p = BeerProduct(
                                    beerName = manualName.trim(),
                                    brewery = manualBrewery.trim(),
                                    style = manualStyle.ifBlank { "Unknown" },
                                    barcode = manualEan.filter { it.isDigit() }
                                )
                                product = p
                                scanStatus = "Saisie manuelle ✓"
                                // Persist product for future EAN lookup (iOS saveProduct)
                                if (p.barcode.length >= 8) {
                                    scope.launch {
                                        try {
                                            api.saveProduct(p.barcode, p.beerName, p.brewery, p.style)
                                        } catch (_: Exception) {
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                BeerCard {
                    Text(
                        if (showEanManual) "▼ Code illisible ? Saisie EAN" else "▶ Code illisible ? Saisie EAN",
                        color = BeerColors.muted,
                        modifier = Modifier.clickable { showEanManual = !showEanManual }
                    )
                    if (showEanManual) {
                        Spacer(Modifier.height(8.dp))
                        BeerField("Code EAN", manualEan, { manualEan = it }, "ex. 5411680001111", KeyboardType.Number)
                        Spacer(Modifier.height(8.dp))
                        BeerSecondaryButton("Identifier par EAN") {
                            scope.launch {
                                val digits = manualEan.filter { it.isDigit() }
                                if (digits.length < 8) {
                                    scanStatus = "Code trop court"
                                    return@launch
                                }
                                busy = true
                                scanStatus = "Recherche…"
                                try {
                                    val res = api.lookup(digits)
                                    if (res.ok) {
                                        product = res.asProduct(digits)
                                        scanStatus = "Bière identifiée ✓"
                                        vm.showToast("Bière identifiée ✓", ToastPayload.Variant.SUCCESS)
                                    } else {
                                        scanStatus = res.error ?: "Introuvable"
                                        product = BeerProduct(barcode = digits)
                                    }
                                } catch (e: Exception) {
                                    scanStatus = e.message ?: "Erreur"
                                } finally {
                                    busy = false
                                }
                            }
                        }
                    }
                }

                product?.takeIf { it.beerName.isNotBlank() }?.let { p ->
                    BeerPreviewCard(p)
                    BeerSecondaryButton("+ Ajouter à la liste « À boire »") {
                        scope.launch {
                            try {
                                api.addWishlist(p.beerName, p.brewery, p.style, p.barcode)
                                vm.showToast("Ajouté à À boire ✓", ToastPayload.Variant.SUCCESS)
                            } catch (e: Exception) {
                                vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
                            }
                        }
                    }
                    BeerPrimaryButton("Continuer → photo") { vm.wizardStep = 2 }
                }
            }

            2 -> {
                BeerLead("Photo du verre (optionnel) et lieu de dégustation.")
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(BeerColors.card)
                        .border(2.dp, BeerColors.border, RoundedCornerShape(16.dp))
                        .clickable { ensureCamera("photo") },
                    contentAlignment = Alignment.Center
                ) {
                    if (photoFile != null) {
                        AsyncImage(
                            model = photoFile,
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize().padding(8.dp),
                            contentScale = ContentScale.Fit
                        )
                    } else {
                        Text("📷 Prendre une photo", color = BeerColors.muted)
                    }
                }
                if (photoFile != null) {
                    TextButton(onClick = { photoFile = null }) {
                        Text("Retirer la photo", color = BeerColors.error)
                    }
                }

                BeerCard {
                    Text("Où as-tu dégusté ?", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Nom du lieu et/ou lien (Maps, resto…) — optionnel.",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    BeerField(
                        label = "Lieu ou lien",
                        value = location,
                        onChange = { if (it.length <= 300) location = it },
                        placeholder = "ex. Chez nous · Brasserie X · https://maps…"
                    )
                    Text(
                        "${location.length}/300",
                        color = BeerColors.muted,
                        fontSize = 11.sp,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                BeerSecondaryButton("← Retour") { vm.wizardStep = 1 }
                BeerPrimaryButton("Continuer → note") { vm.wizardStep = 3 }
            }

            else -> {
                val p = product
                if (p != null && p.beerName.isNotBlank()) {
                    BeerLead(p.beerName)
                } else {
                    BeerLead("Pas de bière identifiée — retourne à l'étape 1.")
                }

                BeerCard {
                    UntappdRatingSlider(rating, { rating = it }, onTick = { vm.hapticTick() })
                }

                if (showFlavors) {
                    if (flavorTags.isNotEmpty()) {
                        BeerCard {
                            FlavorTagGrid(
                                title = if (p != null && p.displayStyle != "Unknown") "Goûts ${p.displayStyle}" else "Goûts",
                                tags = flavorTags,
                                selected = flavors,
                                maxCount = 8
                            ) { tag ->
                                flavors = if (tag in flavors) flavors - tag else flavors + tag
                            }
                        }
                    }
                    BeerCard {
                        Text("Goûts perso", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                        CustomTagInput("ex. pneus, sucrée…", customFlavor, { customFlavor = it }) {
                            val t = customFlavor.trim()
                            if (t.isNotBlank() && flavors.size < 8) {
                                flavors = flavors + t
                                customFlavor = ""
                            }
                        }
                        if (flavors.isNotEmpty()) {
                            Text("Sélectionnés: ${flavors.joinToString()}", color = BeerColors.muted, fontSize = 12.sp)
                        }
                        Text("Libre — 8 goûts max", color = BeerColors.muted, fontSize = 11.sp)
                    }
                }

                if (showHops) {
                    if (hopTags.isNotEmpty()) {
                        BeerCard {
                            FlavorTagGrid("Houblons", hopTags, hops, 6) { tag ->
                                hops = if (tag in hops) hops - tag else hops + tag
                            }
                        }
                    }
                    BeerCard {
                        Text("Houblons perso", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                        CustomTagInput("ex. Citra, Mosaic…", customHop, { customHop = it }) {
                            val t = customHop.trim()
                            if (t.isNotBlank() && hops.size < 6) {
                                hops = hops + t
                                customHop = ""
                                scope.launch { try { api.addHop(t) } catch (_: Exception) {} }
                            }
                        }
                        if (hops.isNotEmpty()) {
                            Text("Sélectionnés: ${hops.joinToString()}", color = BeerColors.muted, fontSize = 12.sp)
                        }
                    }
                }

                BeerCard {
                    Text("Commentaire (optionnel, 300 car.)", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(
                        value = comment,
                        onValueChange = { if (it.length <= 300) comment = it },
                        placeholder = { Text("Terrasse, avec elle, à refaire…", color = BeerColors.muted.copy(alpha = 0.6f)) },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = BeerColors.text,
                            unfocusedTextColor = BeerColors.text,
                            focusedBorderColor = BeerColors.accent,
                            unfocusedBorderColor = BeerColors.border,
                            cursorColor = BeerColors.accent,
                            focusedContainerColor = BeerColors.fieldBg,
                            unfocusedContainerColor = BeerColors.fieldBg
                        ),
                        shape = RoundedCornerShape(10.dp)
                    )
                    Text("${comment.length}/300", color = BeerColors.muted, fontSize = 11.sp, modifier = Modifier.align(Alignment.End))
                }

                BeerSecondaryButton("← Retour") { vm.wizardStep = 2 }
                BeerPrimaryButton(
                    title = if (saving) "Enregistrement…" else "Enregistrer",
                    enabled = product != null && product!!.beerName.isNotBlank() && rating >= 0.25f,
                    busy = saving
                ) {
                    scope.launch { doSave(force = false) }
                }

                TextButton(onClick = { resetWizard() }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Text("Reset wizard", color = BeerColors.muted)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

private suspend fun tryMlKitBarcode(context: Context, file: File): String? =
    withContext(Dispatchers.IO) {
        try {
            suspendCancellableCoroutine { cont ->
                try {
                    val img = com.google.mlkit.vision.common.InputImage.fromFilePath(context, Uri.fromFile(file))
                    val sc = com.google.mlkit.vision.barcode.BarcodeScanning.getClient()
                    sc.process(img)
                        .addOnSuccessListener { bs ->
                            val code = bs.firstOrNull { b ->
                                val f = b.format
                                (f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_13 ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_8 ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_A ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_E) &&
                                    b.rawValue != null
                            }?.rawValue ?: bs.firstOrNull { it.rawValue != null }?.rawValue
                            try { sc.close() } catch (_: Exception) {}
                            cont.resume(code)
                        }
                        .addOnFailureListener { ex ->
                            try { sc.close() } catch (_: Exception) {}
                            cont.resume(null)
                        }
                    cont.invokeOnCancellation { try { sc.close() } catch (_: Exception) {} }
                } catch (e: Exception) {
                    cont.resume(null)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

// ───────────────────────── Sheets ─────────────────────────

@Composable
private fun SheetScaffold(title: String, onClose: () -> Unit, trailing: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.headlineSmall, color = BeerColors.text, modifier = Modifier.weight(1f))
            trailing?.invoke()
            TextButton(onClick = onClose) { Text("Fermer ✕", color = BeerColors.muted) }
        }
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
private fun HistorySheet(vm: AppViewModel) {
    val api = vm.api
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf(listOf<CheckinItem>()) }
    var stats by remember { mutableStateOf<HistoryStats?>(null) }
    var styles by remember { mutableStateOf(listOf<StyleOption>()) }
    var filterStyle by remember { mutableStateOf("") }
    var filterRating by remember { mutableFloatStateOf(0f) }
    var filterPeriod by remember { mutableStateOf("") }
    var offset by remember { mutableIntStateOf(0) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val pageSize = 10
    val cache = vm.listCache

    suspend fun load(append: Boolean) {
        if (loading) return
        loading = true
        error = null
        try {
            val off = if (append) offset else 0
            val page = api.checkins(
                style = filterStyle,
                minRating = filterRating.toDouble(),
                period = filterPeriod,
                limit = pageSize,
                offset = off
            )
            items = if (append) items + page else page
            offset = off + page.size
            hasMore = page.size >= pageSize
            if (!append) {
                stats = api.stats()
                // Ne cache la page « unfiltered » complète que sans filtres
                if (filterStyle.isEmpty() && filterRating <= 0f && filterPeriod.isEmpty()) {
                    cache.saveCheckins(items)
                    stats?.let { cache.saveStats(it) }
                }
            }
        } catch (e: Exception) {
            if (!append) {
                val cached = cache.loadCheckins()
                if (cached.isNotEmpty()) {
                    items = cached
                    stats = cache.loadStats()
                    error = "Hors ligne — cache local (${vm.networkStatus.label.lowercase()})"
                } else {
                    error = e.message ?: "Impossible de charger (pas de cache)"
                }
            } else {
                error = e.message
            }
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) {
        // Styles: live then cache
        styles = try {
            api.styles().also { if (it.isNotEmpty()) cache.saveStyles(it) }
        } catch (_: Exception) {
            cache.loadStyles()
        }
        // Affiche le cache immédiatement si hors ligne
        if (vm.networkStatus != NetworkStatus.ONLINE) {
            val cached = cache.loadCheckins()
            if (cached.isNotEmpty()) {
                items = cached
                stats = cache.loadStats()
                error = "Hors ligne — cache local"
            }
        }
        load(false)
    }
    LaunchedEffect(filterStyle, filterRating, filterPeriod) {
        offset = 0
        load(false)
    }

    SheetScaffold(
        title = "Historique",
        onClose = { vm.closeSheet() },
        trailing = {
            TextButton(onClick = {
                vm.closeSheet()
                vm.openSheet(BeerSheet.GALLERY)
            }) { Text("📷 Galerie", color = BeerColors.accent) }
        }
    ) {
        stats?.takeIf { it.total > 0 }?.let { s ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                StatCell("${s.total}", "dégust.", Modifier.weight(1f))
                StatCell(formatRating(s.avgRating ?: 0.0), "moyenne", Modifier.weight(1f))
                StatCell(s.topStyles?.firstOrNull()?.style ?: "—", "top style", Modifier.weight(1f))
                StatCell(s.last?.beerName ?: "—", "dernière", Modifier.weight(1f), small = true)
            }
            Spacer(Modifier.height(8.dp))
        }

        // Filters
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(
                selected = filterRating >= 4f,
                onClick = { filterRating = if (filterRating >= 4f) 0f else 4f },
                label = { Text("★4+") }
            )
            FilterChip(
                selected = filterPeriod == "30d",
                onClick = { filterPeriod = if (filterPeriod == "30d") "" else "30d" },
                label = { Text("30j") }
            )
            FilterChip(
                selected = filterPeriod == "7d",
                onClick = { filterPeriod = if (filterPeriod == "7d") "" else "7d" },
                label = { Text("7j") }
            )
        }
        if (styles.isNotEmpty()) {
            var expanded by remember { mutableStateOf(false) }
            TextButton(onClick = { expanded = true }) {
                Text(if (filterStyle.isBlank()) "Style: tous" else "Style: $filterStyle", color = BeerColors.muted)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text("Tous") }, onClick = { filterStyle = ""; expanded = false })
                styles.take(40).forEach { st ->
                    DropdownMenuItem(text = { Text(st.label.ifBlank { st.value }) }, onClick = {
                        filterStyle = st.value
                        expanded = false
                    })
                }
            }
        }

        error?.let { Text(it, color = BeerColors.error, fontSize = 12.sp) }

        when {
            loading && items.isEmpty() -> {
                Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = BeerColors.accent)
                }
            }
            items.isEmpty() -> {
                val hasFilters = filterStyle.isNotEmpty() || filterRating > 0 || filterPeriod.isNotEmpty()
                BeerEmptyState(
                    if (hasFilters) "🔍" else "🍺",
                    if (hasFilters) "Aucun résultat" else "Aucune dégustation",
                    if (hasFilters) "Ajuste les filtres." else "Note ta première bière depuis l'accueil."
                )
            }
            else -> {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f, fill = true)) {
                    items(items, key = { it.id }) { item ->
                        HistoryCard(vm, item,
                            onOpen = {
                                vm.selectedCheckin = item
                                vm.openSheet(BeerSheet.DETAIL)
                            },
                            onEdit = {
                                vm.editingCheckin = item
                                vm.openSheet(BeerSheet.EDIT)
                            },
                            onDelete = {
                                // confirmation handled inside HistoryCard
                            },
                            onConfirmDelete = {
                                scope.launch {
                                    try {
                                        if (vm.networkStatus != NetworkStatus.ONLINE) {
                                            vm.enqueueDeleteCheckin(item.id)
                                        } else {
                                            try {
                                                api.deleteCheckin(item.id)
                                                vm.listCache.invalidateHistory()
                                                vm.showToast("Supprimé", ToastPayload.Variant.SUCCESS)
                                            } catch (e: Exception) {
                                                if (e is java.io.IOException) {
                                                    vm.enqueueDeleteCheckin(item.id)
                                                } else {
                                                    throw e
                                                }
                                            }
                                        }
                                        load(false)
                                    } catch (e: Exception) {
                                        vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                    }
                                }
                            }
                        )
                    }
                    if (hasMore) {
                        item {
                            BeerSecondaryButton(if (loading) "Chargement…" else "Charger 10 de plus") {
                                scope.launch { load(true) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatCell(value: String, label: String, modifier: Modifier = Modifier, small: Boolean = false) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(BeerColors.card)
            .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = if (small) 11.sp else 14.sp, maxLines = 2)
        Text(label, color = BeerColors.muted, fontSize = 11.sp)
    }
}

@Composable
private fun HistoryCard(
    vm: AppViewModel,
    item: CheckinItem,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit = {},
    onConfirmDelete: () -> Unit = onDelete
) {
    var confirmDelete by remember { mutableStateOf(false) }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Supprimer ?") },
            text = { Text("Supprimer « ${item.beerName} » de l'historique ?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onConfirmDelete()
                }) { Text("Supprimer", color = BeerColors.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Annuler") }
            }
        )
    }
    BeerCard {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onOpen),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            BeerAuthImage(
                path = item.photoURL,
                api = vm.api,
                modifier = Modifier.size(88.dp).clip(RoundedCornerShape(10.dp))
            )
            Column(Modifier.weight(1f)) {
                Row {
                    Text(item.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    if (vm.isAdmin && item.hiddenFromPartner == true) {
                        Text("privé", color = BeerColors.accent, fontSize = 10.sp)
                    }
                }
                Text("★ ${formatRating(item.rating)}", color = BeerColors.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    "${item.brewery ?: "—"} · ${item.style ?: "Inconnu"} · ${formatDate(item.createdAt)}",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
                item.location?.trim()?.takeIf { it.isNotEmpty() }?.let {
                    Text("📍 $it", color = BeerColors.muted, fontSize = 12.sp, maxLines = 2)
                }
                item.flavors?.takeIf { it.isNotEmpty() }?.let {
                    Text(it.joinToString(", "), color = BeerColors.muted, fontSize = 12.sp)
                }
                item.hops?.takeIf { it.isNotEmpty() }?.let {
                    Text("Houblons : ${it.joinToString(", ")}", color = BeerColors.muted, fontSize = 12.sp)
                }
                // Commentaire visible (parité iOS) — manquait sur l’APK
                item.comment?.takeIf { it.isNotBlank() }?.let { c ->
                    Spacer(Modifier.height(6.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .height(IntrinsicSize.Min)
                            .clip(RoundedCornerShape(8.dp))
                            .background(BeerColors.bg.copy(alpha = 0.55f))
                    ) {
                        Box(
                            Modifier
                                .width(3.dp)
                                .fillMaxHeight()
                                .background(BeerColors.accent)
                        )
                        Text(
                            "« $c »",
                            color = BeerColors.text,
                            fontSize = 13.sp,
                            fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                            modifier = Modifier
                                .weight(1f)
                                .padding(horizontal = 9.dp, vertical = 7.dp)
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = onEdit) { Text("Modifier", color = BeerColors.accent) }
            TextButton(onClick = {
                vm.startRetaste(item)
            }) { Text("Re-noter", color = BeerColors.text) }
            TextButton(onClick = { confirmDelete = true }) { Text("Suppr.", color = BeerColors.error) }
        }
    }
}

@Composable
private fun GallerySheet(vm: AppViewModel) {
    val api = vm.api
    var items by remember { mutableStateOf(listOf<CheckinItem>()) }
    var styles by remember { mutableStateOf(listOf<StyleOption>()) }
    var filterStyle by remember { mutableStateOf("") }
    var filterRating by remember { mutableFloatStateOf(0f) }
    var filterPeriod by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var offlineHint by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<CheckinItem?>(null) }
    val cache = vm.listCache
    val scope = rememberCoroutineScope()

    suspend fun reload() {
        loading = true
        try {
            styles = try {
                api.styles().also { if (it.isNotEmpty()) cache.saveStyles(it) }
            } catch (_: Exception) {
                cache.loadStyles()
            }
            val live = api.checkins(
                style = filterStyle,
                minRating = filterRating.toDouble(),
                period = filterPeriod,
                limit = 100,
                offset = 0
            )
            if (filterStyle.isEmpty() && filterRating <= 0f && filterPeriod.isEmpty()) {
                cache.saveCheckins(live)
            }
            items = live.filter { !it.photoURL.isNullOrBlank() }
            offlineHint = null
            vm.prewarmRecentPhotos()
        } catch (_: Exception) {
            val cached = cache.loadCheckins().filter { !it.photoURL.isNullOrBlank() }
            items = cached
            offlineHint = if (cached.isEmpty()) {
                "Hors ligne — aucune photo en cache"
            } else {
                "Hors ligne — galerie en cache"
            }
        }
        loading = false
    }

    LaunchedEffect(Unit) {
        val cached = cache.loadCheckins().filter { !it.photoURL.isNullOrBlank() }
        if (cached.isNotEmpty()) items = cached
        reload()
    }
    LaunchedEffect(filterStyle, filterRating, filterPeriod) {
        if (!loading || items.isNotEmpty()) reload()
    }

    SheetScaffold("Galerie photos", onClose = { vm.closeSheet() }) {
        offlineHint?.let {
            Text(it, color = BeerColors.accent, fontSize = 12.sp, modifier = Modifier.padding(bottom = 6.dp))
        }
        // Filtres parité iOS
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(
                selected = filterRating >= 4f,
                onClick = { filterRating = if (filterRating >= 4f) 0f else 4f },
                label = { Text("★4+") }
            )
            FilterChip(
                selected = filterPeriod == "30d",
                onClick = { filterPeriod = if (filterPeriod == "30d") "" else "30d" },
                label = { Text("30j") }
            )
            FilterChip(
                selected = filterPeriod == "7d",
                onClick = { filterPeriod = if (filterPeriod == "7d") "" else "7d" },
                label = { Text("7j") }
            )
        }
        if (styles.isNotEmpty()) {
            var expanded by remember { mutableStateOf(false) }
            TextButton(onClick = { expanded = true }) {
                Text(
                    if (filterStyle.isBlank()) "Style: tous" else "Style: $filterStyle",
                    color = BeerColors.muted
                )
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text("Tous") }, onClick = { filterStyle = ""; expanded = false })
                styles.take(40).forEach { st ->
                    DropdownMenuItem(
                        text = { Text(st.label.ifBlank { st.value }) },
                        onClick = { filterStyle = st.value; expanded = false }
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${items.size} photos", color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.weight(1f))
            if (filterStyle.isNotEmpty() || filterRating > 0 || filterPeriod.isNotEmpty()) {
                TextButton(onClick = {
                    filterStyle = ""; filterRating = 0f; filterPeriod = ""
                }) {
                    Text("Réinit. filtres", color = BeerColors.accent, fontSize = 12.sp)
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        if (loading && items.isEmpty()) {
            CircularProgressIndicator(color = BeerColors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
        } else if (items.isEmpty()) {
            BeerEmptyState("📷", "Aucune photo", "Les dégustations avec photo apparaîtront ici.")
        } else {
            // Grille 3 colonnes (parité iOS LazyVGrid)
            val cols = 3
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(1f, fill = true)) {
                items(items.chunked(cols), key = { row -> row.joinToString("-") { it.id.toString() } }) { row ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        row.forEach { item ->
                            Column(
                                Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable {
                                        selected = item
                                    }
                            ) {
                                BeerAuthImage(
                                    path = item.photoURL,
                                    api = api,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(10.dp))
                                )
                                Text(
                                    item.beerName,
                                    color = BeerColors.text,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 2,
                                    modifier = Modifier.padding(top = 3.dp)
                                )
                                Text(
                                    "★ ${formatRating(item.rating)}",
                                    color = BeerColors.accent,
                                    fontSize = 10.sp
                                )
                            }
                        }
                        // pad empty cells
                        repeat(cols - row.size) {
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }

    selected?.let { item ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(item.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    BeerAuthImage(
                        path = item.photoURL,
                        api = api,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp)
                            .clip(RoundedCornerShape(12.dp))
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${item.brewery ?: "—"} · ★ ${formatRating(item.rating)}",
                        color = BeerColors.muted,
                        fontSize = 13.sp
                    )
                    item.comment?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.height(6.dp))
                        Text("« $it »", color = BeerColors.text, fontSize = 13.sp)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    selected = null
                    vm.selectedCheckin = item
                    vm.openSheet(BeerSheet.DETAIL)
                }) { Text("Voir fiche", color = BeerColors.accent) }
            },
            dismissButton = {
                TextButton(onClick = { selected = null }) { Text("Fermer", color = BeerColors.muted) }
            },
            containerColor = BeerColors.card
        )
    }
}

@Composable
private fun WishlistSheet(vm: AppViewModel) {
    val api = vm.api
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf(listOf<WishlistItem>()) }
    var newName by remember { mutableStateOf("") }
    var newBrewery by remember { mutableStateOf("") }
    var offlineHint by remember { mutableStateOf<String?>(null) }
    val cache = vm.listCache

    suspend fun reload() {
        try {
            val live = api.wishlist()
            cache.saveWishlist(live)
            items = live
            offlineHint = null
        } catch (_: Exception) {
            val cached = cache.loadWishlist()
            items = cached
            offlineHint = if (cached.isEmpty()) {
                "Hors ligne — liste non en cache"
            } else {
                "Hors ligne — wishlist en cache"
            }
        }
    }

    LaunchedEffect(Unit) {
        val cached = cache.loadWishlist()
        if (cached.isNotEmpty()) items = cached
        reload()
    }

    SheetScaffold("À boire", onClose = { vm.closeSheet() }) {
        Text("Tes souhaits personnels (bières à goûter).", color = BeerColors.muted, fontSize = 13.sp)
        offlineHint?.let {
            Text(it, color = BeerColors.accent, fontSize = 12.sp)
        }
        Spacer(Modifier.height(8.dp))
        BeerField("Nom bière", newName, { newName = it })
        Spacer(Modifier.height(6.dp))
        BeerField("Brasserie (optionnel)", newBrewery, { newBrewery = it })
        Spacer(Modifier.height(8.dp))
        BeerPrimaryButton("Ajouter", enabled = newName.length >= 2 && vm.networkStatus == NetworkStatus.ONLINE) {
            scope.launch {
                try {
                    api.addWishlist(newName.trim(), newBrewery.trim())
                    newName = ""
                    newBrewery = ""
                    reload()
                    vm.showToast("Ajouté ✓", ToastPayload.Variant.SUCCESS)
                } catch (e: Exception) {
                    vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        if (items.isEmpty()) {
            BeerEmptyState("🍺", "Liste vide", "Ajoute des bières à goûter.")
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(items, key = { it.id }) { w ->
                    BeerCard {
                        Text(w.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                        Text("${w.brewery.orEmpty()} · ${w.style.orEmpty()}", color = BeerColors.muted, fontSize = 12.sp)
                        Row {
                            TextButton(onClick = { vm.startWishlistTaste(w) }) {
                                Text("Goûter", color = BeerColors.accent)
                            }
                            TextButton(onClick = {
                                scope.launch {
                                    try {
                                        api.deleteWishlist(w.id)
                                        reload()
                                    } catch (e: Exception) {
                                        vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                    }
                                }
                            }) { Text("Suppr.", color = BeerColors.error) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GiftsSheet(vm: AppViewModel) {
    val api = vm.api
    var gifts by remember { mutableStateOf(listOf<GiftIdea>()) }
    var users by remember { mutableStateOf(listOf<CoupleStats.CoupleUser>()) }
    var partner by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var filterStyle by remember { mutableStateOf("") }
    var minRating by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }

    val cache = vm.listCache
    LaunchedEffect(Unit) {
        cache.loadCouple()?.let { cached ->
            gifts = cached.giftIdeas.orEmpty()
            users = cached.users.orEmpty()
            partner = users.firstOrNull { it.username != vm.user }?.username.orEmpty()
        }
        try {
            val data = api.coupleStats()
            gifts = data.giftIdeas.orEmpty()
            users = data.users.orEmpty()
            partner = users.firstOrNull { it.username != vm.user }?.username.orEmpty()
            cache.saveCouple(data)
            error = null
        } catch (e: Exception) {
            if (gifts.isEmpty()) {
                error = e.message ?: "Hors ligne — pas de cache cadeaux"
            } else {
                error = "Hors ligne — idées cadeaux en cache"
            }
        }
        loading = false
    }

    val styleOptions = remember(gifts) {
        gifts.mapNotNull { it.style }.filter { it.isNotEmpty() }.distinct().sorted()
    }
    val filtered = gifts.filter { g ->
        if (minRating > 0) {
            if (minRating >= 5f && (g.rating ?: 0.0) < 4.99) return@filter false
            else if ((g.rating ?: 0.0) < minRating) return@filter false
        }
        if (filterStyle.isNotEmpty() && g.style != filterStyle) return@filter false
        if (search.isNotEmpty()) {
            val hay = "${g.beerName} ${g.brewery.orEmpty()} ${g.style.orEmpty()}".lowercase()
            if (!hay.contains(search.lowercase())) return@filter false
        }
        true
    }

    SheetScaffold(
        title = if (partner.isEmpty()) "Idées cadeaux" else "Idées cadeaux — $partner",
        onClose = { vm.closeSheet() }
    ) {
        error?.let { Text(it, color = BeerColors.error) }
        if (loading) {
            CircularProgressIndicator(color = BeerColors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
            return@SheetScaffold
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            users.forEach { u ->
                Column(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(BeerColors.card)
                        .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
                        .padding(9.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(if (u.username == vm.user) "Toi" else u.username, color = BeerColors.muted, fontSize = 11.sp)
                    Text("${u.total}", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text("dégust.", color = BeerColors.muted, fontSize = 11.sp)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        BeerField("Recherche", search, { search = it }, "nom, brasserie…")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(selected = minRating >= 4f, onClick = { minRating = if (minRating >= 4f) 0f else 4f }, label = { Text("★4+") })
            FilterChip(selected = minRating >= 4.5f, onClick = { minRating = if (minRating >= 4.5f) 0f else 4.5f }, label = { Text("★4.5+") })
        }
        if (filtered.isEmpty()) {
            Text("Aucune idée cadeau avec ces filtres.", color = BeerColors.muted, modifier = Modifier.padding(24.dp))
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f, fill = true)) {
                items(filtered, key = { it.id }) { g ->
                    BeerCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            BeerAuthImage(
                                path = ServerSettings.giftPhotoPath(g.photoPath),
                                api = api,
                                modifier = Modifier.size(88.dp).clip(RoundedCornerShape(10.dp))
                            )
                            Column(Modifier.weight(1f)) {
                                Text(g.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                                Text(
                                    "${g.brewery ?: "—"} · ${g.style ?: "?"}",
                                    color = BeerColors.muted,
                                    fontSize = 12.sp
                                )
                                g.rating?.let {
                                    Text("★ ${formatRating(it)}", color = BeerColors.accent, fontSize = 12.sp)
                                }
                                Text("Notée par ${g.likedBy ?: "?"}", color = BeerColors.muted, fontSize = 11.sp)
                                g.comment?.takeIf { it.isNotBlank() }?.let {
                                    Text("« $it »", color = BeerColors.text, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PendingSheet(vm: AppViewModel) {
    SheetScaffold("En attente", onClose = { vm.closeSheet() }) {
        Text(
            when (vm.networkStatus) {
                NetworkStatus.ONLINE -> "Réseau OK — tu peux synchroniser."
                NetworkStatus.OFFLINE -> "Pas de réseau — les notes restent sur l'appareil."
                NetworkStatus.SERVER_UNREACHABLE -> "Serveur injoignable — file conservée."
            },
            color = BeerColors.muted,
            fontSize = 12.sp
        )
        Spacer(Modifier.height(8.dp))
        BeerPrimaryButton(
            "Synchroniser maintenant",
            enabled = vm.networkStatus == NetworkStatus.ONLINE && vm.pendingCount > 0
        ) {
            vm.requestSync()
        }
        Spacer(Modifier.height(8.dp))
        Text("Créations en attente (${vm.pendingItems.size})", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
        if (vm.pendingItems.isEmpty()) {
            Text("Aucune dégustation en attente.", color = BeerColors.muted)
        } else {
            vm.pendingItems.forEach { p ->
                BeerCard {
                    Text(p.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                    Text("${p.brewery} · ${p.style} · ★${formatRating(p.rating)}", color = BeerColors.muted, fontSize = 12.sp)
                    p.location?.takeIf { it.isNotBlank() }?.let {
                        Text("📍 $it", color = BeerColors.muted, fontSize = 12.sp)
                    }
                    TextButton(onClick = { vm.removePending(p.id) }) {
                        Text("Supprimer", color = BeerColors.error)
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("Suppressions en attente", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
        if (vm.pendingDeletes.isEmpty()) {
            Text("Aucune suppression en attente.", color = BeerColors.muted)
        } else {
            vm.pendingDeletes.forEach { id ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Suppression #$id", color = BeerColors.text, modifier = Modifier.weight(1f))
                    TextButton(onClick = { vm.removePendingDelete(id) }) {
                        Text("Annuler", color = BeerColors.error)
                    }
                }
            }
        }
    }
}

@Composable
private fun CheckinDetailSheet(vm: AppViewModel, item: CheckinItem) {
    val scope = rememberCoroutineScope()
    var hidden by remember { mutableStateOf(item.hiddenFromPartner == true) }

    SheetScaffold(item.beerName, onClose = { vm.closeSheet() }) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            BeerAuthImage(
                path = item.photoURL,
                api = vm.api,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(240.dp)
                    .clip(RoundedCornerShape(12.dp))
            )
            Spacer(Modifier.height(12.dp))
            Text("★ ${formatRating(item.rating)}", color = BeerColors.accent, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text(
                "${item.brewery ?: "—"} · ${item.style ?: "?"} · ${formatDate(item.createdAt)}",
                color = BeerColors.muted
            )
            item.location?.trim()?.takeIf { it.isNotEmpty() }?.let {
                Spacer(Modifier.height(8.dp))
                BeerCard {
                    Text("Lieu", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    Text("📍 $it", color = BeerColors.text, fontSize = 14.sp)
                }
            }
            item.comment?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(8.dp))
                Text("« $it »", color = BeerColors.text)
            }
            item.flavors?.takeIf { it.isNotEmpty() }?.let {
                Text("Goûts: ${it.joinToString()}", color = BeerColors.muted, fontSize = 13.sp)
            }
            item.hops?.takeIf { it.isNotEmpty() }?.let {
                Text("Houblons: ${it.joinToString()}", color = BeerColors.muted, fontSize = 13.sp)
            }
            Spacer(Modifier.height(12.dp))
            BeerPrimaryButton("Re-noter") { vm.startRetaste(item) }
            BeerSecondaryButton("Modifier") {
                vm.editingCheckin = item
                vm.openSheet(BeerSheet.EDIT)
            }
            if (vm.isAdmin) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Masqué partenaire", color = BeerColors.text, modifier = Modifier.weight(1f))
                    Switch(checked = hidden, onCheckedChange = { v ->
                        hidden = v
                        scope.launch {
                            try {
                                vm.api.updateCheckin(item.id, hiddenFromPartner = v)
                                vm.showToast(if (v) "Masqué" else "Visible", ToastPayload.Variant.SUCCESS)
                            } catch (e: Exception) {
                                hidden = !v
                                vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                            }
                        }
                    })
                }
            }
        }
    }
}

@Composable
private fun CheckinEditSheet(vm: AppViewModel, item: CheckinItem) {
    val scope = rememberCoroutineScope()
    var rating by remember { mutableFloatStateOf(item.rating.toFloat()) }
    var comment by remember { mutableStateOf(item.comment.orEmpty()) }
    var location by remember { mutableStateOf(item.location.orEmpty()) }
    var flavors by remember { mutableStateOf(item.flavors.orEmpty().toSet()) }
    var hops by remember { mutableStateOf(item.hops.orEmpty().toSet()) }
    var flavorTags by remember { mutableStateOf(listOf<String>()) }
    var hopTags by remember { mutableStateOf(listOf<String>()) }
    var customFlavor by remember { mutableStateOf("") }
    var customHop by remember { mutableStateOf("") }
    var hidden by remember { mutableStateOf(item.hiddenFromPartner == true) }
    var busy by remember { mutableStateOf(false) }
    var removePhoto by remember { mutableStateOf(false) }
    var newPhoto by remember { mutableStateOf<File?>(null) }
    val context = LocalContext.current
    var pending by remember { mutableStateOf<File?>(null) }

    LaunchedEffect(Unit) {
        try {
            val fh = vm.api.flavors(item.style.orEmpty())
            flavorTags = (fh.suggestedFlavors ?: fh.flavors).orEmpty()
            hopTags = (fh.suggestedHops ?: fh.hops).orEmpty()
        } catch (_: Exception) {
        }
    }

    val takePic = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok && pending != null) {
            newPhoto = pending
            removePhoto = false
        }
        pending = null
    }

    SheetScaffold("Modifier la dégustation", onClose = { vm.closeSheet() }) {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "${item.brewery ?: "—"} · ${item.style ?: "?"} · ${formatDate(item.createdAt)}",
                color = BeerColors.muted,
                fontSize = 13.sp
            )
            BeerCard {
                UntappdRatingSlider(rating, { rating = it }, onTick = { vm.hapticTick() })
            }
            if (flavorTags.isNotEmpty()) {
                BeerCard {
                    FlavorTagGrid("Goûts", flavorTags, flavors, 8) {
                        flavors = if (it in flavors) flavors - it else flavors + it
                    }
                }
            }
            BeerCard {
                Text("Goûts perso", color = BeerColors.muted)
                CustomTagInput("…", customFlavor, { customFlavor = it }) {
                    val t = customFlavor.trim()
                    if (t.isNotBlank() && flavors.size < 8) {
                        flavors = flavors + t
                        customFlavor = ""
                    }
                }
            }
            if (hopTags.isNotEmpty()) {
                BeerCard {
                    FlavorTagGrid("Houblons", hopTags, hops, 6) {
                        hops = if (it in hops) hops - it else hops + it
                    }
                }
            }
            BeerCard {
                Text("Houblons perso", color = BeerColors.muted)
                CustomTagInput("…", customHop, { customHop = it }) {
                    val t = customHop.trim()
                    if (t.isNotBlank() && hops.size < 6) {
                        hops = hops + t
                        customHop = ""
                    }
                }
            }
            BeerField("Commentaire", comment, { if (it.length <= 300) comment = it })
            BeerField(
                label = "Lieu ou lien",
                value = location,
                onChange = { if (it.length <= 300) location = it },
                placeholder = "ex. Chez nous · https://maps…"
            )
            if (vm.isAdmin) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Masqué partenaire", color = BeerColors.text, modifier = Modifier.weight(1f))
                    Switch(checked = hidden, onCheckedChange = { hidden = it })
                }
            }
            BeerSecondaryButton("📷 Nouvelle photo") {
                try {
                    val dir = File(context.cacheDir, "beer").apply { mkdirs() }
                    val f = File(dir, "edit_${System.currentTimeMillis()}.jpg")
                    val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", f)
                    pending = f
                    takePic.launch(uri)
                } catch (e: Exception) {
                    vm.showToast(e.message ?: "Caméra", ToastPayload.Variant.ERROR)
                }
            }
            if (item.photoURL != null || newPhoto != null) {
                BeerSecondaryButton("Retirer la photo") {
                    removePhoto = true
                    newPhoto = null
                }
            }
            BeerPrimaryButton(if (busy) "Enregistrement…" else "Enregistrer", busy = busy) {
                scope.launch {
                    busy = true
                    try {
                        vm.api.updateCheckin(
                            id = item.id,
                            rating = rating.toDouble(),
                            flavors = flavors.toList(),
                            hops = hops.toList(),
                            comment = comment,
                            hiddenFromPartner = if (vm.isAdmin) hidden else null,
                            location = location.take(300)
                        )
                        if (removePhoto) {
                            try { vm.api.removeCheckinPhoto(item.id) } catch (_: Exception) {}
                        }
                        newPhoto?.let { f ->
                            val bytes = ImageUtils.compressJPEG(f.readBytes())
                            vm.api.replaceCheckinPhoto(item.id, bytes)
                        }
                        vm.showToast("Modifié ✓", ToastPayload.Variant.SUCCESS)
                        vm.closeSheet()
                    } catch (e: Exception) {
                        vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                    } finally {
                        busy = false
                    }
                }
            }
        }
    }
}

@Composable
private fun PatchnotesSheet(vm: AppViewModel) {
    var text by remember { mutableStateOf("Chargement…") }
    LaunchedEffect(Unit) {
        text = try {
            val p = vm.api.patchnotes()
            "v${p.version.orEmpty()}\n\n${p.markdown.orEmpty()}"
        } catch (e: Exception) {
            e.message ?: "Indisponible"
        }
    }
    SheetScaffold("Patch notes", onClose = { vm.closeSheet() }) {
        Text(text, color = BeerColors.text, fontSize = 13.sp, modifier = Modifier.verticalScroll(rememberScrollState()))
    }
}

/* Admin complet : AdminSheet.kt (parité iOS / webapp) */
