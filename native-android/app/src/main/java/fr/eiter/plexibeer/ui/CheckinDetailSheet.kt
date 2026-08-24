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
fun CheckinDetailSheet(vm: AppViewModel, item: CheckinItem) {
    val scope = rememberCoroutineScope()
    var hidden by remember { mutableStateOf(item.hiddenFromPartner == true) }

    // Parité iOS CheckinDetailView + BeerDetailHead
    Column(
        Modifier
            .fillMaxSize()
            .background(BeerColors.bg)
            .consumeClicks()
    ) {
        // BeerDetailHead
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            BeerGhostButton("Fermer", onClick = { vm.closeSheet() })
            Spacer(Modifier.weight(1f))
            if (vm.isAdmin) {
                BeerGhostButton(
                    if (hidden) "Visible" else "Masquer",
                    onClick = {
                        val next = !hidden
                        hidden = next
                        scope.launch {
                            try {
                                vm.api.updateCheckin(item.id, hiddenFromPartner = next)
                                vm.showToast(
                                    if (next) "Masqué partenaire" else "Visible partenaire",
                                    ToastPayload.Variant.SUCCESS
                                )
                            } catch (e: Exception) {
                                hidden = !next
                                vm.showToast(e.message ?: "Erreur", ToastPayload.Variant.ERROR)
                            }
                        }
                    }
                )
            }
            Button(
                onClick = { vm.startRetaste(item) },
                colors = ButtonDefaults.buttonColors(containerColor = BeerColors.accent),
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Text(
                    "Noter à nouveau",
                    color = BeerColors.btnPrimaryText,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 12.sp,
                    maxLines = 1
                )
            }
            BeerGhostButton(
                "Modifier",
                onClick = {
                    vm.editingCheckin = item
                    vm.openSheet(BeerSheet.EDIT)
                }
            )
        }

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (!item.photoURL.isNullOrBlank()) {
                BeerAuthImage(
                    path = item.photoURL,
                    api = vm.api,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 320.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
                )
            } else {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(140.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
                        .background(BeerColors.card),
                    contentAlignment = Alignment.Center
                ) {
                    Text("Pas de photo", color = BeerColors.muted)
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    item.beerName,
                    color = BeerColors.text,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (vm.isAdmin && (hidden || item.hiddenFromPartner == true)) {
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "privé",
                        color = BeerColors.accent,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(BeerColors.accent.copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }
            Text(
                "${item.brewery ?: "—"} · ${item.style ?: "?"} · ${formatDate(item.createdAt)}",
                color = BeerColors.muted,
                fontSize = 13.sp
            )

            item.location?.trim()?.takeIf { it.isNotEmpty() }?.let { loc ->
                val uriHandler = LocalUriHandler.current
                val lat = item.locationLat
                val lon = item.locationLon
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
                        .background(BeerColors.card)
                        .let { m ->
                            if (lat != null && lon != null) {
                                m.clickable {
                                    uriHandler.openUri(
                                        "https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon"
                                    )
                                }
                            } else m
                        }
                        .padding(12.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Text("📍", fontSize = 14.sp)
                    Spacer(Modifier.width(8.dp))
                    Column {
                        Text("Lieu", color = BeerColors.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            loc,
                            color = if (lat != null && lon != null) BeerColors.accent else BeerColors.text,
                            fontSize = 14.sp
                        )
                    }
                }
            }

            BeerStarRating(item.rating)

            item.flavors?.takeIf { it.isNotEmpty() }?.let {
                Text(
                    "Goûts : ${it.joinToString(", ")}",
                    color = BeerColors.text,
                    fontSize = 13.sp
                )
            }
            item.hops?.takeIf { it.isNotEmpty() }?.let {
                Text(
                    "Houblons : ${it.joinToString(", ")}",
                    color = BeerColors.muted,
                    fontSize = 13.sp
                )
            }
            item.comment?.takeIf { it.isNotBlank() }?.let { c ->
                Text(
                    "« $c »",
                    color = BeerColors.text,
                    fontSize = 14.sp,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .border(1.dp, BeerColors.border, RoundedCornerShape(14.dp))
                        .background(BeerColors.card)
                        .padding(12.dp)
                )
            }
        }
    }
}
