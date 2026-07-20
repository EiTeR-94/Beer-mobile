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
import fr.eiter.plexibeer.RpgAdminPlayer
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

private val Gold = Color(0xFFF5C542)
private val QuestBlue = Color(0xFF60A5FA)
private val BadgePurple = Color(0xFFC084FC)
private val RareBlue = Color(0xFF60A5FA)
private val LegendAmber = Color(0xFFF59E0B)
private val Copper = Color(0xFFD97706)
private val Silver = Color(0xFF94A3B8)
private val MythViolet = Color(0xFFA78BFA)
private val ExploreGreen = Color(0xFF34D399)

/** Cadre RPG de l’accueil — aligné sur les TITLE_BANDS serveur. */
private data class LevelFrame(
    val bandName: String,
    val border: Color,
    val borderWidth: Dp,
    val outerBorder: Color? = null,
    val background: Color,
    val accent: Color,
    val sealRing: Color,
)

private fun levelFrameFor(profile: RpgProfile): LevelFrame {
    if (profile.beerMaster) {
        return LevelFrame(
            bandName = profile.prestige?.ribbon ?: "Beer Master",
            border = Gold.copy(alpha = 0.75f),
            borderWidth = 2.dp,
            outerBorder = Color(0xFFFBBF24).copy(alpha = 0.35f),
            background = Color(0xFF78350F).copy(alpha = 0.42f),
            accent = Gold,
            sealRing = Gold,
        )
    }
    val lvl = profile.level.coerceAtLeast(1)
    val band = profile.titleBand?.name
    return when {
        lvl <= 4 -> LevelFrame(
            bandName = band ?: "Premiers pas",
            border = BeerColors.border,
            borderWidth = 1.dp,
            background = BeerColors.card,
            accent = BeerColors.accent,
            sealRing = Silver,
        )
        lvl <= 8 -> LevelFrame(
            bandName = band ?: "Apprentissage",
            border = Copper.copy(alpha = 0.55f),
            borderWidth = 1.5.dp,
            background = Color(0xFF1C1410),
            accent = Copper,
            sealRing = Copper,
        )
        lvl <= 12 -> LevelFrame(
            bandName = band ?: "Exploration",
            border = ExploreGreen.copy(alpha = 0.5f),
            borderWidth = 1.5.dp,
            background = Color(0xFF0F1A16),
            accent = ExploreGreen,
            sealRing = ExploreGreen,
        )
        lvl <= 16 -> LevelFrame(
            bandName = band ?: "Affirmation",
            border = QuestBlue.copy(alpha = 0.55f),
            borderWidth = 1.5.dp,
            background = Color(0xFF0F1620),
            accent = QuestBlue,
            sealRing = QuestBlue,
        )
        lvl <= 20 -> LevelFrame(
            bandName = band ?: "Expertise",
            border = BadgePurple.copy(alpha = 0.55f),
            borderWidth = 1.5.dp,
            background = Color(0xFF16101F),
            accent = BadgePurple,
            sealRing = BadgePurple,
        )
        lvl <= 24 -> LevelFrame(
            bandName = band ?: "Renommée",
            border = Gold.copy(alpha = 0.5f),
            borderWidth = 1.5.dp,
            outerBorder = Gold.copy(alpha = 0.2f),
            background = Color(0xFF1A160E),
            accent = Gold,
            sealRing = Gold,
        )
        lvl <= 28 -> LevelFrame(
            bandName = band ?: "Légende",
            border = Gold.copy(alpha = 0.7f),
            borderWidth = 2.dp,
            outerBorder = LegendAmber.copy(alpha = 0.3f),
            background = Color(0xFF1F180A),
            accent = LegendAmber,
            sealRing = LegendAmber,
        )
        else -> LevelFrame(
            bandName = band ?: "Mythe",
            border = MythViolet.copy(alpha = 0.7f),
            borderWidth = 2.dp,
            outerBorder = Gold.copy(alpha = 0.35f),
            background = Color(0xFF18101F),
            accent = MythViolet,
            sealRing = Gold,
        )
    }
}

@Composable
fun BqHudBar(profile: RpgProfile, onClick: () -> Unit) {
    val pct = (profile.progressPct.coerceIn(0.0, 100.0) / 100.0).toFloat()
    val into = profile.xpIntoLevel
    val span = if (profile.xpLevelStart != null && profile.xpLevelNext != null) {
        (profile.xpLevelNext - profile.xpLevelStart).coerceAtLeast(1)
    } else null
    val mid = if (into != null && span != null) "$into / $span XP" else "${profile.xp} XP"
    val right = profile.xpToNext?.let { "encore $it" } ?: "max"
    val master = profile.beerMaster
    val frame = levelFrameFor(profile)
    val shape = RoundedCornerShape(14.dp)

    Column(
        Modifier
            .fillMaxWidth()
            .then(
                if (frame.outerBorder != null) {
                    Modifier
                        .border(3.dp, frame.outerBorder, shape)
                        .padding(2.dp)
                } else Modifier
            )
            .clip(shape)
            .border(frame.borderWidth, frame.border, shape)
            .background(
                Brush.verticalGradient(
                    listOf(
                        frame.background,
                        BeerColors.card.copy(alpha = 0.92f),
                    )
                )
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 10.dp)
    ) {
        // Bandeau de rang RPG
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                frame.bandName.uppercase(),
                color = frame.accent,
                fontSize = 10.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 1.2.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Text(
                "Nv ${profile.level}",
                color = frame.accent,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .border(1.dp, frame.border, RoundedCornerShape(999.dp))
                    .background(frame.background)
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(BeerColors.fieldBg)
                    .border(2.dp, frame.sealRing, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(profile.displayIcon(), fontSize = 20.sp)
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                if (master) {
                    Text(
                        profile.prestige?.ribbon ?: "BEER MASTER",
                        color = Gold,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        profile.title ?: "Aventurier",
                        color = BeerColors.text,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        "${profile.progressPct.toInt()}%",
                        color = frame.accent,
                        fontWeight = FontWeight.ExtraBold,
                        fontSize = 13.sp
                    )
                }
                val sub = buildList {
                    profile.classInfo?.name?.let { add(it) }
                    if (!master) profile.titleBand?.name?.let { add(it) }
                }.joinToString(" · ")
                if (sub.isNotBlank()) {
                    Text(sub, color = BeerColors.muted, fontSize = 11.sp, maxLines = 1)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        LinearProgressIndicator(
            progress = { pct },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(999.dp)),
            color = frame.accent,
            trackColor = BeerColors.fieldBg
        )
        Spacer(Modifier.height(4.dp))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(mid, color = BeerColors.text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(right, color = BeerColors.muted, fontSize = 11.sp)
        }
    }
}

@Composable
fun GrimoireSheet(vm: AppViewModel) {
    val state = vm.rpgState
    var tab by remember { mutableIntStateOf(0) }
    var detailBadge by remember { mutableStateOf<RpgBadge?>(null) }
    val tabs = listOf("Accueil", "Quêtes", "Badges", "Atlas")

    Box(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .consumeClicks()
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(
                    "📖 Grimoire",
                    style = MaterialTheme.typography.headlineSmall,
                    color = BeerColors.text,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    "Fermer ✕",
                    color = BeerColors.muted,
                    modifier = Modifier
                        .clickable { vm.closeSheet() }
                        .padding(8.dp)
                )
            }
            Spacer(Modifier.height(8.dp))
            if (state == null || !state.enabled || state.profile == null) {
                Text(
                    if (state?.enabled == false) "Beerquest est désactivé sur le serveur."
                    else "Beerquest n’est pas disponible pour ce compte.",
                    color = BeerColors.muted,
                    fontSize = 13.sp
                )
                return
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                tabs.forEachIndexed { i, label ->
                    val sel = tab == i
                    Text(
                        label,
                        color = if (sel) Color.Black else BeerColors.muted,
                        fontWeight = if (sel) FontWeight.Bold else FontWeight.SemiBold,
                        fontSize = 12.sp,
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (sel) BeerColors.accent else BeerColors.card)
                            .border(1.dp, if (sel) BeerColors.accent else BeerColors.border, RoundedCornerShape(10.dp))
                            .clickable { tab = i }
                            .padding(vertical = 8.dp),
                        textAlign = TextAlign.Center
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            when (tab) {
                0 -> GrimoireHome(state, onBadge = { detailBadge = it })
                1 -> GrimoireQuests(state)
                2 -> GrimoireBadges(state, onBadge = { detailBadge = it })
                3 -> GrimoireAtlas(state, vm)
            }
        }
        detailBadge?.let { b ->
            RpgBadgeDetailDialog(badge = b, onDismiss = { detailBadge = null })
        }
    }
}

@Composable
private fun ColumnScope.GrimoireHome(state: RpgState, onBadge: (RpgBadge) -> Unit) {
    val p = state.profile ?: return
    val master = p.beerMaster
    val nActive = state.quests?.active?.size ?: 0
    val scroll = rememberScrollState()
    Column(Modifier.verticalScroll(scroll)) {
        // Master card en premier (parité iOS)
        if (master) {
            MasterCard(p)
            Spacer(Modifier.height(10.dp))
        }

        // Fiche d’aventurier unique : avatar + XP + stats (parité iOS homeTab)
        FicheAventurierCard(p = p, state = state, nActive = nActive)

        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Quêtes en cours",
            ico = "📜",
            count = nActive.takeIf { it > 0 }
        ) {
            val active = state.quests?.active.orEmpty().take(3)
            if (active.isEmpty()) {
                Text(
                    "Aucune quête active — le tavernier en prépare pour demain.",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
            } else {
                active.forEach { QuestCard(it) }
            }
        }
        val next = state.nextBadges
        if (next.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            SectionCard(title = "Prochains badges", ico = "🏅", count = next.size) {
                next.forEach {
                    Box(Modifier.clickable { onBadge(it) }) {
                        BadgeProgressRow(it)
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        SectionCard(title = "Le tavernier", ico = "🗣️", count = null) {
            Text(
                state.phrase?.takeIf { it.isNotBlank() } ?: "…",
                color = BeerColors.muted,
                fontSize = 14.sp,
                fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
            )
        }
        Spacer(Modifier.height(28.dp))
    }
}

/** Encadrement section grimoire (parité iOS sectionCard). */
@Composable
private fun SectionCard(
    title: String,
    ico: String,
    count: Int?,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
            .background(BeerColors.card)
            .padding(12.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "$ico $title",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                modifier = Modifier.weight(1f)
            )
            count?.let { n ->
                Text(
                    "$n",
                    color = BeerColors.muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(BeerColors.fieldBg)
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        content()
    }
}

/** Fiche d’aventurier — une seule carte (avatar, XP, stats) comme iOS. */
@Composable
private fun FicheAventurierCard(p: RpgProfile, state: RpgState, nActive: Int) {
    val master = p.beerMaster
    val className = p.classInfo?.name ?: p.classKey ?: "Aventurier"
    val classIcon = p.classInfo?.icon ?: "🍺"
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(
                1.dp,
                if (master) Gold.copy(alpha = 0.4f) else BeerColors.border,
                RoundedCornerShape(14.dp)
            )
            .background(
                if (master) {
                    Brush.linearGradient(listOf(Color(0xFF47300D), BeerColors.card))
                } else {
                    Brush.linearGradient(listOf(BeerColors.card, BeerColors.card.copy(alpha = 0.98f)))
                }
            )
            .padding(14.dp)
    ) {
        Text(
            "Fiche d’aventurier",
            color = BeerColors.muted,
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.6.sp
        )
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.Top) {
            // Avatar + pastille niveau en bas (parité iOS offset)
            Box(
                Modifier.size(64.dp),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(BeerColors.fieldBg)
                        .border(2.5.dp, if (master) Gold else BeerColors.accent, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(p.displayIcon(), fontSize = 28.sp)
                }
                Text(
                    "${p.level}",
                    color = BeerColors.text,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .offset(y = 4.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(BeerColors.card.copy(alpha = 0.95f))
                        .padding(horizontal = 5.dp, vertical = 1.dp)
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    p.title ?: "Aventurier",
                    color = BeerColors.text,
                    fontWeight = FontWeight.Bold,
                    fontSize = 17.sp
                )
                Spacer(Modifier.height(4.dp))
                if (master) {
                    Text(
                        "Profil unique · Beer Master",
                        color = Gold,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                } else {
                    Text(
                        "Classe · $classIcon $className",
                        color = BeerColors.muted,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(Modifier.height(4.dp))
                if (master) {
                    Text(
                        "Prestige",
                        color = Gold,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(Gold.copy(alpha = 0.12f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                } else {
                    p.titleBand?.name?.takeIf { it.isNotBlank() }?.let { band ->
                        Text(
                            band,
                            color = BeerColors.accent,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(BeerColors.accent.copy(alpha = 0.12f))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        XpHeroBar(p)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatTileSoft("🔥", "${p.streakDays}", "Streak", Modifier.weight(1f))
            StatTileSoft(
                if (p.dailySoftCapped) "⛔" else "⚡",
                "${p.dailyXp}/${p.dailySoftCap}",
                if (p.dailySoftCapped) "Soft cap" else "XP du jour",
                Modifier.weight(1f)
            )
            StatTileSoft(
                "🍺",
                "${state.atlas?.totalCheckins ?: 0}",
                "Check-ins",
                Modifier.weight(1f)
            )
            if (master) {
                StatTileSoft("👑", "Unique", "Prestige", Modifier.weight(1f))
            } else {
                StatTileSoft("📜", "$nActive", "Quêtes", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MasterCard(p: RpgProfile) {
    // Parité iOS masterCard
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, Gold.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
            .background(Color(0xFF38240A).copy(alpha = 0.95f))
            .padding(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text("👑", fontSize = 22.sp)
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(
                p.prestige?.ribbon ?: "BEER MASTER",
                color = Gold,
                fontSize = 10.sp,
                fontWeight = FontWeight.Black
            )
            Text(
                p.title ?: "Beer Master",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Text(
                p.prestige?.tagline ?: "Couronne de la taverne",
                color = BeerColors.muted,
                fontSize = 12.sp
            )
            p.prestige?.blurb?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(4.dp))
                Text(it, color = BeerColors.muted, fontSize = 12.sp)
            }
        }
    }
}

/** Barre XP dans la fiche (parité iOS xpHeroBar). */
@Composable
private fun XpHeroBar(p: RpgProfile) {
    val into = p.xpIntoLevel
    val span = if (p.xpLevelStart != null && p.xpLevelNext != null) {
        (p.xpLevelNext - p.xpLevelStart).coerceAtLeast(1)
    } else null
    val mid = if (into != null && span != null) "$into / $span XP" else "${p.xp} XP"
    val pct = (p.progressPct.coerceIn(0.0, 100.0) / 100.0).toFloat()
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Nv ${p.level}",
                color = BeerColors.text,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(BeerColors.fieldBg)
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            )
            Spacer(Modifier.weight(1f))
            Text(mid, color = BeerColors.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(
                p.xpToNext?.let { "encore $it" } ?: "max",
                color = BeerColors.accent,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(Modifier.height(6.dp))
        // Barre dégradé jaune→orange (parité iOS)
        Box(
            Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(BeerColors.fieldBg)
        ) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(pct.coerceIn(0.02f, 1f))
                    .clip(RoundedCornerShape(999.dp))
                    .background(
                        Brush.horizontalGradient(
                            listOf(Color(0xFFFACC15), Color(0xFFF97316))
                        )
                    )
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            "${p.progressPct.toInt()}% vers le prochain niveau",
            color = BeerColors.muted,
            fontSize = 11.sp,
            modifier = Modifier.align(Alignment.End)
        )
    }
}

/** Stat tile style iOS (fond fieldBg soft). */
@Composable
private fun StatTileSoft(ico: String, value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .border(1.dp, BeerColors.border.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
            .background(BeerColors.fieldBg.copy(alpha = 0.65f))
            .padding(vertical = 8.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(ico, fontSize = 14.sp)
        Text(
            value,
            color = BeerColors.text,
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(label, color = BeerColors.muted, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** Hero de tab grimoire (parité iOS tabHero). */
@Composable
private fun TabHero(
    kicker: String,
    title: String,
    blurb: String,
    master: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(
                1.dp,
                if (master) Gold.copy(alpha = 0.4f) else BeerColors.border,
                RoundedCornerShape(14.dp)
            )
            .background(
                if (master) {
                    Brush.linearGradient(listOf(Color(0xFF47300D), BeerColors.card))
                } else {
                    Brush.linearGradient(listOf(BeerColors.card, BeerColors.card.copy(alpha = 0.98f)))
                }
            )
            .padding(14.dp)
    ) {
        Text(
            kicker,
            color = if (master) Gold.copy(alpha = 0.9f) else BeerColors.muted,
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.8.sp
        )
        Spacer(Modifier.height(4.dp))
        Text(title, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 17.sp)
        Spacer(Modifier.height(4.dp))
        Text(blurb, color = BeerColors.muted, fontSize = 13.sp)
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun ColumnScope.GrimoireQuests(state: RpgState) {
    val scroll = rememberScrollState()
    val q = state.quests
    val active = q?.active.orEmpty()
    val doneToday = q?.doneToday.orEmpty()
    val doneWeekly = q?.doneWeekly.orEmpty()
    val dailies = active.filter { it.kind == "daily" } + doneToday
    val weeklies = active.filter { it.kind == "weekly" } + doneWeekly
    val story = active.filter { it.kind == "story" }
    val nOpen = active.count { it.status != "done" }
    val nDone = doneToday.size + doneWeekly.size
    val nTotal = active.size + doneToday.size + doneWeekly.size

    Column(Modifier.verticalScroll(scroll)) {
        TabHero(
            kicker = "Tableau des quêtes",
            title = "📜 Missions de la taverne",
            blurb = "Accomplis des objectifs pour gagner de l’XP. Les journalières se renouvellent chaque jour."
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTileSoft("⚔️", "$nOpen", "Actives", Modifier.weight(1f))
                StatTileSoft("✅", "$nDone", "Finies", Modifier.weight(1f))
                StatTileSoft("✨", "$nTotal", "Total", Modifier.weight(1f))
            }
        }
        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Journalières",
            ico = "☀️",
            count = dailies.size.takeIf { it > 0 }
        ) {
            if (dailies.isEmpty()) {
                Text("Pas de quête du jour — reviens demain.", color = BeerColors.muted, fontSize = 12.sp)
            } else {
                dailies.forEach { QuestCard(it) }
            }
        }
        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Hebdomadaires",
            ico = "📅",
            count = weeklies.size.takeIf { it > 0 }
        ) {
            if (weeklies.isEmpty()) {
                Text("Aucune quête hebdo pour l’instant.", color = BeerColors.muted, fontSize = 12.sp)
            } else {
                weeklies.forEach { QuestCard(it) }
            }
        }
        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Histoire",
            ico = "📖",
            count = story.size.takeIf { it > 0 }
        ) {
            if (story.isEmpty()) {
                Text("Chapitres à venir… le tavernier écrit encore.", color = BeerColors.muted, fontSize = 12.sp)
            } else {
                story.forEach { QuestCard(it) }
            }
        }
        Spacer(Modifier.height(28.dp))
    }
}

@Composable
private fun ColumnScope.GrimoireBadges(state: RpgState, onBadge: (RpgBadge) -> Unit) {
    val badges = state.badges
    val earnedList = badges.filter { it.earned }.sortedWith(
        compareByDescending<RpgBadge> { rarityOrder(it.rarity) }
            .thenBy { it.name.orEmpty() }
    )
    val locked = badges.filter { !it.earned }
    val inProgress = locked
        .filter { it.progress > 0 }
        .sortedByDescending { it.progress.toDouble() / it.target.coerceAtLeast(1) }
    val byRarity = linkedMapOf(
        "common" to mutableListOf<RpgBadge>(),
        "rare" to mutableListOf(),
        "epic" to mutableListOf(),
        "legendary" to mutableListOf(),
    )
    locked.filter { it.progress <= 0 }.forEach { b ->
        val r = (b.rarity ?: "common").lowercase()
        byRarity.getOrPut(r) { mutableListOf() }.add(b)
    }
    byRarity.values.forEach { list ->
        list.sortWith(compareBy({ rarityOrder(it.rarity) }, { it.name.orEmpty() }))
    }
    val nEarned = earnedList.size
    val nTotal = badges.size
    val pctAll = if (nTotal > 0) (nEarned * 100 / nTotal) else 0
    val scroll = rememberScrollState()

    Column(
        Modifier
            .weight(1f)
            .fillMaxWidth()
            .verticalScroll(scroll)
    ) {
        // Hero « Salle des trophées » (parité webapp)
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .border(1.dp, Gold.copy(alpha = 0.28f), RoundedCornerShape(14.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xFF1A160E), BeerColors.card)
                    )
                )
                .padding(12.dp)
        ) {
            Text(
                "SALLE DES TROPHÉES",
                color = Gold.copy(alpha = 0.9f),
                fontSize = 10.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 1.6.sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "🏅 Collection de badges",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Chaque badge a un objectif clair. Touche une tuile pour voir la progression.",
                color = BeerColors.muted,
                fontSize = 12.sp
            )
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                StatTile("🏆", "$nEarned", "Obtenus", Modifier.weight(1f))
                StatTile("🔒", "${locked.size}", "À faire", Modifier.weight(1f))
                StatTile("📊", "$pctAll%", "Complétion", Modifier.weight(1f))
            }
            Spacer(Modifier.height(10.dp))
            LinearProgressIndicator(
                progress = { (pctAll / 100f).coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(999.dp)),
                color = BadgePurple,
                trackColor = BeerColors.fieldBg
            )
            Spacer(Modifier.height(4.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    "$nEarned / $nTotal badges",
                    color = BeerColors.text,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "${(nTotal - nEarned).coerceAtLeast(0)} restants",
                    color = BeerColors.muted,
                    fontSize = 11.sp
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                LegendDot(Silver, "Commun")
                LegendDot(RareBlue, "Rare")
                LegendDot(BadgePurple, "Épique")
                LegendDot(LegendAmber, "Légendaire")
            }
        }

        Spacer(Modifier.height(12.dp))
        BadgeGroupSection("En cours", "⚔️", inProgress, onBadge)
        BadgeGroupSection("Commun", "⚪", byRarity["common"].orEmpty(), onBadge)
        BadgeGroupSection("Rare", "🔵", byRarity["rare"].orEmpty(), onBadge)
        BadgeGroupSection("Épique", "🟣", byRarity["epic"].orEmpty(), onBadge)
        BadgeGroupSection("Légendaire", "🟡", byRarity["legendary"].orEmpty(), onBadge)
        BadgeGroupSection("Obtenus", "✅", earnedList, onBadge)
        Spacer(Modifier.height(28.dp))
    }
}

private fun rarityOrder(r: String?): Int = when ((r ?: "common").lowercase()) {
    "legendary" -> 3
    "epic" -> 2
    "rare" -> 1
    else -> 0
}

@Composable
private fun LegendDot(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
                .border(1.dp, BeerColors.border, CircleShape)
        )
        Spacer(Modifier.width(4.dp))
        Text(label, color = BeerColors.muted, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun BadgeGroupSection(
    title: String,
    ico: String,
    list: List<RpgBadge>,
    onBadge: (RpgBadge) -> Unit = {},
) {
    if (list.isEmpty()) return
    Column(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
            .background(BeerColors.card)
            .padding(10.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "$ico $title",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp
            )
            Text(
                "${list.size}",
                color = BeerColors.muted,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(BeerColors.fieldBg)
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            )
        }
        Spacer(Modifier.height(8.dp))
        BadgeGrid(list, onBadge)
    }
}

@Composable
private fun BadgeGrid(list: List<RpgBadge>, onBadge: (RpgBadge) -> Unit = {}) {
    val rows = list.chunked(3)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                row.forEach { b ->
                    Box(Modifier.weight(1f).clickable { onBadge(b) }) { BadgeTile(b) }
                }
                // pad incomplete rows
                repeat(3 - row.size) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun ColumnScope.GrimoireAtlas(state: RpgState, vm: AppViewModel) {
    val scroll = rememberScrollState()
    val a = state.atlas
    val p = state.profile
    val master = p?.beerMaster == true
    val aff = state.classAffinity.orEmpty()
    val classes = state.classes
    val equippedKey = p?.classKey
    val recKey = bestAffinityKey(aff, classes)
    val equipped = classes.firstOrNull { it.key == equippedKey }
    val others = classes.filter { it.key != equippedKey }
    val styles = a?.styles.orEmpty()
    val equippedLabel = equipped?.let {
        "${it.icon ?: "🍺"} ${it.name ?: it.key.orEmpty()}".trim()
    }.orEmpty()
    val recLabel = recKey
        ?.takeIf { it != equippedKey }
        ?.let { rk -> classes.firstOrNull { it.key == rk } }
        ?.let { "${it.icon ?: "🍺"} ${it.name ?: it.key.orEmpty()}".trim() }
        .orEmpty()

    Column(Modifier.verticalScroll(scroll)) {
        // Hero Atlas (parité iOS tabHero)
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
                .background(
                    if (master) {
                        Brush.linearGradient(
                            listOf(Color(0xFF47300D), BeerColors.card)
                        )
                    } else {
                        Brush.linearGradient(
                            listOf(BeerColors.card, BeerColors.card)
                        )
                    }
                )
                .padding(12.dp)
        ) {
            Text(
                "Carte du royaume",
                color = if (master) Gold.copy(alpha = 0.9f) else BeerColors.muted,
                fontSize = 10.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 0.8.sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "🗺️ Atlas du dégustateur",
                color = BeerColors.text,
                fontWeight = FontWeight.Bold,
                fontSize = 17.sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Ta collection, tes territoires de goût, et la classe qui te définit à la taverne.",
                color = BeerColors.muted,
                fontSize = 12.sp
            )
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                StatTile("🎨", "${a?.stylesCount ?: 0}", "Styles", Modifier.weight(1f))
                StatTile("🌿", "${a?.hopsCount ?: 0}", "Houblons", Modifier.weight(1f))
                StatTile("🏭", "${a?.breweriesCount ?: 0}", "Brasseries", Modifier.weight(1f))
                StatTile("📷", "${a?.photos ?: 0}", "Photos", Modifier.weight(1f))
            }
            if (equippedLabel.isNotEmpty() || recLabel.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (equippedLabel.isNotEmpty()) {
                        Text(
                            "Équipée · $equippedLabel",
                            color = BeerColors.accent,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(BeerColors.accent.copy(alpha = 0.14f))
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                    if (recLabel.isNotEmpty()) {
                        Text(
                            "Plus jouée · $recLabel",
                            color = QuestBlue,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(QuestBlue.copy(alpha = 0.12f))
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Styles découverts",
            ico = "🍺",
            count = a?.stylesCount?.takeIf { it > 0 }
        ) {
            if (styles.isEmpty()) {
                Text(
                    "Aucun style noté pour l’instant — goûte et logue !",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
            } else {
                StyleChips(styles)
            }
        }

        Spacer(Modifier.height(12.dp))
        SectionCard(
            title = "Classes",
            ico = "⚔️",
            count = if (equipped != null) 1 else null
        ) {
            Text(
                "Une seule spécialité à la fois. Si la bière colle : +2 XP, parfois un bonus, et de l’habitude (le % à droite). Max 12 XP de classe par bière.",
                color = BeerColors.muted,
                fontSize = 12.sp
            )
            if (equipped != null) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Classe équipée",
                    color = Gold.copy(alpha = 0.95f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.4.sp
                )
                Spacer(Modifier.height(6.dp))
                ClassCard(
                    c = equipped,
                    aff = aff[equipped.key.orEmpty()] ?: 0,
                    equipped = true,
                    recommended = equipped.key == recKey,
                    onEquip = {}
                )
            }
            if (others.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Autres classes · toucher pour équiper",
                    color = BeerColors.muted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.4.sp
                )
                Spacer(Modifier.height(6.dp))
                others.forEach { c ->
                    val key = c.key.orEmpty()
                    ClassCard(
                        c = c,
                        aff = aff[key] ?: 0,
                        equipped = false,
                        recommended = key == recKey,
                        onEquip = {
                            if (key.isNotBlank()) vm.equipRpgClass(key)
                        }
                    )
                }
            }
        }
        Spacer(Modifier.height(28.dp))
    }
}

/** Clé de classe avec la plus haute affinité (parité iOS bestAffinityKey). */
private fun bestAffinityKey(aff: Map<String, Int>, classes: List<RpgClassInfo>): String? {
    var best: String? = null
    var bestVal = -1
    for (c in classes) {
        val k = c.key ?: continue
        val v = aff[k] ?: 0
        if (v > bestVal) {
            bestVal = v
            best = k
        }
    }
    return best
}

private fun habitLabel(aff: Int): String = when {
    aff >= 70 -> "+3 XP d’habitude"
    aff >= 50 -> "+2 XP d’habitude"
    aff >= 25 -> "+1 XP d’habitude"
    else -> "pas encore d’habitude (+0)"
}

/** Carte classe Atlas — parité iOS ClassCardView. */
@Composable
private fun ClassCard(
    c: RpgClassInfo,
    aff: Int,
    equipped: Boolean,
    recommended: Boolean,
    onEquip: () -> Unit,
) {
    val whenText = c.whenText?.takeIf { it.isNotBlank() } ?: "Quand la bière colle à la classe"
    val special = (c.special ?: "Bonus si condition remplie").replace("**", "")
    val habit = habitLabel(aff)
    val equipGoldBg = Color(0xFF382B17) // brun-or plein iOS
    val recBlue = QuestBlue

    Row(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 6.dp)
            .alpha(if (equipped) 1f else 0.82f)
            .clip(RoundedCornerShape(12.dp))
            .border(
                width = if (equipped) 2.dp else 1.dp,
                color = when {
                    equipped -> BeerColors.accent
                    recommended -> recBlue.copy(alpha = 0.45f)
                    else -> BeerColors.border
                },
                shape = RoundedCornerShape(12.dp)
            )
            .background(if (equipped) equipGoldBg else BeerColors.card)
            .clickable(enabled = !equipped) { onEquip() }
            .padding(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Column(Modifier.weight(1f)) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "${c.icon ?: "🍺"} ${c.name ?: c.key ?: "—"}",
                    color = BeerColors.text,
                    fontWeight = FontWeight.Black,
                    fontSize = 15.sp,
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.width(6.dp))
                when {
                    equipped -> {
                        Text(
                            "Équipée",
                            color = Color(0xFF121212),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Black,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(BeerColors.accent)
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                    recommended -> {
                        Text(
                            "Celle que tu joues le plus",
                            color = recBlue,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Black,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(recBlue.copy(alpha = 0.15f))
                                .border(1.dp, recBlue.copy(alpha = 0.4f), RoundedCornerShape(999.dp))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                    else -> {
                        Text(
                            "Toucher pour équiper",
                            color = BeerColors.muted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .drawBehind {
                                    val stroke = Stroke(
                                        width = 1.dp.toPx(),
                                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f))
                                    )
                                    drawRoundRect(
                                        color = BeerColors.muted.copy(alpha = 0.55f),
                                        style = stroke,
                                        cornerRadius = CornerRadius(999.dp.toPx())
                                    )
                                }
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                }
            }
            val blurb = c.blurb
            if (!blurb.isNullOrBlank()) {
                Spacer(Modifier.height(4.dp))
                Text(blurb, color = BeerColors.muted, fontSize = 12.sp)
            }
            Spacer(Modifier.height(4.dp))
            Text(
                buildAnnotatedString {
                    withStyle(
                        SpanStyle(
                            color = recBlue,
                            fontWeight = FontWeight.Black,
                            fontSize = 9.sp
                        )
                    ) { append("Quand ") }
                    withStyle(SpanStyle(color = BeerColors.muted, fontSize = 11.sp)) {
                        append("$whenText → ")
                    }
                    withStyle(
                        SpanStyle(
                            color = BeerColors.text,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.sp
                        )
                    ) { append("+2 XP") }
                }
            )
            Text(
                buildAnnotatedString {
                    withStyle(
                        SpanStyle(
                            color = recBlue,
                            fontWeight = FontWeight.Black,
                            fontSize = 9.sp
                        )
                    ) { append("En plus ") }
                    withStyle(SpanStyle(color = BeerColors.muted, fontSize = 11.sp)) {
                        append(special)
                    }
                }
            )
            Spacer(Modifier.height(2.dp))
            Text(
                (if (equipped) "Active · " else "Si tu l’équipes · ") +
                    habit + " si la bière colle",
                color = if (equipped) ExploreGreen else BeerColors.muted,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
        Spacer(Modifier.width(10.dp))
        // Bloc habitude (parité web / iOS)
        Column(
            Modifier
                .width(72.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(BeerColors.fieldBg)
                .drawBehind {
                    val stroke = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f))
                    )
                    drawRoundRect(
                        color = BeerColors.border,
                        style = stroke,
                        cornerRadius = CornerRadius(10.dp.toPx())
                    )
                }
                .padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "HABITUDE",
                color = BeerColors.muted,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                "$aff%",
                color = BeerColors.text,
                fontSize = 16.sp,
                fontWeight = FontWeight.Black
            )
            Text(
                habit,
                color = BeerColors.muted,
                fontSize = 8.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SectionTitle(t: String) {
    Text(
        t,
        color = BeerColors.text,
        fontWeight = FontWeight.Bold,
        fontSize = 14.sp,
        modifier = Modifier.padding(bottom = 6.dp)
    )
}

@Composable
private fun StatTile(ico: String, value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
            .background(BeerColors.card)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(ico, fontSize = 14.sp)
        Text(value, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
        Text(label, color = BeerColors.muted, fontSize = 9.sp)
    }
}

@Composable
private fun QuestCard(q: RpgQuest) {
    // Parité iOS QuestCardView
    val done = q.status == "done"
    val tgt = q.target.coerceAtLeast(1)
    val prog = q.progress
    val pct = (prog.toFloat() / tgt).coerceIn(0f, 1f)
    val (kindLabel, kindIco, kindColor) = when ((q.kind ?: "").lowercase()) {
        "daily" -> Triple("Journalière", "☀️", QuestBlue)
        "weekly" -> Triple("Hebdo", "📅", BadgePurple)
        "story" -> Triple("Histoire", "📖", Color(0xFFF97316))
        else -> Triple("Quête", "📜", QuestBlue)
    }
    val border = if (done) ExploreGreen else kindColor
    val statusLabel = when {
        done -> "Terminée"
        pct > 0f -> "En cours"
        else -> "À faire"
    }
    Box(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 4.dp)
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .border(1.dp, border.copy(alpha = 0.7f), RoundedCornerShape(12.dp))
                .background(
                    Brush.horizontalGradient(
                        listOf(border.copy(alpha = 0.08f), BeerColors.card)
                    )
                )
                .padding(12.dp)
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "$kindIco $kindLabel",
                        color = kindColor,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(kindColor.copy(alpha = 0.12f))
                            .border(1.dp, kindColor.copy(alpha = 0.35f), RoundedCornerShape(999.dp))
                            .padding(horizontal = 7.dp, vertical = 3.dp)
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        q.title ?: "—",
                        color = BeerColors.text,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                }
                Text(
                    "✨ +${q.rewardXp} XP",
                    color = Gold,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp
                )
            }
            q.description?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(4.dp))
                Text(it, color = BeerColors.muted, fontSize = 12.sp)
            }
            Spacer(Modifier.height(6.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    statusLabel,
                    color = if (done) ExploreGreen else kindColor,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "$prog/$tgt · ${(pct * 100).toInt()}%",
                    color = BeerColors.muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { pct },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(999.dp)),
                color = if (done) ExploreGreen else kindColor,
                trackColor = BeerColors.fieldBg
            )
        }
        // Bandeau gauche (parité iOS)
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .padding(vertical = 4.dp)
                .width(3.dp)
                .height(48.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(border)
        )
    }
}

@Composable
private fun BadgeProgressRow(b: RpgBadge) {
    val tgt = b.target.coerceAtLeast(1)
    val pct = (b.progress.toFloat() / tgt).coerceIn(0f, 1f)
    Column(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(b.icon ?: "🏅", fontSize = 18.sp)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    "${b.name ?: "Badge"} · ${rarityLabelFr(b.rarity)}",
                    color = BeerColors.text,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp
                )
                val goal = (b.hint ?: "").removePrefix("Objectif : ").trim()
                if (goal.isNotBlank()) Text(goal, color = BeerColors.muted, fontSize = 11.sp, maxLines = 2)
            }
        }
        LinearProgressIndicator(
            progress = { pct },
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(999.dp)).padding(top = 4.dp),
            color = BadgePurple,
            trackColor = BeerColors.fieldBg
        )
        Text(
            "${b.progress}/$tgt · ${(pct * 100).toInt()}%",
            color = BeerColors.muted,
            fontSize = 10.sp
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StyleChips(styles: List<String>) {
    val shown = styles.take(24)
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        shown.forEach { s ->
            Text(
                s,
                color = BeerColors.text,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                    .background(BeerColors.fieldBg)
                    .padding(horizontal = 8.dp, vertical = 5.dp)
            )
        }
        if (styles.size > 24) {
            Text(
                "+${styles.size - 24}",
                color = BeerColors.muted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(BeerColors.fieldBg)
                    .padding(horizontal = 8.dp, vertical = 5.dp)
            )
        }
    }
}

@Composable
private fun BadgeTile(b: RpgBadge) {
    val tgt = b.target.coerceAtLeast(1)
    val pct = (b.progress.toFloat() / tgt).coerceIn(0f, 1f)
    val rarity = (b.rarity ?: "common").lowercase()
    val rarityColor = when (rarity) {
        "legendary" -> LegendAmber
        "epic" -> BadgePurple
        "rare" -> RareBlue
        else -> BeerColors.muted
    }
    val borderColor = when {
        b.earned && rarity == "legendary" -> LegendAmber
        b.earned && rarity == "epic" -> BadgePurple
        b.earned && rarity == "rare" -> RareBlue
        b.earned -> BadgePurple
        b.progress > 0 -> Gold.copy(alpha = 0.55f)
        else -> BeerColors.border
    }
    val bg = when {
        b.earned -> Brush.verticalGradient(
            listOf(rarityColor.copy(alpha = 0.18f), BeerColors.card)
        )
        b.progress > 0 -> Brush.verticalGradient(
            listOf(Gold.copy(alpha = 0.08f), BeerColors.card)
        )
        else -> Brush.verticalGradient(listOf(BeerColors.card, BeerColors.card))
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, borderColor, RoundedCornerShape(12.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            b.icon ?: "🏅",
            fontSize = 22.sp,
            modifier = Modifier.padding(bottom = 2.dp)
        )
        Text(
            b.name ?: "—",
            color = if (b.earned) BeerColors.text else BeerColors.text.copy(alpha = 0.88f),
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            lineHeight = 13.sp
        )
        Text(
            rarityLabelFr(b.rarity),
            color = rarityColor,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            if (b.earned) "✓ Obtenu" else "${b.progress}/$tgt · ${(pct * 100).toInt()}%",
            color = if (b.earned) ExploreGreen else BeerColors.muted,
            fontSize = 10.sp,
            fontWeight = if (b.earned) FontWeight.Bold else FontWeight.SemiBold,
            maxLines = 1
        )
        if (!b.earned) {
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { pct },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(999.dp)),
                color = if (b.progress > 0) Gold else rarityColor,
                trackColor = BeerColors.fieldBg
            )
            val goal = (b.hint ?: "").removePrefix("Objectif : ").removePrefix("Objectif:").trim()
            if (goal.isNotBlank()) {
                Spacer(Modifier.height(3.dp))
                Text(
                    goal,
                    color = BeerColors.muted,
                    fontSize = 9.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    lineHeight = 11.sp
                )
            }
        }
    }
}

// ─── Célébrations + intro + détail badge + admin Beerquest ───────────────────

@Composable
fun RpgCelebrationOverlay(vm: AppViewModel) {
    if (vm.showRpgIntro) {
        RpgIntroDialog(
            onDiscover = { vm.dismissRpgIntro(openGrimoire = true) },
            onLater = { vm.dismissRpgIntro(openGrimoire = false) },
        )
    }
    when (val c = vm.rpgCelebration) {
        is RpgCelebration.LevelUp -> RpgLevelUpDialog(c.loot) { vm.dismissRpgCelebration() }
        is RpgCelebration.BadgeUnlock -> RpgBadgeUnlockDialog(c.badge) { open ->
            vm.dismissRpgCelebration(openGrimoire = open)
        }
        null -> {}
    }
}

@Composable
private fun RpgIntroDialog(onDiscover: () -> Unit, onLater: () -> Unit) {
    AlertDialog(
        onDismissRequest = onLater,
        title = {
            Text("⚔ Beerquest", fontWeight = FontWeight.Bold, color = BeerColors.text)
        },
        text = {
            Text(
                "Tes dégustations font progresser un grimoire (XP, quêtes, badges). Le scan et la note ne changent pas.",
                color = BeerColors.muted,
                fontSize = 14.sp
            )
        },
        confirmButton = {
            Button(onClick = onDiscover, colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)) {
                Text("Découvrir", color = Color.Black, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onLater) { Text("Plus tard", color = BeerColors.muted) }
        },
        containerColor = BeerColors.card
    )
}

@Composable
private fun RpgLevelUpDialog(loot: RpgLoot, onDismiss: () -> Unit) {
    val oldLv = loot.oldLevel ?: maxOf(1, loot.level - 1)
    val newLv = loot.level
    val gained = loot.levelsGained ?: maxOf(1, newLv - oldLv)
    val pct = (loot.progressPct.coerceIn(0.0, 100.0) / 100.0).toFloat()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text("LEVEL UP", color = Gold, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp, letterSpacing = 2.sp)
                Text(
                    if (gained > 1) "Niveaux $oldLv → $newLv" else "Niveau $newLv",
                    color = BeerColors.text,
                    fontWeight = FontWeight.Bold,
                    fontSize = 24.sp
                )
            }
        },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text(
                    if (gained > 1) "+$gained niveaux d’un coup" else "Lv $oldLv → Lv $newLv",
                    color = Gold,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp
                )
                Spacer(Modifier.height(6.dp))
                if (loot.titleChanged && loot.oldTitle != null && loot.title != null) {
                    Text("${loot.oldTitle} → ${loot.title}", color = BeerColors.muted, fontSize = 12.sp)
                } else {
                    loot.title?.let { Text(it, color = BeerColors.muted, fontSize = 12.sp) }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    loot.phraseLevelUp ?: loot.phrase ?: "Le tavernier hoche la tête.",
                    color = BeerColors.muted,
                    fontSize = 13.sp,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(10.dp))
                LinearProgressIndicator(
                    progress = { pct },
                    modifier = Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(999.dp)),
                    color = Gold,
                    trackColor = BeerColors.fieldBg
                )
            }
        },
        confirmButton = {
            Button(onClick = onDismiss, colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)) {
                Text("Continuer", color = Color.Black, fontWeight = FontWeight.Bold)
            }
        },
        containerColor = BeerColors.card
    )
}

@Composable
private fun RpgBadgeUnlockDialog(badge: RpgBadge, onDismiss: (Boolean) -> Unit) {
    val rarity = (badge.rarity ?: "common").lowercase()
    val rarityColor = when (rarity) {
        "legendary" -> LegendAmber
        "epic" -> BadgePurple
        "rare" -> RareBlue
        else -> BeerColors.muted
    }
    AlertDialog(
        onDismissRequest = { onDismiss(false) },
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text("BADGE · ${rarity.uppercase()}", color = rarityColor, fontWeight = FontWeight.ExtraBold, fontSize = 11.sp)
                Spacer(Modifier.height(8.dp))
                Text(badge.icon ?: "🏅", fontSize = 48.sp)
                Text(badge.name ?: "Badge", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 18.sp, textAlign = TextAlign.Center)
            }
        },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text(rarityLabelFr(badge.rarity), color = rarityColor, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                Spacer(Modifier.height(6.dp))
                (badge.lore ?: badge.hint)?.takeIf { it.isNotBlank() }?.let {
                    Text(it, color = BeerColors.muted, fontSize = 13.sp, textAlign = TextAlign.Center)
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    badge.unlockPhrase ?: "Un badge s’ajoute au grimoire.",
                    color = BeerColors.muted,
                    fontSize = 12.sp,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                    textAlign = TextAlign.Center
                )
            }
        },
        confirmButton = {
            Button(onClick = { onDismiss(false) }, colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent)) {
                Text("Super !", color = Color.Black, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = { onDismiss(true) }) {
                Text("Voir le grimoire", color = QuestBlue)
            }
        },
        containerColor = BeerColors.card
    )
}

@Composable
fun RpgBadgeDetailDialog(badge: RpgBadge, onDismiss: () -> Unit) {
    val rarity = (badge.rarity ?: "common").lowercase()
    val rarityColor = when (rarity) {
        "legendary" -> LegendAmber
        "epic" -> BadgePurple
        "rare" -> RareBlue
        else -> BeerColors.muted
    }
    val tgt = badge.target.coerceAtLeast(1)
    val pct = (badge.progress.toFloat() / tgt).coerceIn(0f, 1f)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text(badge.icon ?: "🏅", fontSize = 44.sp)
                Text(badge.name ?: "Badge", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 18.sp, textAlign = TextAlign.Center)
                Text(rarityLabelFr(badge.rarity), color = rarityColor, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
        },
        text = {
            Column(Modifier.fillMaxWidth()) {
                if (badge.earned) {
                    Text("✓ Obtenu", color = ExploreGreen, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    badge.earnedAt?.takeIf { it.isNotBlank() }?.let {
                        Text(it, color = BeerColors.muted, fontSize = 12.sp)
                    }
                } else {
                    LinearProgressIndicator(
                        progress = { pct },
                        modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(999.dp)),
                        color = if (badge.progress > 0) Gold else rarityColor,
                        trackColor = BeerColors.fieldBg
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${badge.progress} / $tgt · ${(pct * 100).toInt()}%",
                        color = BeerColors.muted,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                badge.lore?.takeIf { it.isNotBlank() }?.let {
                    Spacer(Modifier.height(10.dp))
                    Text("Lore", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    Text(it, color = BeerColors.text, fontSize = 13.sp)
                }
                badge.hint?.takeIf { it.isNotBlank() }?.let {
                    Spacer(Modifier.height(8.dp))
                    Text("Objectif", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    Text(it, color = BeerColors.text, fontSize = 13.sp)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Fermer", color = BeerColors.accent) }
        },
        containerColor = BeerColors.card
    )
}

@Composable
fun RpgAdminSheet(vm: AppViewModel) {
    var tab by remember { mutableIntStateOf(0) } // 0 joueurs, 1 feedback
    var players by remember { mutableStateOf<List<RpgAdminPlayer>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<RpgAdminPlayer?>(null) }
    var busy by remember { mutableStateOf(false) }
    var levelText by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    var reloadToken by remember { mutableIntStateOf(0) }

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

    LaunchedEffect(reloadToken) {
        loading = true
        error = null
        players = withContext(Dispatchers.IO) {
            try { vm.api.adminRpgPlayers() } catch (_: Exception) { emptyList() }
        }
        if (players.isEmpty()) error = "Aucun joueur ou accès refusé."
        loading = false
    }

    LaunchedEffect(tab, fbUnreadOnly, fbStatus, reloadToken) {
        if (tab != 1) return@LaunchedEffect
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
                Text(
                    if (unread > 0) "${players.size} joueurs · $unread feedback non lu(s)"
                    else "${players.size} aventurier(s)",
                    color = BeerColors.muted,
                    fontSize = 12.sp
                )
            }
            Text("↻", color = QuestBlue, modifier = Modifier.clickable { reload() }.padding(8.dp))
            Text("Fermer ✕", color = BeerColors.muted, modifier = Modifier.clickable { vm.closeSheet() }.padding(8.dp))
        }
        Spacer(Modifier.height(8.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("Joueurs", "Feedback").forEachIndexed { i, lab ->
                val active = tab == i
                val badge = if (i == 1 && (fbStats?.unread ?: 0) > 0) " ${(fbStats?.unread)}" else ""
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
                        fontSize = 13.sp
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
                        val borderC = if (p.dailySoftCapped) Gold.copy(alpha = 0.55f) else BeerColors.border
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(bottom = 8.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .border(1.dp, borderC, RoundedCornerShape(12.dp))
                                .background(BeerColors.card)
                                .clickable {
                                    selected = p
                                    levelText = p.level.toString()
                                }
                                .padding(12.dp)
                        ) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Column(Modifier.weight(1f)) {
                                    Text(name, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
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
                        }
                    }
                }
            }
            tab == 1 -> {
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
        val name = p.username.orEmpty()
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(name, color = BeerColors.text, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text("Nv ${p.level} · ${p.xp} XP · ${p.badgeCount} badges", color = BeerColors.muted, fontSize = 13.sp)
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
                                val ok = withContext(Dispatchers.IO) {
                                    vm.api.adminRpgPatchPlayer(name, mapOf("level" to lv))
                                }
                                busy = false
                                if (ok) {
                                    vm.showToast("Niveau $lv pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                                    selected = null
                                    reload()
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
                        listOf(-50, -10, 10, 50).forEach { d ->
                            OutlinedButton(
                                onClick = {
                                    busy = true
                                    scope.launch {
                                        val ok = withContext(Dispatchers.IO) {
                                            try { vm.api.adminRpgAdjustXp(name, d) } catch (_: Exception) { false }
                                        }
                                        busy = false
                                        if (ok) {
                                            vm.showToast("XP ${if (d > 0) "+" else ""}$d pour $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                                            selected = null
                                            reload()
                                        } else {
                                            vm.showToast("Échec XP", ToastPayload.Variant.ERROR)
                                        }
                                    }
                                },
                                enabled = !busy && name.isNotBlank()
                            ) {
                                Text(if (d > 0) "+$d" else "$d", color = BeerColors.text, fontSize = 12.sp)
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = {
                            busy = true
                            scope.launch {
                                val ok = withContext(Dispatchers.IO) {
                                    try { vm.api.adminRpgResetDaily(name) } catch (_: Exception) { false }
                                }
                                busy = false
                                if (ok) {
                                    vm.showToast("Reset journalier $name", ToastPayload.Variant.SUCCESS, label = "Beerquest")
                                    selected = null
                                    reload()
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
                }
            },
            confirmButton = {
                TextButton(onClick = { selected = null }) { Text("Fermer", color = BeerColors.muted) }
            },
            containerColor = BeerColors.card
        )
    }
}

@Composable
private fun FeedbackAdminCard(
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
