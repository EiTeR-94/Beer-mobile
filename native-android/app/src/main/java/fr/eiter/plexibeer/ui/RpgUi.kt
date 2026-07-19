package fr.eiter.plexibeer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(
                1.dp,
                if (master) Gold.copy(alpha = 0.55f) else BeerColors.border,
                RoundedCornerShape(12.dp)
            )
            .background(
                if (master) Color(0xFF78350F).copy(alpha = 0.35f)
                else BeerColors.card
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(BeerColors.fieldBg)
                    .border(1.dp, if (master) Gold else BeerColors.accent, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(profile.displayIcon(), fontSize = 18.sp)
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
                        color = Gold,
                        fontWeight = FontWeight.ExtraBold,
                        fontSize = 13.sp
                    )
                }
                val sub = buildList {
                    add("Nv ${profile.level}")
                    profile.classInfo?.name?.let { add(it) }
                    profile.titleBand?.name?.takeIf { !master }?.let { add(it) }
                }.joinToString(" · ")
                Text(sub, color = BeerColors.muted, fontSize = 11.sp, maxLines = 1)
            }
        }
        Spacer(Modifier.height(6.dp))
        LinearProgressIndicator(
            progress = { pct },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(999.dp)),
            color = if (master) Gold else BeerColors.accent,
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
    val earned = badges.count { it.earned }
    val total = badges.size.coerceAtLeast(1)
    Text(
        "$earned / ${badges.size} badges · ${(earned * 100 / total)}%",
        color = BeerColors.muted,
        fontSize = 12.sp
    )
    Spacer(Modifier.height(8.dp))
    // weight(1f) : occupe tout l’espace restant du grimoire et scrolle.
    // (avant : height(420.dp) → ~2/3 d’écran puis fond vide, badges coupés)
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        contentPadding = PaddingValues(bottom = 28.dp),
        modifier = Modifier
            .weight(1f)
            .fillMaxWidth()
    ) {
        items(
            badges.sortedWith(
                compareBy(
                    { it.earned },
                    { -(it.progress.toDouble() / (it.target.coerceAtLeast(1))) }
                )
            )
        ) { b ->
            BadgeTile(b)
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
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(
                1.dp,
                when {
                    b.earned -> BadgePurple
                    b.progress > 0 -> Gold.copy(alpha = 0.5f)
                    else -> BeerColors.border
                },
                RoundedCornerShape(12.dp)
            )
            .background(BeerColors.card)
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(b.icon ?: "🏅", fontSize = 22.sp)
        Text(
            b.name ?: "—",
            color = BeerColors.text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
        Text(rarityLabelFr(b.rarity), color = BeerColors.muted, fontSize = 9.sp)
        Text(
            if (b.earned) "✓ Obtenu" else "${b.progress}/$tgt",
            color = if (b.earned) Color(0xFF34D399) else BeerColors.muted,
            fontSize = 10.sp
        )
        if (!b.earned) {
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { pct },
                modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(999.dp)),
                color = BadgePurple,
                trackColor = BeerColors.fieldBg
            )
        }
    }
}
