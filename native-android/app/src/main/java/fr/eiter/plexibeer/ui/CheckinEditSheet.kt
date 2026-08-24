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
fun CheckinEditSheet(vm: AppViewModel, item: CheckinItem) {
    val scope = rememberCoroutineScope()
    var rating by remember { mutableFloatStateOf(item.rating.toFloat()) }
    var comment by remember { mutableStateOf(item.comment.orEmpty()) }
    var location by remember { mutableStateOf(item.location.orEmpty()) }
    var locationLat by remember { mutableStateOf(item.locationLat) }
    var locationLon by remember { mutableStateOf(item.locationLon) }
    var locationOsmId by remember { mutableStateOf(item.locationOsmId) }
    var locationResults by remember { mutableStateOf(listOf<GeocodeHit>()) }
    var locationSearchJob by remember { mutableStateOf<Job?>(null) }
    var flavors by remember { mutableStateOf(item.flavors.orEmpty().toSet()) }
    var hops by remember { mutableStateOf(item.hops.orEmpty().toSet()) }
    var flavorTags by remember { mutableStateOf(listOf<String>()) }
    var hopTags by remember { mutableStateOf(listOf<String>()) }
    var customFlavor by remember { mutableStateOf("") }
    var customHop by remember { mutableStateOf("") }
    var hidden by remember { mutableStateOf(item.hiddenFromPartner == true) }
    var busy by remember { mutableStateOf(false) }
    var removePhoto by remember { mutableStateOf(false) }
    var newPhoto by remember { mutableStateOf<File?>(null) }
    val context = LocalContext.current
    var pending by remember { mutableStateOf<File?>(null) }

    LaunchedEffect(Unit) {
        try {
            val fh = vm.api.flavors(item.style.orEmpty())
            flavorTags = (fh.suggestedFlavors ?: fh.flavors).orEmpty()
            hopTags = (fh.suggestedHops ?: fh.hops).orEmpty()
        } catch (_: Exception) {
        }
        val hasPermission = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (hasPermission) LocationBiasProvider.refresh(context)
    }

    fun scheduleLocationSearch(query: String) {
        locationSearchJob?.cancel()
        if (query.trim().length < 2) {
            locationResults = emptyList()
            return
        }
        locationSearchJob = scope.launch {
            delay(300)
            try {
                val resp = vm.api.geocodeSearch(query, LocationBiasProvider.lat, LocationBiasProvider.lon)
                locationResults = resp.results.orEmpty()
            } catch (e: Exception) {
                locationResults = emptyList()
            }
        }
    }

    fun pickLocation(hit: GeocodeHit) {
        location = hit.label.take(300)
        locationLat = hit.lat
        locationLon = hit.lon
        locationOsmId = hit.osmId
        locationResults = emptyList()
        locationSearchJob?.cancel()
    }

    val takePic = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok && pending != null) {
            newPhoto = pending
            removePhoto = false
        }
        pending = null
    }

    SheetScaffold("Modifier la dégustation", onClose = { vm.closeSheet() }) {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "${item.brewery ?: "—"} · ${item.style ?: "?"} · ${formatDate(item.createdAt)}",
                color = BeerColors.muted,
                fontSize = 13.sp
            )
            BeerCard {
                UntappdRatingSlider(rating, { rating = it }, onTick = { vm.hapticTick() })
            }
            if (flavorTags.isNotEmpty()) {
                BeerCard {
                    FlavorTagGrid("Goûts", flavorTags, flavors, 8) {
                        flavors = if (it in flavors) flavors - it else flavors + it
                    }
                }
            }
            BeerCard {
                Text("Goûts perso", color = BeerColors.muted)
                CustomTagInput("…", customFlavor, { customFlavor = it }) {
                    val t = customFlavor.trim()
                    if (t.isNotBlank() && flavors.size < 8) {
                        flavors = flavors + t
                        customFlavor = ""
                    }
                }
            }
            if (hopTags.isNotEmpty()) {
                BeerCard {
                    FlavorTagGrid("Houblons", hopTags, hops, 6) {
                        hops = if (it in hops) hops - it else hops + it
                    }
                }
            }
            BeerCard {
                Text("Houblons perso", color = BeerColors.muted)
                CustomTagInput("…", customHop, { customHop = it }) {
                    val t = customHop.trim()
                    if (t.isNotBlank() && hops.size < 6) {
                        hops = hops + t
                        customHop = ""
                    }
                }
            }
            BeerField("Commentaire", comment, { if (it.length <= 300) comment = it })
            BeerField(
                label = "Lieu ou lien",
                value = location,
                onChange = {
                    if (it.length <= 300) location = it
                    locationLat = null
                    locationLon = null
                    locationOsmId = null
                    scheduleLocationSearch(it)
                },
                placeholder = "ex. Chez nous · https://maps…"
            )
            if (locationLat != null) {
                Text("✓ Lieu vérifié (OpenStreetMap)", color = BeerColors.accent, fontSize = 11.sp)
            }
            locationResults.forEach { hit ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 3.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(8.dp))
                        .clickable { pickLocation(hit) }
                        .padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("📍", fontSize = 12.sp)
                    Spacer(Modifier.width(6.dp))
                    Text(hit.label, color = BeerColors.text, fontSize = 12.sp)
                }
            }
            if (vm.isAdmin) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Masqué partenaire", color = BeerColors.text, modifier = Modifier.weight(1f))
                    Switch(checked = hidden, onCheckedChange = { hidden = it })
                }
            }
            BeerSecondaryButton("📷 Nouvelle photo") {
                try {
                    val dir = File(context.cacheDir, "beer").apply { mkdirs() }
                    val f = File(dir, "edit_${System.currentTimeMillis()}.jpg")
                    val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", f)
                    pending = f
                    takePic.launch(uri)
                } catch (e: Exception) {
                    vm.showToast(e.message ?: "Caméra", ToastPayload.Variant.ERROR)
                }
            }
            if (item.photoURL != null || newPhoto != null) {
                BeerSecondaryButton("Retirer la photo") {
                    removePhoto = true
                    newPhoto = null
                }
            }
            BeerPrimaryButton(if (busy) "Enregistrement…" else "Enregistrer", busy = busy) {
                scope.launch {
                    busy = true
                    try {
                        vm.api.updateCheckin(
                            id = item.id,
                            rating = rating.toDouble(),
                            flavors = flavors.toList(),
                            hops = hops.toList(),
                            comment = comment,
                            hiddenFromPartner = if (vm.isAdmin) hidden else null,
                            location = location.take(300),
                            locationLat = locationLat,
                            locationLon = locationLon,
                            locationOsmId = locationOsmId
                        )
                        if (removePhoto) {
                            try { vm.api.removeCheckinPhoto(item.id) } catch (_: Exception) {}
                        }
                        newPhoto?.let { f ->
                            val bytes = ImageUtils.compressJPEG(f.readBytes())
                            vm.api.replaceCheckinPhoto(item.id, bytes)
                        }
                        vm.showToast("Modifié ✓", ToastPayload.Variant.SUCCESS)
                        vm.closeSheet()
                    } catch (e: Exception) {
                        vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                    } finally {
                        busy = false
                    }
                }
            }
        }
    }
}
