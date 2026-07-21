package fr.eiter.plexibeer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import fr.eiter.plexibeer.BeerAPI
import fr.eiter.plexibeer.BeerProduct
import fr.eiter.plexibeer.StyleOption
import fr.eiter.plexibeer.ImageCache
import fr.eiter.plexibeer.NetworkStatus
import fr.eiter.plexibeer.ToastPayload
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun BeerPrimaryButton(
    title: String,
    enabled: Boolean = true,
    busy: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(12.dp)
    Button(
        onClick = onClick,
        enabled = enabled && !busy,
        modifier = modifier.fillMaxWidth().height(48.dp),
        shape = shape,
        colors = ButtonDefaults.buttonColors(
            containerColor = BeerColors.accent,
            contentColor = BeerColors.btnPrimaryText,
            disabledContainerColor = BeerColors.accent.copy(alpha = 0.4f)
        )
    ) {
        if (busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = BeerColors.btnPrimaryText
            )
            Spacer(Modifier.width(8.dp))
        }
        Text(title, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun BeerSecondaryButton(
    title: String,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth().height(44.dp),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = BeerColors.text),
        border = ButtonDefaults.outlinedButtonBorder.copy(
            brush = Brush.linearGradient(listOf(BeerColors.border, BeerColors.border))
        )
    ) {
        Text(title, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun BeerGhostButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            title,
            color = BeerColors.text,
            fontSize = 12.8.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * Empêche les clics de traverser l’overlay vers le HUD / wizard en dessous
 * (sinon un tap dans le vide d’un sheet ouvre le Grimoire).
 */
fun Modifier.consumeClicks(): Modifier = composed {
    clickable(
        indication = null,
        interactionSource = remember { MutableInteractionSource() },
        onClick = {}
    )
}

/** Sélecteur compact Style / Note / Période (parité iOS BeerSelectField). */
@Composable
fun BeerSelectField(
    label: String,
    value: String,
    options: List<Pair<String, String>>,
    onChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val currentLabel = options.firstOrNull { it.first == value }?.second
        ?: options.firstOrNull()?.second
        ?: "—"
    Column(modifier = modifier) {
        Text(
            label,
            color = BeerColors.muted,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
        Spacer(Modifier.height(3.dp))
        Box {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                    .background(BeerColors.fieldBg)
                    .clickable { expanded = true }
                    .padding(horizontal = 6.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    currentLabel,
                    color = BeerColors.text,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text("▾", color = BeerColors.muted, fontSize = 10.sp)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (key, lab) ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                lab,
                                color = if (key == value) BeerColors.accent else BeerColors.text,
                                fontWeight = if (key == value) FontWeight.Bold else FontWeight.Normal,
                                fontSize = 13.sp
                            )
                        },
                        onClick = {
                            onChange(key)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

/** Filtres historique / galerie — parité iOS BeerHistoryFiltersRow (API week/month/year). */
@Composable
fun BeerHistoryFiltersRow(
    filterStyle: String,
    filterRating: Float,
    filterPeriod: String,
    styles: List<StyleOption>,
    onStyle: (String) -> Unit,
    onRating: (Float) -> Unit,
    onPeriod: (String) -> Unit,
) {
    val styleOpts = buildList {
        add("" to "Tous styles")
        styles.filter { it.value.isNotBlank() }.forEach {
            add(it.value to it.label.ifBlank { it.value })
        }
    }
    val ratingOpts = listOf(
        "0" to "Toutes",
        "0.25" to "0.25 ★+",
        "0.5" to "0.5 ★+",
        "1" to "1 ★+",
        "2" to "2 ★+",
        "3" to "3 ★+",
        "4" to "4 ★+",
        "5" to "5 ★+",
    )
    val periodOpts = listOf(
        "" to "Tout",
        "week" to "7 jours",
        "month" to "30 jours",
        "year" to "1 an",
    )
    val ratingKey = when {
        filterRating <= 0f -> "0"
        filterRating == filterRating.toInt().toFloat() -> filterRating.toInt().toString()
        else -> filterRating.toString()
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        BeerSelectField(
            label = "Style",
            value = filterStyle,
            options = styleOpts,
            onChange = onStyle,
            modifier = Modifier.weight(1f)
        )
        BeerSelectField(
            label = "Note min",
            value = ratingKey,
            options = ratingOpts,
            onChange = { onRating(it.toFloatOrNull() ?: 0f) },
            modifier = Modifier.weight(1f)
        )
        BeerSelectField(
            label = "Période",
            value = filterPeriod,
            options = periodOpts,
            onChange = onPeriod,
            modifier = Modifier.weight(1f)
        )
    }
}

/** Filtres idées cadeaux — parité iOS BeerGiftsFiltersRow. */
@Composable
fun BeerGiftsFiltersRow(
    search: String,
    filterStyle: String,
    minRating: Float,
    styleOptions: List<String>,
    onSearch: (String) -> Unit,
    onStyle: (String) -> Unit,
    onRating: (Float) -> Unit,
) {
    val styles = buildList {
        add("" to "Tous styles")
        styleOptions.forEach { add(it to it) }
    }
    val ratingOpts = listOf(
        "0" to "Toutes",
        "4" to "≥4★",
        "4.5" to "≥4.5★",
        "5" to "=5★",
    )
    val ratingKey = when {
        minRating >= 5f -> "5"
        minRating >= 4.5f -> "4.5"
        minRating >= 4f -> "4"
        else -> "0"
    }
    Column(Modifier.fillMaxWidth()) {
        Text("Recherche", color = BeerColors.muted, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(3.dp))
        OutlinedTextField(
            value = search,
            onValueChange = onSearch,
            placeholder = { Text("nom, brasserie…", color = BeerColors.muted, fontSize = 12.sp) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = BeerColors.text,
                unfocusedTextColor = BeerColors.text,
                focusedBorderColor = BeerColors.accent,
                unfocusedBorderColor = BeerColors.border,
                cursorColor = BeerColors.accent,
                focusedContainerColor = BeerColors.fieldBg,
                unfocusedContainerColor = BeerColors.fieldBg,
            ),
            shape = RoundedCornerShape(8.dp)
        )
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            BeerSelectField(
                label = "Style",
                value = filterStyle,
                options = styles,
                onChange = onStyle,
                modifier = Modifier.weight(1f)
            )
            BeerSelectField(
                label = "Note min",
                value = ratingKey,
                options = ratingOpts,
                onChange = { onRating(it.toFloatOrNull() ?: 0f) },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/** Étoiles + note (détail check-in). */
@Composable
fun BeerStarRating(rating: Double, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // Approximation visuelle (5 étoiles + note chiffrée)
        val filled = (rating / 5.0 * 5).toInt().coerceIn(0, 5)
        Text(
            "★".repeat(filled) + "☆".repeat(5 - filled),
            color = BeerColors.star,
            fontSize = 16.sp
        )
        Text(
            formatRating(rating),
            color = BeerColors.accent,
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp
        )
    }
}

@Composable
fun BeerField(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    placeholder: String = "",
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(label, color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.padding(bottom = 4.dp))
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            placeholder = { Text(placeholder, color = BeerColors.muted.copy(alpha = 0.6f)) },
            singleLine = singleLine,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = BeerColors.text,
                unfocusedTextColor = BeerColors.text,
                focusedBorderColor = BeerColors.accent,
                unfocusedBorderColor = BeerColors.border,
                cursorColor = BeerColors.accent,
                focusedContainerColor = BeerColors.fieldBg,
                unfocusedContainerColor = BeerColors.fieldBg
            ),
            shape = RoundedCornerShape(10.dp)
        )
    }
}

@Composable
fun BeerLead(text: String) {
    Text(
        text,
        color = BeerColors.muted,
        fontSize = 14.sp,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    )
}

@Composable
fun BeerCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BeerColors.card)
            .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
            .padding(14.dp),
        content = content
    )
}

@Composable
fun BeerPreviewCard(product: BeerProduct) {
    BeerCard {
        Text(product.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(4.dp))
        Text(
            listOfNotNull(
                product.brewery.takeIf { it.isNotBlank() && it != "—" },
                product.displayStyle.takeIf { it.isNotBlank() },
                product.abv?.let { String.format("%.1f%%", it) },
            ).joinToString(" · "),
            color = BeerColors.muted,
            fontSize = 13.sp
        )
        if (product.barcode.isNotBlank()) {
            Text("EAN ${product.barcode}", color = BeerColors.muted, fontSize = 12.sp)
        }
        // Parité web + iOS : résumé Untappd (description FR + note) sous la méta
        if (product.summary.isNotBlank()) {
            Spacer(Modifier.height(8.dp))
            Text(
                product.summary,
                color = BeerColors.text,
                fontSize = 13.sp,
                lineHeight = 18.sp,
            )
        }
    }
}

@Composable
fun BeerStepNav(step: Int, onStep: (Int) -> Unit) {
    // Navigation libre 1↔2↔3 (parité iOS BeerStepNav — pas de blocage Photo→Note)
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        listOf(1 to "1 Bière", 2 to "2 Photo", 3 to "3 Note").forEach { (s, label) ->
            val current = s == step
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (current) BeerColors.accent else BeerColors.card)
                    .border(1.dp, if (current) BeerColors.accent else BeerColors.border, RoundedCornerShape(999.dp))
                    .clickable { onStep(s) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    label,
                    color = if (current) BeerColors.btnPrimaryText else BeerColors.muted,
                    fontSize = 11.5.sp,
                    fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
    }
}

@Composable
fun UntappdRatingSlider(
    rating: Float,
    onChange: (Float) -> Unit,
    onTick: (() -> Unit)? = null
) {
    var lastBucket by remember { mutableIntStateOf((rating * 4).toInt()) }
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Note", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
            Text(String.format("%.2f / 5", rating), color = BeerColors.accent, fontWeight = FontWeight.Bold)
        }
        Slider(
            value = rating,
            onValueChange = { v ->
                val snapped = (kotlin.math.round(v * 4f) / 4f).coerceIn(0.25f, 5f)
                val bucket = (snapped * 4).toInt()
                if (bucket != lastBucket) {
                    lastBucket = bucket
                    onTick?.invoke()
                }
                onChange(snapped)
            },
            valueRange = 0.25f..5f,
            steps = 18,
            colors = SliderDefaults.colors(
                thumbColor = BeerColors.star,
                activeTrackColor = BeerColors.star,
                inactiveTrackColor = BeerColors.starOff
            )
        )
    }
}

@Composable
fun TagChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) BeerColors.accent.copy(alpha = 0.25f) else BeerColors.bg
    val border = if (selected) BeerColors.accent else BeerColors.border
    val fg = if (selected) BeerColors.accent else BeerColors.text
    Text(
        label,
        color = fg,
        fontSize = 12.8.sp,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    )
}

@Composable
fun FlavorTagGrid(
    title: String,
    tags: List<String>,
    selected: Set<String>,
    maxCount: Int,
    onToggle: (String) -> Unit
) {
    Column {
        Text(title, color = BeerColors.text, fontWeight = FontWeight.SemiBold, fontSize = 13.6.sp)
        Spacer(Modifier.height(8.dp))
        FlowRowWrap {
            tags.forEach { tag ->
                val isOn = tag in selected
                TagChip(tag, isOn) {
                    if (isOn || selected.size < maxCount) onToggle(tag)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FlowRowWrap(content: @Composable () -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        content = { content() }
    )
}

@Composable
fun CustomTagInput(
    placeholder: String,
    input: String,
    onInput: (String) -> Unit,
    onAdd: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        OutlinedTextField(
            value = input,
            onValueChange = onInput,
            placeholder = { Text(placeholder, color = BeerColors.muted.copy(alpha = 0.6f)) },
            singleLine = true,
            modifier = Modifier.weight(1f),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = BeerColors.text,
                unfocusedTextColor = BeerColors.text,
                focusedBorderColor = BeerColors.accent,
                unfocusedBorderColor = BeerColors.border,
                cursorColor = BeerColors.accent,
                focusedContainerColor = BeerColors.fieldBg,
                unfocusedContainerColor = BeerColors.fieldBg
            ),
            shape = RoundedCornerShape(10.dp)
        )
        Button(
            onClick = onAdd,
            colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent, contentColor = BeerColors.btnPrimaryText)
        ) { Text("+") }
    }
}

@Composable
fun NetworkStatusBar(status: NetworkStatus, pending: Int, latencyMs: Long?) {
    if (status == NetworkStatus.ONLINE && pending == 0) return
    val color = when (status) {
        NetworkStatus.ONLINE -> BeerColors.ok
        NetworkStatus.SERVER_UNREACHABLE -> BeerColors.accent
        NetworkStatus.OFFLINE -> BeerColors.error
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(color.copy(alpha = 0.15f))
            .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(status.label, color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        if (pending > 0) {
            Spacer(Modifier.width(8.dp))
            Text("· $pending en attente", color = BeerColors.muted, fontSize = 12.sp)
        }
        if (latencyMs != null && status == NetworkStatus.ONLINE) {
            Spacer(Modifier.weight(1f))
            Text("${latencyMs}ms", color = BeerColors.muted, fontSize = 11.sp)
        }
    }
}

/**
 * Bannière toast type iOS 4.2.7 — haut d'écran, non-modale, fermable.
 * Pas de voile noir plein écran.
 */
@Composable
fun ToastOverlay(toast: ToastPayload?, onDismiss: () -> Unit = {}) {
    if (toast == null) return
    val accent = when (toast.variant) {
        ToastPayload.Variant.SUCCESS -> BeerColors.ok
        ToastPayload.Variant.WARN, ToastPayload.Variant.DUPLICATE -> BeerColors.accent
        ToastPayload.Variant.ERROR -> BeerColors.error
        ToastPayload.Variant.INFO -> BeerColors.accent
    }
    val icon = when (toast.variant) {
        ToastPayload.Variant.SUCCESS -> "✓"
        ToastPayload.Variant.WARN -> "!"
        ToastPayload.Variant.ERROR -> "✕"
        ToastPayload.Variant.DUPLICATE -> "🍺"
        ToastPayload.Variant.INFO -> "ℹ"
    }
    val defaultLabel = when (toast.variant) {
        ToastPayload.Variant.SUCCESS -> "Succès"
        ToastPayload.Variant.WARN -> "Attention"
        ToastPayload.Variant.ERROR -> "Erreur"
        ToastPayload.Variant.DUPLICATE -> "Déjà dégustée"
        ToastPayload.Variant.INFO -> "Info"
    }
    val label = toast.label ?: defaultLabel

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 8.dp),
        contentAlignment = Alignment.TopCenter
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(BeerColors.card)
                .border(1.dp, accent.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                .clickable(onClick = onDismiss)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(accent.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Text(icon, color = accent, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    label.uppercase(),
                    color = accent,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.6.sp
                )
                Spacer(Modifier.height(3.dp))
                Text(toast.message, color = BeerColors.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                toast.detail?.takeIf { it.isNotBlank() }?.let {
                    Spacer(Modifier.height(3.dp))
                    Text(it, color = BeerColors.muted, fontSize = 12.5.sp)
                }
            }
            Spacer(Modifier.width(8.dp))
            Box(
                Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(BeerColors.bg.copy(alpha = 0.65f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center
            ) {
                Text("×", color = BeerColors.muted, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }
    }
}

@Composable
fun BeerEmptyState(icon: String, title: String, subtitle: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(icon, fontSize = 36.sp)
        Spacer(Modifier.height(8.dp))
        Text(title, color = BeerColors.text, fontWeight = FontWeight.Bold)
        Text(subtitle, color = BeerColors.muted, fontSize = 13.sp)
    }
}

/**
 * Photos serveur avec cache disque offline.
 * 1) cache local  2) download + store  3) fallback emoji
 */
@Composable
fun BeerAuthImage(
    path: String?,
    api: BeerAPI,
    modifier: Modifier = Modifier,
    contentDescription: String? = null
) {
    val context = LocalContext.current
    val imageCache = remember(context) { ImageCache.getInstance(context) }
    var bytes by remember(path) { mutableStateOf<ByteArray?>(null) }
    var failed by remember(path) { mutableStateOf(false) }

    LaunchedEffect(path) {
        bytes = null
        failed = false
        if (path.isNullOrBlank()) {
            failed = true
            return@LaunchedEffect
        }
        // External URL (Untappd labels) — Coil ; pas de cookie homelab
        if (path.startsWith("http://") || path.startsWith("https://")) {
            return@LaunchedEffect
        }
        // Cache d'abord (bars sans réseau)
        val cached = withContext(Dispatchers.IO) { imageCache.get(path) }
        if (cached != null) {
            bytes = cached
            return@LaunchedEffect
        }
        try {
            val downloaded = withContext(Dispatchers.IO) { api.downloadAsset(path) }
            withContext(Dispatchers.IO) { imageCache.put(path, downloaded) }
            bytes = downloaded
        } catch (_: Exception) {
            failed = true
        }
    }

    when {
        !path.isNullOrBlank() && (path.startsWith("http://") || path.startsWith("https://")) -> {
            AsyncImage(
                model = path,
                contentDescription = contentDescription,
                modifier = modifier,
                contentScale = ContentScale.Crop
            )
        }
        bytes != null -> {
            AsyncImage(
                model = bytes,
                contentDescription = contentDescription,
                modifier = modifier,
                contentScale = ContentScale.Crop
            )
        }
        failed || path.isNullOrBlank() -> {
            Box(
                modifier = modifier.background(BeerColors.photoBg),
                contentAlignment = Alignment.Center
            ) {
                Text("🍺", fontSize = 22.sp)
            }
        }
        else -> {
            Box(modifier = modifier.background(BeerColors.photoBg), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(20.dp), color = BeerColors.accent, strokeWidth = 2.dp)
            }
        }
    }
}

fun formatRating(r: Double): String = String.format("%.2f", r)

fun formatDate(iso: String?): String {
    if (iso.isNullOrBlank()) return "—"
    // Keep simple: show date part
    return iso.take(10)
}
