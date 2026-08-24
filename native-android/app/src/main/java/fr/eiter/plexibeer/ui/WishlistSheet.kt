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
fun WishlistSheet(vm: AppViewModel) {
    val api = vm.api
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf(listOf<WishlistItem>()) }
    var newName by remember { mutableStateOf("") }
    var newBrewery by remember { mutableStateOf("") }
    var offlineHint by remember { mutableStateOf<String?>(null) }
    val cache = vm.listCache

    suspend fun reload() {
        try {
            val live = api.wishlist()
            cache.saveWishlist(live)
            items = live
            offlineHint = null
        } catch (_: Exception) {
            val cached = cache.loadWishlist()
            items = cached
            offlineHint = if (cached.isEmpty()) {
                "Hors ligne — liste non en cache"
            } else {
                "Hors ligne — wishlist en cache"
            }
        }
    }

    LaunchedEffect(Unit) {
        val cached = cache.loadWishlist()
        if (cached.isNotEmpty()) items = cached
        reload()
    }

    SheetScaffold("À boire", onClose = { vm.closeSheet() }) {
        Text("Tes souhaits personnels (bières à goûter).", color = BeerColors.muted, fontSize = 13.sp)
        offlineHint?.let {
            Text(it, color = BeerColors.accent, fontSize = 12.sp)
        }
        Spacer(Modifier.height(8.dp))
        BeerField("Nom bière", newName, { newName = it })
        Spacer(Modifier.height(6.dp))
        BeerField("Brasserie (optionnel)", newBrewery, { newBrewery = it })
        Spacer(Modifier.height(8.dp))
        BeerPrimaryButton("Ajouter", enabled = newName.length >= 2 && vm.networkStatus == NetworkStatus.ONLINE) {
            scope.launch {
                try {
                    api.addWishlist(newName.trim(), newBrewery.trim())
                    newName = ""
                    newBrewery = ""
                    reload()
                    vm.showToast("Ajouté ✓", ToastPayload.Variant.SUCCESS)
                } catch (e: Exception) {
                    vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        if (items.isEmpty()) {
            BeerEmptyState("🍺", "Liste vide", "Ajoute des bières à goûter.")
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(items, key = { it.id }) { w ->
                    BeerCard {
                        Text(w.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                        Text("${w.brewery.orEmpty()} · ${w.style.orEmpty()}", color = BeerColors.muted, fontSize = 12.sp)
                        Row {
                            TextButton(onClick = { vm.startWishlistTaste(w) }) {
                                Text("Goûter", color = BeerColors.accent)
                            }
                            TextButton(onClick = {
                                scope.launch {
                                    try {
                                        api.deleteWishlist(w.id)
                                        reload()
                                    } catch (e: Exception) {
                                        vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                                    }
                                }
                            }) { Text("Suppr.", color = BeerColors.error) }
                        }
                    }
                }
            }
        }
    }
}
