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
fun GiftsSheet(vm: AppViewModel) {
    val api = vm.api
    var gifts by remember { mutableStateOf(listOf<GiftIdea>()) }
    var users by remember { mutableStateOf(listOf<CoupleStats.CoupleUser>()) }
    var partner by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var filterStyle by remember { mutableStateOf("") }
    var minRating by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }

    val cache = vm.listCache
    LaunchedEffect(Unit) {
        cache.loadCouple()?.let { cached ->
            gifts = cached.giftIdeas.orEmpty()
            users = cached.users.orEmpty()
            partner = users.firstOrNull { it.username != vm.user }?.username.orEmpty()
        }
        try {
            val data = api.coupleStats()
            gifts = data.giftIdeas.orEmpty()
            users = data.users.orEmpty()
            partner = users.firstOrNull { it.username != vm.user }?.username.orEmpty()
            cache.saveCouple(data)
            error = null
        } catch (e: Exception) {
            if (gifts.isEmpty()) {
                error = e.message ?: "Hors ligne — pas de cache cadeaux"
            } else {
                error = "Hors ligne — idées cadeaux en cache"
            }
        }
        loading = false
    }

    val styleOptions = remember(gifts) {
        gifts.mapNotNull { it.style }.filter { it.isNotEmpty() }.distinct().sorted()
    }
    val filtered = gifts.filter { g ->
        if (minRating > 0) {
            if (minRating >= 5f && (g.rating ?: 0.0) < 4.99) return@filter false
            else if ((g.rating ?: 0.0) < minRating) return@filter false
        }
        if (filterStyle.isNotEmpty() && g.style != filterStyle) return@filter false
        if (search.isNotEmpty()) {
            val hay = "${g.beerName} ${g.brewery.orEmpty()} ${g.style.orEmpty()}".lowercase()
            if (!hay.contains(search.lowercase())) return@filter false
        }
        true
    }

    SheetScaffold(
        title = if (partner.isEmpty()) "Idées cadeaux" else "Idées cadeaux — $partner",
        onClose = { vm.closeSheet() }
    ) {
        error?.let { Text(it, color = BeerColors.error) }
        if (loading) {
            CircularProgressIndicator(color = BeerColors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
            return@SheetScaffold
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            users.forEach { u ->
                Column(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(BeerColors.card)
                        .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
                        .padding(9.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(if (u.username == vm.user) "Toi" else u.username, color = BeerColors.muted, fontSize = 11.sp)
                    Text("${u.total}", color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text("dégust.", color = BeerColors.muted, fontSize = 11.sp)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        BeerGiftsFiltersRow(
            search = search,
            filterStyle = filterStyle,
            minRating = minRating,
            styleOptions = styleOptions,
            onSearch = { search = it },
            onStyle = { filterStyle = it },
            onRating = { minRating = it },
        )
        Spacer(Modifier.height(8.dp))
        if (filtered.isEmpty()) {
            Text("Aucune idée cadeau avec ces filtres.", color = BeerColors.muted, modifier = Modifier.padding(24.dp))
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f, fill = true)) {
                items(filtered, key = { it.id }) { g ->
                    BeerCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            BeerAuthImage(
                                path = ServerSettings.giftPhotoPath(g.photoPath),
                                api = api,
                                modifier = Modifier.size(88.dp).clip(RoundedCornerShape(10.dp))
                            )
                            Column(Modifier.weight(1f)) {
                                Text(g.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                                Text(
                                    "${g.brewery ?: "—"} · ${g.style ?: "?"}",
                                    color = BeerColors.muted,
                                    fontSize = 12.sp
                                )
                                g.rating?.let {
                                    Text("★ ${formatRating(it)}", color = BeerColors.accent, fontSize = 12.sp)
                                }
                                Text("Notée par ${g.likedBy ?: "?"}", color = BeerColors.muted, fontSize = 11.sp)
                                g.comment?.takeIf { it.isNotBlank() }?.let {
                                    Text("« $it »", color = BeerColors.text, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
