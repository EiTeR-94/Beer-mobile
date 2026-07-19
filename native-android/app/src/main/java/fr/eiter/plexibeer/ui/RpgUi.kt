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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import fr.eiter.plexibeer.AppViewModel
import fr.eiter.plexibeer.RpgBadge
import fr.eiter.plexibeer.RpgProfile
import fr.eiter.plexibeer.RpgQuest
import fr.eiter.plexibeer.RpgState
import fr.eiter.plexibeer.displayIcon
import fr.eiter.plexibeer.rarityLabelFr
import fr.eiter.plexibeer.ui.theme.BeerColors

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
    val tabs = listOf("Accueil", "Quêtes", "Badges", "Atlas")

    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
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
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        when (tab) {
            0 -> GrimoireHome(state)
            1 -> GrimoireQuests(state)
            2 -> GrimoireBadges(state)
            3 -> GrimoireAtlas(state, vm)
        }
    }
}

@Composable
private fun ColumnScope.GrimoireHome(state: RpgState) {
    val p = state.profile ?: return
    val scroll = rememberScrollState()
    Column(Modifier.verticalScroll(scroll)) {
        BqHudBar(p) {}
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            StatTile("🔥", "${p.streakDays}", "Streak", Modifier.weight(1f))
            StatTile("⚡", "${p.dailyXp}/${p.dailySoftCap}", "XP jour", Modifier.weight(1f))
            StatTile("🍺", "${state.atlas?.totalCheckins ?: 0}", "Check-ins", Modifier.weight(1f))
            StatTile("📜", "${state.quests?.active?.size ?: 0}", "Quêtes", Modifier.weight(1f))
        }
        Spacer(Modifier.height(14.dp))
        SectionTitle("📜 Quêtes en cours")
        val active = state.quests?.active.orEmpty().take(3)
        if (active.isEmpty()) {
            Text("Aucune quête active.", color = BeerColors.muted, fontSize = 12.sp)
        } else {
            active.forEach { QuestCard(it) }
        }
        val next = state.nextBadges
        if (next.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            SectionTitle("🏅 Prochains badges")
            next.forEach { BadgeProgressRow(it) }
        }
        state.phrase?.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(12.dp))
            SectionTitle("🗣️ Le tavernier")
            Text(it, color = BeerColors.muted, fontSize = 13.sp, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic)
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ColumnScope.GrimoireQuests(state: RpgState) {
    val scroll = rememberScrollState()
    val q = state.quests
    Column(Modifier.verticalScroll(scroll)) {
        SectionTitle("☀️ Journalières")
        val dailies = (q?.active.orEmpty().filter { it.kind == "daily" } + q?.doneToday.orEmpty())
        if (dailies.isEmpty()) Text("Rien pour le moment.", color = BeerColors.muted, fontSize = 12.sp)
        else dailies.forEach { QuestCard(it) }
        Spacer(Modifier.height(12.dp))
        SectionTitle("📅 Hebdomadaires")
        val weeklies = (q?.active.orEmpty().filter { it.kind == "weekly" } + q?.doneWeekly.orEmpty())
        if (weeklies.isEmpty()) Text("Aucune.", color = BeerColors.muted, fontSize = 12.sp)
        else weeklies.forEach { QuestCard(it) }
        Spacer(Modifier.height(12.dp))
        SectionTitle("📖 Histoire")
        val story = q?.active.orEmpty().filter { it.kind == "story" }
        if (story.isEmpty()) Text("Chapitres à venir…", color = BeerColors.muted, fontSize = 12.sp)
        else story.forEach { QuestCard(it) }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ColumnScope.GrimoireBadges(state: RpgState) {
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
        BadgeGroupSection("En cours", "⚔️", inProgress)
        BadgeGroupSection("Commun", "⚪", byRarity["common"].orEmpty())
        BadgeGroupSection("Rare", "🔵", byRarity["rare"].orEmpty())
        BadgeGroupSection("Épique", "🟣", byRarity["epic"].orEmpty())
        BadgeGroupSection("Légendaire", "🟡", byRarity["legendary"].orEmpty())
        BadgeGroupSection("Obtenus", "✅", earnedList)
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
private fun BadgeGroupSection(title: String, ico: String, list: List<RpgBadge>) {
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
        BadgeGrid(list)
    }
}

@Composable
private fun BadgeGrid(list: List<RpgBadge>) {
    val rows = list.chunked(3)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                row.forEach { b ->
                    Box(Modifier.weight(1f)) { BadgeTile(b) }
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
private fun ColumnScope.GrimoireAtlas(state: RpgState, vm: AppViewModel) {
    val scroll = rememberScrollState()
    val a = state.atlas
    val p = state.profile
    Column(Modifier.verticalScroll(scroll)) {
        SectionTitle("🗺️ Collection")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            StatTile("🎨", "${a?.stylesCount ?: 0}", "Styles", Modifier.weight(1f))
            StatTile("🌿", "${a?.hopsCount ?: 0}", "Houblons", Modifier.weight(1f))
            StatTile("🏭", "${a?.breweriesCount ?: 0}", "Brasseries", Modifier.weight(1f))
            StatTile("📷", "${a?.photos ?: 0}", "Photos", Modifier.weight(1f))
        }
        Spacer(Modifier.height(14.dp))
        SectionTitle("⚔️ Classes")
        Text(
            "Une seule classe à la fois. Si la bière colle : +2 XP et bonus d’habitude.",
            color = BeerColors.muted,
            fontSize = 12.sp
        )
        Spacer(Modifier.height(8.dp))
        val equipped = p?.classKey
        val aff = state.classAffinity.orEmpty()
        state.classes.forEach { c ->
            val key = c.key.orEmpty()
            val isOn = key == equipped
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(
                        1.dp,
                        if (isOn) BeerColors.accent else BeerColors.border,
                        RoundedCornerShape(12.dp)
                    )
                    .background(if (isOn) BeerColors.accent.copy(alpha = 0.12f) else BeerColors.card)
                    .clickable(enabled = !isOn && key.isNotBlank()) {
                        vm.equipRpgClass(key)
                    }
                    .padding(10.dp)
            ) {
                Text(
                    "${c.icon ?: "🍺"} ${c.name ?: key}",
                    fontWeight = FontWeight.Bold,
                    color = BeerColors.text,
                    fontSize = 14.sp
                )
                c.blurb?.let {
                    Text(it, color = BeerColors.muted, fontSize = 12.sp)
                }
                Text(
                    if (isOn) "Équipée · habitude ${aff[key] ?: 0}%"
                    else "Toucher pour équiper · habitude ${aff[key] ?: 0}%",
                    color = if (isOn) Gold else QuestBlue,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Spacer(Modifier.height(24.dp))
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
    val done = q.status == "done"
    val pct = if (q.target > 0) (q.progress.toFloat() / q.target).coerceIn(0f, 1f) else 0f
    Column(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp)
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, if (done) Color(0xFF34D399) else QuestBlue, RoundedCornerShape(12.dp))
            .background(BeerColors.card)
            .padding(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f)) {
                Text((q.kind ?: "quête").uppercase(), color = QuestBlue, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(q.title ?: "—", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            Text("+${q.rewardXp} XP", color = Gold, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        }
        q.description?.let {
            Text(it, color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(if (done) "Terminée" else "En cours", color = if (done) Color(0xFF34D399) else QuestBlue, fontSize = 11.sp)
            Text("${q.progress}/${q.target} · ${(pct * 100).toInt()}%", color = BeerColors.muted, fontSize = 11.sp)
        }
        LinearProgressIndicator(
            progress = { pct },
            modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(999.dp)),
            color = if (done) Color(0xFF34D399) else QuestBlue,
            trackColor = BeerColors.fieldBg
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
