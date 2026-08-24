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



/** Lit le presse-papiers et ne garde qu'un lien/token d'invitation Beer valide (comme iOS). */
fun readInviteFromClipboard(context: Context): String? {
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


fun shortInvitePreview(raw: String): String {
    val t = InviteSessionStore.parseInviteToken(raw)
    return if (t != null && t.length >= 16) {
        "Token : ${t.take(10)}…${t.takeLast(6)}"
    } else {
        raw.take(48) + if (raw.length > 48) "…" else ""
    }
}


@Composable
fun LoginScreen(vm: AppViewModel) {
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
                        Text("https://beer.eiterlab.com/join/…", color = BeerColors.muted, fontSize = 12.sp)
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
