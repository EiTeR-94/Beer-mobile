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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
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
import kotlinx.coroutines.Job
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
fun MainScreen(vm: AppViewModel) {
    BackHandler(enabled = vm.sheet != null) { vm.closeSheet() }

    var showAccountMenu by remember { mutableStateOf(false) }
    var showLogoutConfirm by remember { mutableStateOf(false) }
    var showFeedback by remember { mutableStateOf(false) }
    val lifecycleOwner = LocalLifecycleOwner.current

    // Check maj APK + sync léger à chaque retour sur l'app
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                vm.onAppResumed()
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    LaunchedEffect(vm.requestOpenGrimoire) {
        if (vm.requestOpenGrimoire) {
            vm.consumeOpenGrimoireRequest()
            vm.refreshRpg()
            vm.openSheet(BeerSheet.GRIMOIRE)
        }
    }

    LaunchedEffect(vm.showTutorial) {
        if (vm.showTutorial) {
            vm.consumeShowTutorialRequest()
            vm.openSheet(BeerSheet.TUTORIAL)
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
                        // APK d’abord (version installée), webapp ensuite — parité iOS
                        Text(
                            buildString {
                                append("APK ${vm.appVersion}")
                                if (vm.serverVersion.isNotBlank()) {
                                    append(" · web ${vm.serverVersion}")
                                }
                            },
                            color = BeerColors.muted,
                            fontSize = 12.sp
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedButton(
                            onClick = { vm.refreshApp() },
                            enabled = !vm.isRefreshing,
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = BeerColors.text),
                            border = BorderStroke(1.dp, BeerColors.border),
                            shape = RoundedCornerShape(10.dp),
                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)
                        ) {
                            Text(
                                if (vm.isRefreshing) "…" else "MAJ",
                                fontWeight = FontWeight.Bold,
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
            BeerSheet.TUTORIAL -> TutorialSheet(vm)
            null -> {}
        }
    }
}


@Composable
fun AccountMenuOverlay(
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
                    Text(
                        buildString {
                            append("APK ${vm.appVersion}")
                            if (vm.serverVersion.isNotBlank()) {
                                append(" · web ${vm.serverVersion}")
                            }
                            vm.latestAndroidVersion?.let { latest ->
                                if (vm.needsAppUpdate) append(" · ⬆️ $latest dispo")
                            }
                        },
                        color = BeerColors.muted,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(top = 2.dp)
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

            AccountSection("Aide")
            AccountMenuItem("🎓 Tutoriel") { onOpen(BeerSheet.TUTORIAL) }

            AccountSection("Parler à l’admin")
            AccountMenuItem("💬 Un retour") { onFeedback() }

            if (vm.isAdmin) {
                AccountSection("Admin")
                AccountMenuItem("⚙️ Administration") { onOpen(BeerSheet.ADMIN) }
                // Toujours visible admin : même si Beerquest est coupé (pour le rallumer)
                AccountMenuItem("⚔ Beerquest") { onOpen(BeerSheet.RPG_ADMIN) }
                AccountMenuItem("📝 Patch notes") { onOpen(BeerSheet.PATCHNOTES) }
            }

            AccountSection("Application")
            AccountMenuItem(
                if (vm.isRefreshing) "Check MAJ…" else "Check MAJ"
            ) {
                vm.refreshApp()
                onDismiss()
            }
            if (vm.needsAppUpdate) {
                val ctx = LocalContext.current
                AccountMenuItem("⬆️ Installer maj APK ${vm.latestAndroidVersion ?: ""}") {
                    onDismiss()
                    try {
                        ctx.startActivity(
                            android.content.Intent(
                                android.content.Intent.ACTION_VIEW,
                                android.net.Uri.parse(ServerSettings.portalURL)
                            )
                        )
                    } catch (_: Exception) {
                    }
                }
            }

            AccountSection("Session")
            AccountMenuItem("Déconnexion", danger = true) { onLogout() }
        }
    }
}


@Composable
fun AccountSection(title: String) {
    Text(
        title,
        color = BeerColors.muted,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 6.dp, top = 10.dp, bottom = 4.dp)
    )
}


@Composable
fun AccountMenuItem(label: String, danger: Boolean = false, onClick: () -> Unit) {
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
fun AppUpdateBanner(current: String, latest: String, portalUrl: String) {
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
fun FeedbackReplyDialog(
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
fun FeedbackDialog(
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
