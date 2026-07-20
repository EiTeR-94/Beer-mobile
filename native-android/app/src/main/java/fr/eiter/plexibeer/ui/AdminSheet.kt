package fr.eiter.plexibeer.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Admin comptes / invités / outils — parité webapp + iOS.
 */
@Composable
fun AdminSheet(vm: AppViewModel) {
    var tab by remember { mutableIntStateOf(0) } // 0 comptes, 1 invités, 2 outils
    var users by remember { mutableStateOf<List<AdminUser>>(emptyList()) }
    var invites by remember { mutableStateOf<List<InviteItem>>(emptyList()) }
    var refs by remember { mutableStateOf(ReferentialsResponse()) }
    var feedbackUnread by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current

    // create user
    var newUser by remember { mutableStateOf("") }
    var newPass by remember { mutableStateOf("") }
    var newAdmin by remember { mutableStateOf(false) }

    // invite
    var invLabel by remember { mutableStateOf("") }
    var invEmail by remember { mutableStateOf("") }
    var invValidity by remember { mutableStateOf("7d") }
    var createdUrl by remember { mutableStateOf<String?>(null) }
    var invBusy by remember { mutableStateOf(false) }

    // referentials
    var refTab by remember { mutableIntStateOf(0) }
    var refFilter by remember { mutableStateOf("") }
    var refNew by remember { mutableStateOf("") }

    LaunchedEffect(reload) {
        loading = true
        error = null
        try {
            users = withContext(Dispatchers.IO) { vm.api.adminUsers() }
            invites = withContext(Dispatchers.IO) {
                try {
                    vm.api.adminInvites()
                } catch (_: Exception) {
                    emptyList()
                }
            }
            refs = withContext(Dispatchers.IO) {
                try {
                    vm.api.adminReferentials()
                } catch (_: Exception) {
                    ReferentialsResponse()
                }
            }
            feedbackUnread = withContext(Dispatchers.IO) {
                vm.api.adminFeedbackStats()?.unread ?: 0
            }
        } catch (e: Exception) {
            error = e.message ?: "Erreur chargement admin"
        }
        loading = false
    }

    fun toastOk(msg: String) = vm.showToast(msg, ToastPayload.Variant.SUCCESS)
    fun toastErr(msg: String) = vm.showToast(msg, ToastPayload.Variant.ERROR)

    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("⚙️ Administration", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                Text(
                    "${users.size} comptes · ${invites.count { it.active != false && it.revokedAt == null }} invités · 💬 $feedbackUnread",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
            }
            Text("↻", color = BeerColors.muted, modifier = Modifier.clickable { reload++ }.padding(8.dp))
            Text("Fermer ✕", color = BeerColors.muted, modifier = Modifier.clickable { vm.closeSheet() }.padding(8.dp))
        }
        Spacer(Modifier.height(8.dp))

        // Tabs parité web
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("Comptes", "Invités", "Outils").forEachIndexed { i, label ->
                val active = tab == i
                Box(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .border(
                            1.dp,
                            if (active) BeerColors.accent else BeerColors.border,
                            RoundedCornerShape(10.dp)
                        )
                        .background(if (active) BeerColors.card else BeerColors.card.copy(alpha = 0.55f))
                        .clickable { tab = i }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        label,
                        color = if (active) BeerColors.text else BeerColors.muted,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp
                    )
                }
            }
        }
        Spacer(Modifier.height(10.dp))

        if (loading) {
            Text("Chargement…", color = BeerColors.muted)
            return@Column
        }
        error?.let { Text(it, color = BeerColors.error, fontSize = 13.sp) }
        message?.let { Text(it, color = BeerColors.ok, fontSize = 13.sp) }

        val scroll = rememberScrollState()
        Column(Modifier.verticalScroll(scroll).weight(1f, fill = true)) {
            when (tab) {
                0 -> {
                    // ── Comptes ──
                    Text("Nouveau compte", color = BeerColors.muted, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = newUser,
                        onValueChange = { newUser = it },
                        label = { Text("Identifiant") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = newPass,
                        onValueChange = { newPass = it },
                        label = { Text("Mot de passe") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = newAdmin, onCheckedChange = { newAdmin = it })
                        Text("Administrateur", color = BeerColors.text, fontSize = 13.sp)
                    }
                    BeerPrimaryButton(
                        "Créer le compte",
                        enabled = newUser.isNotBlank() && newPass.length >= 6
                    ) {
                        scope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    vm.api.adminCreateUser(newUser.trim(), newPass, newAdmin)
                                }
                                newUser = ""; newPass = ""; newAdmin = false
                                message = "Compte créé"
                                reload++
                            } catch (e: Exception) {
                                toastErr(e.message ?: "Erreur")
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text("Comptes", color = BeerColors.muted, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(6.dp))
                    users.forEach { u ->
                        AdminUserCard(
                            user = u,
                            isSelf = u.username == vm.user,
                            onSetPassword = { pass ->
                                scope.launch {
                                    try {
                                        withContext(Dispatchers.IO) {
                                            vm.api.adminSetPassword(u.username, pass)
                                        }
                                        toastOk("Mot de passe mis à jour")
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            },
                            onToggleAdmin = {
                                scope.launch {
                                    try {
                                        withContext(Dispatchers.IO) {
                                            vm.api.adminSetAdmin(u.username, !u.isAdmin)
                                        }
                                        reload++
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            },
                            onDelete = {
                                scope.launch {
                                    try {
                                        withContext(Dispatchers.IO) {
                                            vm.api.adminDeleteUser(u.username)
                                        }
                                        reload++
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            }
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
                1 -> {
                    // ── Invités ──
                    Text("Invitations", color = BeerColors.muted, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Text(
                        "Lien + email. Lien 24 h si non utilisé. 1 appareil.",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = invLabel,
                        onValueChange = { invLabel = it },
                        label = { Text("Nom") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = invEmail,
                        onValueChange = { invEmail = it },
                        label = { Text("Email") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    Spacer(Modifier.height(6.dp))
                    // Validité simple
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("24h" to "24h", "7d" to "7j", "30d" to "30j", "permanent" to "Perm.").forEach { (v, lab) ->
                            val on = invValidity == v
                            Text(
                                lab,
                                color = if (on) Color.Black else BeerColors.text,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (on) BeerColors.accent else BeerColors.card)
                                    .border(1.dp, if (on) BeerColors.accent else BeerColors.border, RoundedCornerShape(8.dp))
                                    .clickable { invValidity = v }
                                    .padding(horizontal = 10.dp, vertical = 7.dp)
                            )
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    BeerPrimaryButton(
                        if (invBusy) "Génération…" else "Créer le lien",
                        enabled = invLabel.length >= 2 && invEmail.contains("@") && !invBusy
                    ) {
                        invBusy = true
                        scope.launch {
                            try {
                                val res = withContext(Dispatchers.IO) {
                                    vm.api.adminCreateInvite(invLabel.trim(), invEmail.trim(), invValidity)
                                }
                                createdUrl = res.url
                                invLabel = ""; invEmail = ""
                                toastOk("Lien créé — copie-le")
                                reload++
                            } catch (e: Exception) {
                                toastErr(e.message ?: "Erreur")
                            }
                            invBusy = false
                        }
                    }
                    createdUrl?.let { url ->
                        Spacer(Modifier.height(8.dp))
                        Text(url, color = BeerColors.text, fontSize = 11.sp)
                        BeerSecondaryButton("Copier le lien") {
                            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cm.setPrimaryClip(ClipData.newPlainText("invite", url))
                            createdUrl = null
                            toastOk("Lien copié")
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    invites.forEach { inv ->
                        InviteCard(
                            inv = inv,
                            onCopy = { url ->
                                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                cm.setPrimaryClip(ClipData.newPlainText("invite", url))
                                toastOk("Lien copié")
                            },
                            onExtend = { v ->
                                scope.launch {
                                    try {
                                        withContext(Dispatchers.IO) { vm.api.adminExtendInvite(inv.id, v) }
                                        toastOk("Prolongé")
                                        reload++
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            },
                            onReissue = {
                                scope.launch {
                                    try {
                                        val url = withContext(Dispatchers.IO) { vm.api.adminReissueInvite(inv.id) }
                                        createdUrl = url
                                        toastOk("Lien réactivation prêt")
                                        reload++
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            },
                            onRevoke = {
                                scope.launch {
                                    try {
                                        withContext(Dispatchers.IO) { vm.api.adminRevokeInvite(inv.id) }
                                        toastOk("Révoquée")
                                        reload++
                                    } catch (e: Exception) {
                                        toastErr(e.message ?: "Erreur")
                                    }
                                }
                            }
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
                else -> {
                    // ── Outils ──
                    BeerPrimaryButton("⚔ Admin Beerquest") {
                        vm.openSheet(BeerSheet.RPG_ADMIN)
                    }
                    Spacer(Modifier.height(8.dp))
                    BeerSecondaryButton("🧹 Nettoyer photos orphelines") {
                        scope.launch {
                            try {
                                val msg = withContext(Dispatchers.IO) { vm.api.adminCleanupPhotos() }
                                message = msg
                                toastOk(msg)
                            } catch (e: Exception) {
                                toastErr(e.message ?: "Erreur")
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text("Référentiels", color = BeerColors.muted, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("Styles", "Houblons", "Goûts").forEachIndexed { i, lab ->
                            val on = refTab == i
                            Text(
                                lab,
                                color = if (on) Color.Black else BeerColors.text,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (on) BeerColors.accent else BeerColors.card)
                                    .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                                    .clickable { refTab = i }
                                    .padding(horizontal = 10.dp, vertical = 7.dp)
                            )
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = refFilter,
                        onValueChange = { refFilter = it },
                        label = { Text("Filtrer") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    Spacer(Modifier.height(6.dp))
                    OutlinedTextField(
                        value = refNew,
                        onValueChange = { refNew = it },
                        label = { Text("Nouveau nom") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = adminFieldColors()
                    )
                    BeerSecondaryButton("Ajouter", enabled = refNew.trim().length >= 2) {
                        scope.launch {
                            try {
                                val n = refNew.trim()
                                withContext(Dispatchers.IO) {
                                    when (refTab) {
                                        1 -> vm.api.adminAddHop(n)
                                        2 -> vm.api.adminAddFlavor(n)
                                        else -> vm.api.adminAddStyle(n)
                                    }
                                }
                                refNew = ""
                                reload++
                            } catch (e: Exception) {
                                toastErr(e.message ?: "Erreur")
                            }
                        }
                    }
                    val list = when (refTab) {
                        1 -> refs.hops.orEmpty()
                        2 -> refs.flavors.orEmpty()
                        else -> refs.styles.orEmpty()
                    }.filter {
                        refFilter.isBlank() || it.name.contains(refFilter, ignoreCase = true)
                    }
                    Spacer(Modifier.height(8.dp))
                    list.forEach { entry ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(entry.name, color = BeerColors.text, fontSize = 13.sp)
                            if (entry.deletable != false && entry.preset != true) {
                                Text(
                                    "Suppr",
                                    color = BeerColors.error,
                                    fontSize = 12.sp,
                                    modifier = Modifier.clickable {
                                        scope.launch {
                                            try {
                                                withContext(Dispatchers.IO) {
                                                    when (refTab) {
                                                        1 -> vm.api.adminDeleteHop(entry.name)
                                                        2 -> vm.api.adminDeleteFlavor(entry.name)
                                                        else -> vm.api.adminDeleteStyle(entry.name)
                                                    }
                                                }
                                                reload++
                                            } catch (e: Exception) {
                                                toastErr(e.message ?: "Erreur")
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun adminFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = BeerColors.text,
    unfocusedTextColor = BeerColors.text,
    focusedBorderColor = BeerColors.accent,
    unfocusedBorderColor = BeerColors.border,
    focusedLabelColor = BeerColors.muted,
    unfocusedLabelColor = BeerColors.muted,
    cursorColor = BeerColors.accent,
)

@Composable
private fun AdminUserCard(
    user: AdminUser,
    isSelf: Boolean,
    onSetPassword: (String) -> Unit,
    onToggleAdmin: () -> Unit,
    onDelete: () -> Unit,
) {
    var pass by remember { mutableStateOf("") }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, if (user.isAdmin) BeerColors.accent.copy(alpha = 0.4f) else BeerColors.border, RoundedCornerShape(12.dp))
            .background(BeerColors.card)
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(user.username, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            if (user.isAdmin) {
                Spacer(Modifier.width(6.dp))
                Text(
                    "admin",
                    color = Color.Black,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(BeerColors.accent)
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
            if (isSelf) {
                Spacer(Modifier.width(6.dp))
                Text("toi", color = BeerColors.muted, fontSize = 10.sp)
            }
        }
        Text(
            "🍺 ${user.checkins} · 📷 ${user.photos ?: 0}",
            color = BeerColors.muted,
            fontSize = 11.sp
        )
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(
            value = pass,
            onValueChange = { pass = it },
            label = { Text("Nouveau mot de passe") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = adminFieldColors()
        )
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                "MDP",
                color = BeerColors.text,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                    .clickable(enabled = pass.length >= 6) {
                        onSetPassword(pass)
                        pass = ""
                    }
                    .padding(horizontal = 10.dp, vertical = 7.dp)
            )
            if (!isSelf) {
                Text(
                    if (user.isAdmin) "Retirer admin" else "Promouvoir",
                    color = BeerColors.text,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                        .clickable { onToggleAdmin() }
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                )
                Text(
                    "Suppr.",
                    color = BeerColors.error,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, BeerColors.error.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                        .clickable { onDelete() }
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                )
            }
        }
    }
}

@Composable
private fun InviteCard(
    inv: InviteItem,
    onCopy: (String) -> Unit,
    onExtend: (String) -> Unit,
    onReissue: () -> Unit,
    onRevoke: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(12.dp))
            .background(BeerColors.card)
            .padding(12.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(inv.label ?: "—", color = BeerColors.text, fontWeight = FontWeight.Bold)
            Text(
                inv.statusText,
                color = BeerColors.accent,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Text(
            "${inv.username ?: "—"} · ${inv.checkins ?: 0} dégust.",
            color = BeerColors.muted,
            fontSize = 12.sp
        )
        inv.emailHint?.let {
            Text("Email $it", color = BeerColors.muted, fontSize = 11.sp)
        }
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (!inv.url.isNullOrBlank() && inv.revokedAt == null && inv.linkActive != false) {
                SmallAction("Copier") { onCopy(inv.url!!) }
            }
            if (inv.canExtend == true) {
                SmallAction("+7j") { onExtend("7d") }
                SmallAction("Perm.") { onExtend("permanent") }
            }
            if (inv.canReissue == true || inv.reactivationPending == true) {
                SmallAction("Renvoyer") { onReissue() }
            }
            if (inv.revokedAt == null) {
                SmallAction("Révoquer", danger = true) { onRevoke() }
            }
        }
    }
}

@Composable
private fun SmallAction(label: String, danger: Boolean = false, onClick: () -> Unit) {
    Text(
        label,
        color = if (danger) BeerColors.error else BeerColors.text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .border(
                1.dp,
                if (danger) BeerColors.error.copy(alpha = 0.5f) else BeerColors.border,
                RoundedCornerShape(8.dp)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp)
    )
}
