package fr.eiter.plexibeer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import fr.eiter.plexibeer.AdminFeedbackItem
import fr.eiter.plexibeer.AdminFeedbackStats
import fr.eiter.plexibeer.AppViewModel
import fr.eiter.plexibeer.RpgAdminFlags
import fr.eiter.plexibeer.RpgAdminPlayer
import fr.eiter.plexibeer.RpgAdminPlayerDetail
import fr.eiter.plexibeer.RpgAdminPlayersResponse
import fr.eiter.plexibeer.RpgBadge
import fr.eiter.plexibeer.RpgCelebration
import fr.eiter.plexibeer.RpgClassInfo
import fr.eiter.plexibeer.RpgLoot
import fr.eiter.plexibeer.RpgProfile
import fr.eiter.plexibeer.RpgQuest
import fr.eiter.plexibeer.RpgState
import fr.eiter.plexibeer.ToastPayload
import fr.eiter.plexibeer.displayIcon
import fr.eiter.plexibeer.rarityLabelFr
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


@Composable
fun RpgAdminSheet(vm: AppViewModel) {
    // 0 Joueurs · 1 Contrôle · 2 Feedback
    var tab by remember { mutableIntStateOf(1) }
    var players by remember { mutableStateOf<List<RpgAdminPlayer>>(emptyList()) }
    var rpgFlags by remember { mutableStateOf<RpgAdminFlags?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<RpgAdminPlayer?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var reloadToken by remember { mutableIntStateOf(0) }
    var didPickInitialTab by remember { mutableStateOf(false) }

    // Feedback admin
    var fbItems by remember { mutableStateOf<List<AdminFeedbackItem>>(emptyList()) }
    var fbStats by remember { mutableStateOf<AdminFeedbackStats?>(null) }
    var fbUnreadOnly by remember { mutableStateOf(false) }
    var fbStatus by remember { mutableStateOf("") }
    var fbLoading by remember { mutableStateOf(false) }
    var resolveId by remember { mutableStateOf<Int?>(null) }
    var resolveStatus by remember { mutableStateOf("done") }
    var resolveReply by remember { mutableStateOf("") }
    var showResolve by remember { mutableStateOf(false) }

    fun reload() { reloadToken++ }

    fun patchFlag(key: String, value: Boolean) {
        scope.launch {
            busy = true
            val payload = mutableMapOf<String, Any?>(key to value)
            // Allumer Beerquest = moteur + UI (évite ON invisible)
            if (key == "enabled" && value) payload["ui"] = true
            val next = withContext(Dispatchers.IO) {
                vm.api.adminRpgPatchSettings(payload)
            }
            if (next != null) {
                rpgFlags = next
                val msg = when {
                    key == "enabled" && value -> "Beerquest allumé"
                    key == "enabled" -> "Beerquest coupé"
                    key == "allow_invites" && value -> "Invités inclus"
                    key == "allow_invites" -> "Invités exclus"
                    else -> "Réglage enregistré"
                }
                vm.showToast(msg, ToastPayload.Variant.SUCCESS)
                reload()
            } else {
                vm.showToast("Échec réglages", ToastPayload.Variant.ERROR)
            }
            busy = false
        }
    }

    LaunchedEffect(reloadToken) {
        loading = true
        error = null
        val bundle = withContext(Dispatchers.IO) {
            try { vm.api.adminRpgPlayersBundle() } catch (_: Exception) { RpgAdminPlayersResponse() }
        }
        players = bundle.players
        rpgFlags = bundle.flags
        if (players.isEmpty() && bundle.flags == null) error = "Aucun joueur ou accès refusé."
        if (!didPickInitialTab) {
            didPickInitialTab = true
            tab = if (bundle.flags?.enabled == true) 0 else 1
        }
        loading = false
    }

    LaunchedEffect(tab, fbUnreadOnly, fbStatus, reloadToken) {
        if (tab != 2) return@LaunchedEffect
        fbLoading = true
        try {
            val res = withContext(Dispatchers.IO) {
                vm.api.adminFeedbackList(
                    limit = 80,
                    unreadOnly = fbUnreadOnly,
                    status = fbStatus.ifBlank { null }
                )
            }
            fbItems = res.items.orEmpty()
            fbStats = res.stats
        } catch (e: Exception) {
            error = e.message
        }
        fbLoading = false
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .consumeClicks()
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("⚔ Admin Beerquest", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                val unread = fbStats?.unread ?: 0
                val f = rpgFlags
                val status = when {
                    f == null -> "${players.size} joueur(s)"
                    f.enabled -> "Beerquest ON · ${players.size} joueur(s)"
                    else -> "Beerquest OFF · ${players.size} joueur(s)"
                }
                Text(
                    if (unread > 0) "$status · $unread feedback" else status,
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
            }
            Text("↻", color = QuestBlue, modifier = Modifier.clickable { reload() }.padding(8.dp))
            Text("Fermer ✕", color = BeerColors.muted, modifier = Modifier.clickable { vm.closeSheet() }.padding(8.dp))
        }
        Spacer(Modifier.height(8.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("Joueurs", "Contrôle", "Feedback").forEachIndexed { i, lab ->
                val active = tab == i
                val badge = if (i == 2 && (fbStats?.unread ?: 0) > 0) " ${(fbStats?.unread)}" else ""
                Box(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .border(1.dp, if (active) Gold else BeerColors.border, RoundedCornerShape(10.dp))
                        .background(if (active) BeerColors.card else BeerColors.card.copy(alpha = 0.55f))
                        .clickable { tab = i }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        lab + badge,
                        color = if (active) BeerColors.text else BeerColors.muted,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp
                    )
                }
            }
        }
        Spacer(Modifier.height(10.dp))

        when {
            tab == 0 && loading -> Text("Chargement…", color = BeerColors.muted)
            tab == 0 && error != null && players.isEmpty() -> Text(error!!, color = BeerColors.muted)
            tab == 0 -> {
                val scroll = rememberScrollState()
                Column(Modifier.verticalScroll(scroll).weight(1f, fill = true)) {
                    players.forEach { p ->
                        val name = p.username ?: "—"
                        val dayCap = p.dailySoftCap
                        val dayXp = p.dailyXpToday
                        val dayCk = p.dailyCheckinsToday
                        val borderC = when {
                            p.quarantined == true -> BeerColors.error.copy(alpha = 0.6f)
                            p.dailySoftCapped -> Gold.copy(alpha = 0.55f)
                            else -> BeerColors.border
                        }
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(bottom = 8.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .border(1.dp, borderC, RoundedCornerShape(12.dp))
                                .background(BeerColors.card)
                                .clickable {
                                    selected = p
                                }
                                .padding(12.dp)
                        ) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Column(Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(name, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                        if (p.quarantined == true) {
                                            Spacer(Modifier.width(6.dp))
                                            Text(
                                                "⛔ quarantaine",
                                                color = BeerColors.error,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(999.dp))
                                                    .background(BeerColors.error.copy(alpha = 0.16f))
                                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                        if (p.tutorialSeen == false) {
                                            Spacer(Modifier.width(6.dp))
                                            Text(
                                                "🎓 reverra le tuto",
                                                color = Gold,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(999.dp))
                                                    .background(Gold.copy(alpha = 0.16f))
                                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                    p.title?.let {
                                        Text(it, color = BeerColors.muted, fontSize = 11.sp)
                                    }
                                }
                                Text("Nv ${p.level}", color = Gold, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            }
                            Text(
                                buildString {
                                    append("${p.xp} XP · ${p.checkins} check-ins · ${p.badgeCount} badges")
                                    if (p.isInvite) append(" · invité")
                                    if (p.beerMaster) append(" · Master")
                                    if (p.allowed) append(" · RPG OK") else append(" · RPG bloqué")
                                    when (p.allowedOverride) {
                                        true -> append(" (forcé ON)")
                                        false -> append(" (forcé OFF)")
                                        null -> {}
                                    }
                                },
                                color = BeerColors.muted,
                                fontSize = 12.sp
                            )
                            if (dayCap > 0) {
                                Text(
                                    buildString {
                                        if (p.dailySoftCapped) append("⛔ ") else append("⚡ ")
                                        append("$dayXp/$dayCap XP jour · $dayCk check-in")
                                        if (dayCk != 1) append("s")
                                        append(" RPG")
                                        if (p.dailySoftCapped) append(" · plafond")
                                    },
                                    color = if (p.dailySoftCapped) Gold else QuestBlue,
                                    fontSize = 11.sp,
                                    fontWeight = if (p.dailySoftCapped) FontWeight.Bold else FontWeight.Normal
                                )
                            }
                            // ON/OFF/Auto : dans le détail joueur (tap carte)
                        }
                    }
                }
            }
            tab == 1 -> {
                // Kill-switches clairs
                val f = rpgFlags
                val gameOn = f?.enabled == true
                val invOn = f?.allowInvites == true
                val scroll = rememberScrollState()
                Column(Modifier.verticalScroll(scroll).weight(1f, fill = true)) {
                    Text("Interrupteurs serveur", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    Text(
                        "Sans rebuild · admin · Wi‑Fi / VPN maison",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(10.dp))
                    // Beerquest global
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .border(
                                1.dp,
                                if (gameOn) Color(0xFF81C784).copy(alpha = 0.5f) else Color(0xFFE57373).copy(alpha = 0.5f),
                                RoundedCornerShape(12.dp)
                            )
                            .background(BeerColors.card)
                            .padding(12.dp)
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    "Beerquest (tout le monde)",
                                    color = BeerColors.text,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 14.sp
                                )
                                Text(
                                    if (gameOn)
                                        "Le jeu est actif : XP, quêtes, grimoire pour les joueurs autorisés."
                                    else
                                        "Le jeu est coupé : plus d’XP ni de grimoire. Le carnet reste.",
                                    color = BeerColors.muted,
                                    fontSize = 12.sp
                                )
                            }
                            Switch(
                                checked = gameOn,
                                onCheckedChange = { if (!busy) patchFlag("enabled", it) },
                                enabled = !busy,
                                colors = SwitchDefaults.colors(
                                    checkedTrackColor = Color(0xFF81C784).copy(alpha = 0.7f)
                                )
                            )
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .border(1.dp, BeerColors.border, RoundedCornerShape(12.dp))
                            .background(BeerColors.card)
                            .padding(12.dp)
                            .alpha(if (gameOn) 1f else 0.55f)
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    "Inclure les invités",
                                    color = BeerColors.text,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 14.sp
                                )
                                Text(
                                    if (invOn)
                                        "Les comptes invite_* peuvent aussi jouer."
                                    else
                                        "Les invités n’ont que le carnet (pas de jeu).",
                                    color = BeerColors.muted,
                                    fontSize = 12.sp
                                )
                            }
                            Switch(
                                checked = invOn,
                                onCheckedChange = { if (!busy) patchFlag("allow_invites", it) },
                                enabled = !busy && gameOn,
                                colors = SwitchDefaults.colors(checkedTrackColor = Gold.copy(alpha = 0.7f))
                            )
                        }
                    }
                    if (!gameOn) {
                        Spacer(Modifier.height(10.dp))
                        Text(
                            "Beerquest est OFF — cet onglet sert à le rallumer. Le menu ⚔ reste toujours visible pour l’admin.",
                            color = Gold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(
                        "Par joueur : onglet Joueurs → fiche → ON / OFF / Auto.",
                        color = BeerColors.muted,
                        fontSize = 11.sp
                    )
                }
            }
            tab == 2 -> {
                // Feedback toolbar
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = fbUnreadOnly, onCheckedChange = { fbUnreadOnly = it })
                    Text("Non lus seulement", color = BeerColors.text, fontSize = 13.sp)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("" to "Tous", "open" to "En cours", "done" to "Faits", "rejected" to "Refusés").forEach { (v, lab) ->
                        val on = fbStatus == v
                        Text(
                            lab,
                            color = if (on) Color.Black else BeerColors.text,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (on) BeerColors.accent else BeerColors.card)
                                .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                                .clickable { fbStatus = v }
                                .padding(horizontal = 8.dp, vertical = 6.dp)
                        )
                    }
                }
                val s = fbStats
                Text(
                    "${s?.unread ?: 0} non lu(s) · ${s?.open ?: 0} en cours · ${s?.done ?: 0} faits · ${s?.rejected ?: 0} refusés",
                    color = BeerColors.muted,
                    fontSize = 11.sp,
                    modifier = Modifier.padding(vertical = 6.dp)
                )
                if (fbLoading) {
                    Text("Chargement feedback…", color = BeerColors.muted)
                } else if (fbItems.isEmpty()) {
                    Text("Aucun feedback.", color = BeerColors.muted)
                } else {
                    val scroll = rememberScrollState()
                    Column(Modifier.verticalScroll(scroll).weight(1f, fill = true)) {
                        fbItems.forEach { f ->
                            FeedbackAdminCard(
                                f = f,
                                busy = busy,
                                onToggleRead = {
                                    scope.launch {
                                        busy = true
                                        try {
                                            withContext(Dispatchers.IO) {
                                                vm.api.adminFeedbackMarkRead(f.id!!, f.adminRead != true)
                                            }
                                            reload()
                                        } catch (e: Exception) {
                                            vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                        }
                                        busy = false
                                    }
                                },
                                onDone = {
                                    resolveId = f.id
                                    resolveStatus = "done"
                                    resolveReply = ""
                                    showResolve = true
                                },
                                onReject = {
                                    resolveId = f.id
                                    resolveStatus = "rejected"
                                    resolveReply = ""
                                    showResolve = true
                                },
                                onReopen = {
                                    scope.launch {
                                        busy = true
                                        try {
                                            withContext(Dispatchers.IO) { vm.api.adminFeedbackReopen(f.id!!) }
                                            reload()
                                            vm.showToast("Rouvert", ToastPayload.Variant.SUCCESS)
                                        } catch (e: Exception) {
                                            vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                        }
                                        busy = false
                                    }
                                },
                                onDelete = {
                                    scope.launch {
                                        busy = true
                                        try {
                                            withContext(Dispatchers.IO) { vm.api.adminFeedbackDelete(f.id!!) }
                                            reload()
                                            vm.showToast("Supprimé", ToastPayload.Variant.SUCCESS)
                                        } catch (e: Exception) {
                                            vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                        }
                                        busy = false
                                    }
                                }
                            )
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                }
            }
        }
    }

    // Resolve dialog
    if (showResolve && resolveId != null) {
        AlertDialog(
            onDismissRequest = { showResolve = false },
            title = {
                Text(
                    if (resolveStatus == "rejected") "Refuser" else "Mis en place",
                    color = BeerColors.text,
                    fontWeight = FontWeight.Bold
                )
            },
            text = {
                Column {
                    Text(
                        if (resolveStatus == "rejected") "Raison obligatoire (visible par le joueur)"
                        else "Message optionnel pour le joueur",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = resolveReply,
                        onValueChange = { resolveReply = it },
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = BeerColors.text,
                            unfocusedTextColor = BeerColors.text,
                            focusedBorderColor = BeerColors.accent,
                            unfocusedBorderColor = BeerColors.border
                        )
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val id = resolveId ?: return@TextButton
                        if (resolveStatus == "rejected" && resolveReply.trim().length < 3) {
                            vm.showToast("Raison trop courte", ToastPayload.Variant.ERROR)
                            return@TextButton
                        }
                        busy = true
                        scope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    vm.api.adminFeedbackResolve(id, resolveStatus, resolveReply.trim())
                                }
                                showResolve = false
                                reload()
                                vm.showToast(
                                    if (resolveStatus == "rejected") "Refusé — joueur notifié"
                                    else "Fait — joueur notifié",
                                    ToastPayload.Variant.SUCCESS
                                )
                            } catch (e: Exception) {
                                vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                            }
                            busy = false
                        }
                    }
                ) { Text("Envoyer", color = BeerColors.accent) }
            },
            dismissButton = {
                TextButton(onClick = { showResolve = false }) {
                    Text("Annuler", color = BeerColors.muted)
                }
            },
            containerColor = BeerColors.card
        )
    }

    selected?.let { p ->
        RpgPlayerDetailSheet(
            vm = vm,
            username = p.username.orEmpty(),
            initialLevel = p.level,
            onClose = { selected = null },
            onChanged = { reload() }
        )
    }
}

/**
 * Fiche joueur admin — détail complet (GET /api/admin/rpg/players/{user}) : profil, accès RPG,
 * quarantaine anti-triche, badges (donner/retirer), quêtes/événements récents, effacement RPG.
 */
@Composable
fun RpgPlayerDetailSheet(
    vm: AppViewModel,
    username: String,
    initialLevel: Int,
    onClose: () -> Unit,
    onChanged: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var detail by remember(username) { mutableStateOf<RpgAdminPlayerDetail?>(null) }
    var detailLoading by remember(username) { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var levelText by remember(username) { mutableStateOf(initialLevel.toString()) }
    var badgeFilter by remember { mutableStateOf("all") }
    var confirmWipe by remember { mutableStateOf(false) }
    var confirmRevoke by remember { mutableStateOf<RpgBadge?>(null) }

    suspend fun refresh() {
        detail = try { vm.api.adminRpgPlayer(username) } catch (_: Exception) { detail }
    }

    LaunchedEffect(username) {
        detailLoading = true
        refresh()
        detailLoading = false
    }

    fun applyDetail(d: RpgAdminPlayerDetail?) {
        if (d != null) detail = d
        onChanged()
    }

    val p = detail?.player
    val name = username

    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .consumeClicks()
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                "⚔ $name",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp,
                modifier = Modifier.weight(1f)
            )
            Text("Fermer ✕", color = BeerColors.muted, modifier = Modifier.clickable { onClose() }.padding(8.dp))
        }
        Spacer(Modifier.height(8.dp))

        if (detailLoading && detail == null) {
            Text("Chargement…", color = BeerColors.muted)
            return@Column
        }

        val scroll = rememberScrollState()
        Column(Modifier.verticalScroll(scroll).weight(1f, fill = true)) {
            Text(
                "Nv ${p?.level ?: initialLevel} · ${p?.xp ?: 0} XP · ${detail?.badges?.count { it.earned } ?: 0}/${detail?.badges?.size ?: 0} badges",
                color = BeerColors.muted,
                fontSize = 13.sp
            )
            p?.title?.let { Text(it, color = BeerColors.muted, fontSize = 12.sp) }

            // ── Quarantaine anti-triche ──
            if (p?.quarantined == true) {
                Spacer(Modifier.height(10.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .border(1.dp, BeerColors.error.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                        .background(BeerColors.error.copy(alpha = 0.08f))
                        .padding(10.dp)
                ) {
                    Text("⛔ Quarantaine anti-triche", color = BeerColors.error, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        p.quarantineReason ?: "Raison non précisée",
                        color = BeerColors.text,
                        fontSize = 12.sp
                    )
                    Text(
                        buildString {
                            append("Déclenchée le ${formatDate(p.quarantineAt)}")
                            p.quarantineSuspicion?.let { append(" · suspicion $it/100") }
                        },
                        color = BeerColors.muted,
                        fontSize = 11.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = {
                            busy = true
                            scope.launch {
                                val d = withContext(Dispatchers.IO) {
                                    try { vm.api.adminRpgUnquarantine(name) } catch (_: Exception) { null }
                                }
                                busy = false
                                if (d != null) {
                                    applyDetail(d)
                                    vm.showToast("Quarantaine levée pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                                } else {
                                    vm.showToast("Échec levée quarantaine", ToastPayload.Variant.ERROR)
                                }
                            }
                        },
                        enabled = !busy,
                        colors = ButtonDefaults.buttonColors(containerColor = BeerColors.error)
                    ) {
                        Text("Lever quarantaine", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            } else if ((p?.suspicionScore ?: 0) > 0) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Suspicion anti-triche : ${p?.suspicionScore}/100",
                    color = Gold,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(Modifier.height(10.dp))
            Text("Accès RPG", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf<Pair<String, Boolean?>>(
                    "ON" to true,
                    "OFF" to false,
                    "Auto" to null,
                ).forEach { (lab, value) ->
                    val active = when (value) {
                        true -> p?.allowedOverride == true
                        false -> p?.allowedOverride == false
                        null -> p?.allowedOverride == null
                    }
                    Text(
                        lab,
                        color = if (active) Color.Black else BeerColors.text,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(
                                when {
                                    active && value == true -> Color(0xFF81C784)
                                    active && value == false -> Color(0xFFE57373)
                                    active -> Gold
                                    else -> BeerColors.card
                                }
                            )
                            .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                            .clickable(enabled = !busy) {
                                scope.launch {
                                    busy = true
                                    val d = withContext(Dispatchers.IO) {
                                        try { vm.api.adminRpgSetUserAllowed(name, value) } catch (_: Exception) { null }
                                    }
                                    if (d != null) {
                                        vm.showToast("$name · RPG $lab", ToastPayload.Variant.SUCCESS)
                                        applyDetail(d)
                                    } else {
                                        vm.showToast("Échec accès", ToastPayload.Variant.ERROR)
                                    }
                                    busy = false
                                }
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            Text("Niveau (parité iOS)", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            OutlinedTextField(
                value = levelText,
                onValueChange = { levelText = it.filter { c -> c.isDigit() }.take(3) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = BeerColors.text,
                    unfocusedTextColor = BeerColors.text,
                    focusedBorderColor = BeerColors.accent,
                    unfocusedBorderColor = BeerColors.border
                )
            )
            TextButton(
                onClick = {
                    val lv = levelText.toIntOrNull()
                    if (lv == null || lv < 1) {
                        vm.showToast("Niveau invalide", ToastPayload.Variant.ERROR)
                        return@TextButton
                    }
                    busy = true
                    scope.launch {
                        val d = withContext(Dispatchers.IO) {
                            try { vm.api.adminRpgPatchPlayer(name, mapOf("level" to lv)) } catch (_: Exception) { null }
                        }
                        busy = false
                        if (d != null) {
                            vm.showToast("Niveau $lv pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                            applyDetail(d)
                        } else {
                            vm.showToast("Échec niveau", ToastPayload.Variant.ERROR)
                        }
                    }
                },
                enabled = !busy
            ) { Text("Appliquer niveau", color = BeerColors.accent) }

            Spacer(Modifier.height(8.dp))
            Text("Ajuster l’XP", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(-50, -10, 10, 50).forEach { d0 ->
                    OutlinedButton(
                        onClick = {
                            busy = true
                            scope.launch {
                                val d = withContext(Dispatchers.IO) {
                                    try { vm.api.adminRpgAdjustXp(name, d0) } catch (_: Exception) { null }
                                }
                                busy = false
                                if (d != null) {
                                    vm.showToast("XP ${if (d0 > 0) "+" else ""}$d0 pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                                    applyDetail(d)
                                } else {
                                    vm.showToast("Échec XP", ToastPayload.Variant.ERROR)
                                }
                            }
                        },
                        enabled = !busy && name.isNotBlank()
                    ) {
                        Text(if (d0 > 0) "+$d0" else "$d0", color = BeerColors.text, fontSize = 12.sp)
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        val d = withContext(Dispatchers.IO) {
                            try { vm.api.adminRpgResetDaily(name) } catch (_: Exception) { null }
                        }
                        busy = false
                        if (d != null) {
                            vm.showToast("Reset journalier $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                            applyDetail(d)
                        } else {
                            vm.showToast("Échec reset", ToastPayload.Variant.ERROR)
                        }
                    }
                },
                enabled = !busy && name.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)
            ) {
                Text("Reset XP du jour", color = Color.Black, fontWeight = FontWeight.Bold)
            }

            Spacer(Modifier.height(8.dp))
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        val d = withContext(Dispatchers.IO) {
                            try { vm.api.adminRpgPatchPlayer(name, mapOf("tutorial_seen" to false)) } catch (_: Exception) { null }
                        }
                        busy = false
                        if (d != null) {
                            vm.showToast("$name reverra le tutoriel à sa prochaine connexion.", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                            applyDetail(d)
                        } else {
                            vm.showToast("Échec tuto", ToastPayload.Variant.ERROR)
                        }
                    }
                },
                enabled = !busy && name.isNotBlank() && p?.tutorialSeen != false,
                colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)
            ) {
                Text(
                    if (p?.tutorialSeen == false) "🎓 Reverra le tuto" else "🎓 Forcer à revoir le tuto",
                    color = Color.Black,
                    fontWeight = FontWeight.Bold
                )
            }

            // ── Badges : donner / retirer ──
            Spacer(Modifier.height(14.dp))
            val badges = detail?.badges.orEmpty()
            val earnedCount = badges.count { it.earned }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("🏅 Salle des trophées", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Text("$earnedCount/${badges.size}", color = Gold, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("all" to "Tous", "earned" to "Obtenus", "locked" to "À donner").forEach { (key, lab) ->
                    val on = badgeFilter == key
                    Text(
                        lab,
                        color = if (on) Color.Black else BeerColors.muted,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (on) Gold else BeerColors.card)
                            .border(1.dp, if (on) Gold else BeerColors.border, RoundedCornerShape(999.dp))
                            .clickable { badgeFilter = key }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            val shownBadges = when (badgeFilter) {
                "earned" -> badges.filter { it.earned }
                "locked" -> badges.filter { !it.earned }
                else -> badges
            }
            if (shownBadges.isEmpty()) {
                Text("Aucun badge dans ce filtre.", color = BeerColors.muted, fontSize = 12.sp)
            } else {
                val rows = shownBadges.chunked(2)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    rows.forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { b ->
                                Box(Modifier.weight(1f)) {
                                    AdminBadgeTile(
                                        b = b,
                                        busy = busy,
                                        onTap = {
                                            if (b.earned) {
                                                confirmRevoke = b
                                            } else {
                                                scope.launch {
                                                    busy = true
                                                    val res = withContext(Dispatchers.IO) {
                                                        try { vm.api.adminRpgGrantBadge(name, b.key.orEmpty()) } catch (_: Exception) { null }
                                                    }
                                                    busy = false
                                                    if (res?.granted == true) {
                                                        vm.showToast("Badge accordé", ToastPayload.Variant.SUCCESS, label = "🏅 ${b.name}")
                                                        applyDetail(res.player)
                                                    } else {
                                                        vm.showToast("Échec badge", ToastPayload.Variant.ERROR)
                                                    }
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                            if (row.size < 2) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }

            // ── Quêtes récentes ──
            val quests = detail?.quests.orEmpty()
            if (quests.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                Text("📜 Quêtes", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.height(6.dp))
                quests.take(10).forEach { q ->
                    Text(
                        "• ${q.title ?: q.key ?: "—"} · ${q.progress ?: 0}/${q.target ?: 1} · ${q.status ?: "?"}",
                        color = BeerColors.muted,
                        fontSize = 11.sp
                    )
                }
            }

            // ── Événements récents ──
            val events = detail?.events.orEmpty()
            if (events.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                Text("🕒 Historique", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.height(6.dp))
                events.take(10).forEach { e ->
                    Text(
                        "• ${e.kind ?: "—"} · ${formatDate(e.createdAt)}",
                        color = BeerColors.muted,
                        fontSize = 11.sp
                    )
                }
            }

            // ── Zone dangereuse ──
            Spacer(Modifier.height(16.dp))
            Text("Zone dangereuse", color = BeerColors.error, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            Button(
                onClick = { confirmWipe = true },
                enabled = !busy && name.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = BeerColors.error)
            ) {
                Text("Effacer RPG", color = Color.White, fontWeight = FontWeight.Bold)
            }
            Text(
                "Efface niveau, XP, badges, quêtes et historique RPG — le carnet de dégustations reste intact.",
                color = BeerColors.muted,
                fontSize = 10.sp
            )
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmRevoke != null) {
        val b = confirmRevoke!!
        AlertDialog(
            onDismissRequest = { confirmRevoke = null },
            title = { Text("Retirer « ${b.name ?: b.key} » ?", color = BeerColors.text, fontWeight = FontWeight.Bold) },
            text = { Text("Ce badge sera retiré du grimoire de $name.", color = BeerColors.muted) },
            confirmButton = {
                TextButton(onClick = {
                    val key = b.key.orEmpty()
                    confirmRevoke = null
                    scope.launch {
                        busy = true
                        val res = withContext(Dispatchers.IO) {
                            try { vm.api.adminRpgRevokeBadge(name, key) } catch (_: Exception) { null }
                        }
                        busy = false
                        if (res?.removed == true) {
                            vm.showToast("Badge retiré", ToastPayload.Variant.INFO, label = "🏅 ${b.name}")
                            applyDetail(res.player)
                        } else {
                            vm.showToast("Échec retrait", ToastPayload.Variant.ERROR)
                        }
                    }
                }) { Text("Retirer", color = BeerColors.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmRevoke = null }) { Text("Annuler", color = BeerColors.muted) }
            },
            containerColor = BeerColors.card
        )
    }

    if (confirmWipe) {
        AlertDialog(
            onDismissRequest = { confirmWipe = false },
            title = { Text("Effacer tout le RPG de « $name » ?", color = BeerColors.text, fontWeight = FontWeight.Bold) },
            text = {
                Text(
                    "Irréversible : niveau, XP, badges, quêtes et historique RPG seront supprimés. Le carnet de dégustations n'est pas touché.",
                    color = BeerColors.muted
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmWipe = false
                    scope.launch {
                        busy = true
                        val ok = withContext(Dispatchers.IO) {
                            try { vm.api.adminRpgWipePlayer(name) } catch (_: Exception) { false }
                        }
                        busy = false
                        if (ok) {
                            vm.showToast("RPG effacé pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                            onChanged()
                            onClose()
                        } else {
                            vm.showToast("Échec effacement", ToastPayload.Variant.ERROR)
                        }
                    }
                }) { Text("Effacer le RPG", color = BeerColors.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmWipe = false }) { Text("Annuler", color = BeerColors.muted) }
            },
            containerColor = BeerColors.card
        )
    }
}

/** Tuile badge admin (parité visuelle avec BadgeTile du Grimoire) — tap pour donner/retirer. */
@Composable
fun AdminBadgeTile(b: RpgBadge, busy: Boolean, onTap: () -> Unit) {
    val earned = b.earned
    val rarity = (b.rarity ?: "common").lowercase()
    val rarityColor = when (rarity) {
        "legendary" -> LegendAmber
        "epic" -> BadgePurple
        "rare" -> RareBlue
        else -> BeerColors.muted
    }
    val borderColor = if (earned) rarityColor.copy(alpha = 0.6f) else BeerColors.border
    val bg = if (earned) rarityColor.copy(alpha = 0.14f) else BeerColors.card
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, borderColor, RoundedCornerShape(12.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(b.icon ?: "🏅", fontSize = 20.sp)
        Text(
            b.name ?: "—",
            color = BeerColors.text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            lineHeight = 13.sp
        )
        Text(rarityLabelFr(b.rarity), color = rarityColor, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text(
            if (earned) "Retirer" else "Donner",
            color = if (earned) BeerColors.error else Color.Black,
            fontSize = 11.sp,
            fontWeight = FontWeight.Black,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(if (earned) BeerColors.error.copy(alpha = 0.12f) else Gold)
                .border(1.dp, if (earned) BeerColors.error.copy(alpha = 0.4f) else Gold, RoundedCornerShape(8.dp))
                .clickable(enabled = !busy && !b.key.isNullOrBlank()) { onTap() }
                .padding(vertical = 6.dp),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
fun FeedbackAdminCard(
    f: AdminFeedbackItem,
    busy: Boolean,
    onToggleRead: () -> Unit,
    onDone: () -> Unit,
    onReject: () -> Unit,
    onReopen: () -> Unit,
    onDelete: () -> Unit,
) {
    val unread = f.adminRead != true
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(
                1.5.dp,
                when {
                    f.isDone -> Color(0xFF4ADE80).copy(alpha = 0.45f)
                    f.isRejected -> BeerColors.error.copy(alpha = 0.45f)
                    unread -> BeerColors.accent.copy(alpha = 0.45f)
                    else -> BeerColors.border
                },
                RoundedCornerShape(12.dp)
            )
            .background(BeerColors.card)
            .padding(12.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(f.username ?: "—", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text(f.displayStatus, color = Gold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        Text(f.categoryLabel ?: f.category ?: "", color = BeerColors.accent, fontSize = 11.sp)
        Spacer(Modifier.height(4.dp))
        Text(f.message.orEmpty(), color = BeerColors.text, fontSize = 13.sp)
        f.adminReply?.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(4.dp))
            Text("Réponse : $it", color = BeerColors.muted, fontSize = 12.sp)
        }
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(
                checked = f.adminRead == true,
                onCheckedChange = { onToggleRead() },
                enabled = !busy
            )
            Text("Lu", color = BeerColors.text, fontSize = 12.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (f.isOpen) {
                Text(
                    "✓ Fait",
                    color = Color.Black,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(BeerColors.accent)
                        .clickable(enabled = !busy, onClick = onDone)
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                )
                Text(
                    "✕ Refuser",
                    color = BeerColors.text,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                        .clickable(enabled = !busy, onClick = onReject)
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                )
            } else {
                Text(
                    "Rouvrir",
                    color = BeerColors.text,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                        .clickable(enabled = !busy, onClick = onReopen)
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                )
            }
            Text(
                "Suppr",
                color = BeerColors.error,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, BeerColors.error.copy(alpha = 0.45f), RoundedCornerShape(8.dp))
                    .clickable(enabled = !busy, onClick = onDelete)
                    .padding(horizontal = 10.dp, vertical = 7.dp)
            )
        }
    }
}
