package fr.eiter.plexibeer.ui

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume



@Composable
fun GallerySheet(vm: AppViewModel) {
    val api = vm.api
    var items by remember { mutableStateOf(listOf<CheckinItem>()) }
    var styles by remember { mutableStateOf(listOf<StyleOption>()) }
    var filterStyle by remember { mutableStateOf("") }
    var filterRating by remember { mutableFloatStateOf(0f) }
    var filterPeriod by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var offlineHint by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<CheckinItem?>(null) }
    val cache = vm.listCache
    val scope = rememberCoroutineScope()

    suspend fun reload() {
        loading = true
        try {
            styles = try {
                api.styles().also { if (it.isNotEmpty()) cache.saveStyles(it) }
            } catch (_: Exception) {
                cache.loadStyles()
            }
            val live = api.checkins(
                style = filterStyle,
                minRating = filterRating.toDouble(),
                period = filterPeriod,
                limit = 100,
                offset = 0
            )
            if (filterStyle.isEmpty() && filterRating <= 0f && filterPeriod.isEmpty()) {
                cache.saveCheckins(live)
            }
            items = live.filter { !it.photoURL.isNullOrBlank() }
            offlineHint = null
            vm.prewarmRecentPhotos()
        } catch (_: Exception) {
            val cached = cache.loadCheckins().filter { !it.photoURL.isNullOrBlank() }
            items = cached
            offlineHint = if (cached.isEmpty()) {
                "Hors ligne — aucune photo en cache"
            } else {
                "Hors ligne — galerie en cache"
            }
        }
        loading = false
    }

    LaunchedEffect(Unit) {
        val cached = cache.loadCheckins().filter { !it.photoURL.isNullOrBlank() }
        if (cached.isNotEmpty()) items = cached
        reload()
    }
    LaunchedEffect(filterStyle, filterRating, filterPeriod) {
        if (!loading || items.isNotEmpty()) reload()
    }

    SheetScaffold("Galerie photos", onClose = { vm.closeSheet() }) {
        offlineHint?.let {
            Text(it, color = BeerColors.accent, fontSize = 12.sp, modifier = Modifier.padding(bottom = 6.dp))
        }
        BeerHistoryFiltersRow(
            filterStyle = filterStyle,
            filterRating = filterRating,
            filterPeriod = filterPeriod,
            styles = styles,
            onStyle = { filterStyle = it },
            onRating = { filterRating = it },
            onPeriod = { filterPeriod = it },
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${items.size} photos", color = BeerColors.muted, fontSize = 12.sp, modifier = Modifier.weight(1f))
            if (filterStyle.isNotEmpty() || filterRating > 0 || filterPeriod.isNotEmpty()) {
                TextButton(onClick = {
                    filterStyle = ""; filterRating = 0f; filterPeriod = ""
                }) {
                    Text("Réinit. filtres", color = BeerColors.accent, fontSize = 12.sp)
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        if (loading && items.isEmpty()) {
            CircularProgressIndicator(color = BeerColors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
        } else if (items.isEmpty()) {
            BeerEmptyState("📷", "Aucune photo", "Les dégustations avec photo apparaîtront ici.")
        } else {
            // Grille 3 colonnes (parité iOS LazyVGrid)
            val cols = 3
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(1f, fill = true)) {
                items(items.chunked(cols), key = { row -> row.joinToString("-") { it.id.toString() } }) { row ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        row.forEach { item ->
                            Column(
                                Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable {
                                        selected = item
                                    }
                            ) {
                                BeerAuthImage(
                                    path = item.photoURL,
                                    api = api,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(10.dp))
                                )
                                Text(
                                    item.beerName,
                                    color = BeerColors.text,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 2,
                                    modifier = Modifier.padding(top = 3.dp)
                                )
                                Text(
                                    "★ ${formatRating(item.rating)}",
                                    color = BeerColors.accent,
                                    fontSize = 10.sp
                                )
                            }
                        }
                        // pad empty cells
                        repeat(cols - row.size) {
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }

    selected?.let { item ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(item.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    BeerAuthImage(
                        path = item.photoURL,
                        api = api,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp)
                            .clip(RoundedCornerShape(12.dp))
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${item.brewery ?: "—"} · ★ ${formatRating(item.rating)}",
                        color = BeerColors.muted,
                        fontSize = 13.sp
                    )
                    item.comment?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.height(6.dp))
                        Text("« $it »", color = BeerColors.text, fontSize = 13.sp)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    selected = null
                    vm.selectedCheckin = item
                    vm.openSheet(BeerSheet.DETAIL)
                }) { Text("Voir fiche", color = BeerColors.accent) }
            },
            dismissButton = {
                TextButton(onClick = { selected = null }) { Text("Fermer", color = BeerColors.muted) }
            },
            containerColor = BeerColors.card
        )
    }
}
