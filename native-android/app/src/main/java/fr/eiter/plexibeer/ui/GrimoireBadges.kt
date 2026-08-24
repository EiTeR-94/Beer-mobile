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
fun ColumnScope.GrimoireBadges(state: RpgState, onBadge: (RpgBadge) -> Unit) {
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

fun rarityOrder(r: String?): Int = when ((r ?: "common").lowercase()) {
    "legendary" -> 3
    "epic" -> 2
    "rare" -> 1
    else -> 0
}

@Composable
fun LegendDot(color: Color, label: String) {
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
fun BadgeGroupSection(
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
fun BadgeGrid(list: List<RpgBadge>, onBadge: (RpgBadge) -> Unit = {}) {
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
fun BadgeProgressRow(b: RpgBadge) {
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
fun StyleChips(styles: List<String>) {
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
fun BadgeTile(b: RpgBadge) {
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
