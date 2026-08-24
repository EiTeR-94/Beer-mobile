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

/** Hero de tab grimoire (parité iOS tabHero). */
@Composable
fun TabHero(
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
