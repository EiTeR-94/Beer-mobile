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
@OptIn(ExperimentalLayoutApi::class)
fun ColumnScope.GrimoireAtlas(state: RpgState, vm: AppViewModel) {
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
fun bestAffinityKey(aff: Map<String, Int>, classes: List<RpgClassInfo>): String? {
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

fun habitLabel(aff: Int): String = when {
    aff >= 70 -> "+3 XP d’habitude"
    aff >= 50 -> "+2 XP d’habitude"
    aff >= 25 -> "+1 XP d’habitude"
    else -> "pas encore d’habitude (+0)"
}

/** Carte classe Atlas — parité iOS ClassCardView. */
@Composable
fun ClassCard(
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
