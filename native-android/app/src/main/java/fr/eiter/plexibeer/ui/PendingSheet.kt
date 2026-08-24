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
fun PendingSheet(vm: AppViewModel) {
    SheetScaffold("En attente", onClose = { vm.closeSheet() }) {
        Text(
            when (vm.networkStatus) {
                NetworkStatus.ONLINE -> "Réseau OK — tu peux synchroniser."
                NetworkStatus.OFFLINE -> "Pas de réseau — les notes restent sur l'appareil."
                NetworkStatus.SERVER_UNREACHABLE -> "Serveur injoignable — file conservée."
            },
            color = BeerColors.muted,
            fontSize = 12.sp
        )
        Spacer(Modifier.height(8.dp))
        BeerPrimaryButton(
            "Synchroniser maintenant",
            enabled = vm.networkStatus == NetworkStatus.ONLINE && vm.pendingCount > 0
        ) {
            vm.requestSync()
        }
        Spacer(Modifier.height(8.dp))
        Text("Créations en attente (${vm.pendingItems.size})", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
        if (vm.pendingItems.isEmpty()) {
            Text("Aucune dégustation en attente.", color = BeerColors.muted)
        } else {
            vm.pendingItems.forEach { p ->
                BeerCard {
                    Text(p.beerName, color = BeerColors.text, fontWeight = FontWeight.Bold)
                    Text("${p.brewery} · ${p.style} · ★${formatRating(p.rating)}", color = BeerColors.muted, fontSize = 12.sp)
                    p.location?.takeIf { it.isNotBlank() }?.let {
                        Text("📍 $it", color = BeerColors.muted, fontSize = 12.sp)
                    }
                    TextButton(onClick = { vm.removePending(p.id) }) {
                        Text("Supprimer", color = BeerColors.error)
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("Suppressions en attente", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
        if (vm.pendingDeletes.isEmpty()) {
            Text("Aucune suppression en attente.", color = BeerColors.muted)
        } else {
            vm.pendingDeletes.forEach { id ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Suppression #$id", color = BeerColors.text, modifier = Modifier.weight(1f))
                    TextButton(onClick = { vm.removePendingDelete(id) }) {
                        Text("Annuler", color = BeerColors.error)
                    }
                }
            }
        }
    }
}
