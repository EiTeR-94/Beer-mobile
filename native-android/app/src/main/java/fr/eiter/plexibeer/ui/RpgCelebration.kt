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
fun RpgIntroDialog(onDiscover: () -> Unit, onLater: () -> Unit) {
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
fun RpgLevelUpDialog(loot: RpgLoot, onDismiss: () -> Unit) {
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
fun RpgBadgeUnlockDialog(badge: RpgBadge, onDismiss: (Boolean) -> Unit) {
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
