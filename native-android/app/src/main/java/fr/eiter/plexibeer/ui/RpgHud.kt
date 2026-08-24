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
