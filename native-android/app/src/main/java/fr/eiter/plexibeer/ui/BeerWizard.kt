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


// ───────────────────────── Wizard ─────────────────────────

@Composable
fun BeerWizard(vm: AppViewModel) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = vm.api

    var product by remember { mutableStateOf<BeerProduct?>(null) }
    var scanStatus by remember { mutableStateOf("Cadre le code-barres dans le rectangle") }
    var busy by remember { mutableStateOf(false) }
    var untappdBrewery by remember { mutableStateOf("") }
    var untappdName by remember { mutableStateOf("") }
    var untappdResults by remember { mutableStateOf(listOf<UntappdHit>()) }
    var untappdError by remember { mutableStateOf<String?>(null) }
    var showManual by remember { mutableStateOf(false) }
    var showEanManual by remember { mutableStateOf(false) }
    var manualEan by remember { mutableStateOf("") }
    var manualName by remember { mutableStateOf("") }
    var manualBrewery by remember { mutableStateOf("") }
    var manualStyle by remember { mutableStateOf("") }
    var customStyle by remember { mutableStateOf("") }
    var styleOptions by remember { mutableStateOf(listOf<StyleOption>()) }
    var photoFile by remember { mutableStateOf<File?>(null) }
    /** Lieu / lien de dégustation (optionnel) — saisi à l'étape Photo, comme iOS. */
    var location by remember { mutableStateOf("") }
    var locationLat by remember { mutableStateOf<Double?>(null) }
    var locationLon by remember { mutableStateOf<Double?>(null) }
    var locationOsmId by remember { mutableStateOf<String?>(null) }
    var locationResults by remember { mutableStateOf(listOf<GeocodeHit>()) }
    var locationSearchJob by remember { mutableStateOf<Job?>(null) }
    var hasLocationPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var rating by remember { mutableFloatStateOf(3f) }
    var comment by remember { mutableStateOf("") }
    var flavors by remember { mutableStateOf(setOf<String>()) }
    var hops by remember { mutableStateOf(setOf<String>()) }
    var flavorTags by remember { mutableStateOf(listOf<String>()) }
    var hopTags by remember { mutableStateOf(listOf<String>()) }
    var showFlavors by remember { mutableStateOf(true) }
    var showHops by remember { mutableStateOf(true) }
    var customFlavor by remember { mutableStateOf("") }
    var customHop by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var showDuplicate by remember { mutableStateOf(false) }
    var duplicateDetail by remember { mutableStateOf("") }
    var pendingCapture by remember { mutableStateOf<File?>(null) }
    var captureMode by remember { mutableStateOf("photo") } // photo | scan
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }

    // Apply prefill from retaste / wishlist
    LaunchedEffect(vm.wizardProduct) {
        vm.wizardProduct?.let {
            product = it
            scanStatus = "Prérempli ✓"
        }
    }

    LaunchedEffect(Unit) {
        styleOptions = api.styles()
    }

    LaunchedEffect(vm.wizardStep, product) {
        if (vm.wizardStep == 3 && product != null) {
            try {
                val fh = api.flavors(product!!.displayStyle, product!!.summary)
                flavorTags = (fh.suggestedFlavors ?: fh.flavors).orEmpty()
                hopTags = (fh.suggestedHops ?: fh.hops).orEmpty()
                showFlavors = fh.showFlavorsBlock != false
                showHops = fh.showHopsBlock != false
            } catch (_: Exception) {
            }
        }
    }

    fun resetWizard() {
        product = null
        scanStatus = "Cadre le code-barres dans le rectangle"
        photoFile = null
        location = ""
        locationLat = null
        locationLon = null
        locationOsmId = null
        locationResults = emptyList()
        locationSearchJob?.cancel()
        rating = 3f
        comment = ""
        flavors = emptySet()
        hops = emptySet()
        untappdResults = emptyList()
        untappdError = null
        manualEan = ""
        manualName = ""
        manualBrewery = ""
        manualStyle = ""
        customStyle = ""
        vm.clearWizardPrefill()
        vm.wizardStep = 1
    }

    val eanLookupMutex = remember { Mutex() }

    /** Lookup EAN après lecture live ou photo (mutex = pas de double lookup en cascade). */
    suspend fun lookupScannedEan(rawCode: String, fromLive: Boolean) {
        val digits = rawCode.filter { it.isDigit() }
        if (digits.length < 8) {
            scanStatus = "Code trop court"
            return
        }
        if (!eanLookupMutex.tryLock()) return
        busy = true
        manualEan = digits
        scanStatus = "Recherche…"
        try {
            val res = api.lookup(digits)
            if (res.ok) {
                product = res.asProduct(digits)
                scanStatus = "Bière identifiée ✓"
                vm.showToast(
                    "Code-barres lu ✓",
                    ToastPayload.Variant.SUCCESS,
                    digits,
                    label = if (fromLive) "Scan" else "Photo",
                )
            } else {
                scanStatus = res.error ?: "Scanné $digits (introuvable)"
                product = BeerProduct(barcode = digits, beerName = "")
                vm.showToast(
                    "Code lu — introuvable",
                    ToastPayload.Variant.WARN,
                    digits,
                    label = if (fromLive) "Scan" else "Photo",
                )
            }
        } catch (e: Exception) {
            scanStatus = e.message ?: "Erreur"
        } finally {
            busy = false
            eanLookupMutex.unlock()
        }
    }

    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val f = pendingCapture
        pendingCapture = null
        if (!ok || f == null) return@rememberLauncherForActivityResult
        if (captureMode == "photo") {
            photoFile = f
            vm.showToast("Photo prête ✓", ToastPayload.Variant.SUCCESS)
        } else {
            scope.launch {
                // busy coupe le live scan pendant le décodage photo
                busy = true
                scanStatus = "Décodage photo…"
                var decoded: String? = null
                var serverProduct: BeerProduct? = null
                var decodeError: String? = null
                try {
                    val jpeg = ImageUtils.compressJPEG(f.readBytes())
                    val mlCode = tryMlKitBarcode(context, f)?.filter { it.isDigit() }
                    if (!mlCode.isNullOrBlank() && mlCode.length >= 8) {
                        decoded = mlCode
                    } else {
                        val scan = api.scanPhoto(jpeg)
                        if (scan.ok) {
                            val digits = scan.barcode.orEmpty().filter { it.isDigit() }
                            if (digits.length >= 8) {
                                decoded = digits
                            } else {
                                serverProduct = scan.asProduct(digits)
                            }
                        } else {
                            decodeError = scan.error ?: "Code illisible"
                        }
                    }
                } catch (e: Exception) {
                    decodeError = e.message ?: "Erreur scan"
                } finally {
                    busy = false
                    try { f.delete() } catch (_: Exception) {}
                }

                when {
                    decoded != null -> lookupScannedEan(decoded!!, fromLive = false)
                    serverProduct != null -> {
                        product = serverProduct
                        scanStatus = "Bière identifiée ✓"
                        vm.showToast("Code-barres lu ✓", ToastPayload.Variant.SUCCESS)
                    }
                    decodeError != null -> scanStatus = decodeError!!
                }
            }
        }
    }

    fun launchCamera(mode: String) {
        captureMode = mode
        if (!hasCameraPermission) {
            vm.showToast("Autorise la caméra puis réessaie", ToastPayload.Variant.WARN)
            return
        }
        try {
            val dir = File(context.cacheDir, "beer").apply { mkdirs() }
            val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val f = File(dir, "${mode}_$ts.jpg")
            val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", f)
            pendingCapture = f
            takePicture.launch(uri)
        } catch (e: Exception) {
            vm.showToast("Caméra: ${e.message}", ToastPayload.Variant.ERROR)
        }
    }

    /** pendingCamAction: null = live only, "scan"|"photo" = open still camera after grant */
    var pendingCamAction by remember { mutableStateOf<String?>(null) }

    val camPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCameraPermission = granted
        val action = pendingCamAction
        pendingCamAction = null
        if (!granted) {
            vm.showToast("Permission caméra refusée", ToastPayload.Variant.ERROR)
            return@rememberLauncherForActivityResult
        }
        if (action == "scan" || action == "photo") {
            launchCamera(action)
        }
        // sinon : scan live s'active tout seul via recomposition
    }

    fun ensureCamera(mode: String) {
        captureMode = mode
        if (hasCameraPermission) {
            launchCamera(mode)
        } else {
            pendingCamAction = mode
            camPerm.launch(Manifest.permission.CAMERA)
        }
    }

    fun ensureLiveCameraPermission() {
        if (hasCameraPermission) return
        pendingCamAction = null
        camPerm.launch(Manifest.permission.CAMERA)
    }

    // Demande caméra dès l'étape scan (comme iOS)
    LaunchedEffect(vm.wizardStep) {
        if (vm.wizardStep == 1 && !hasCameraPermission) {
            ensureLiveCameraPermission()
        }
    }

    val locationPerm = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        val ok = granted[Manifest.permission.ACCESS_COARSE_LOCATION] == true ||
            granted[Manifest.permission.ACCESS_FINE_LOCATION] == true
        hasLocationPermission = ok
        if (ok) LocationBiasProvider.refresh(context)
    }

    fun ensureLocationBias() {
        if (hasLocationPermission) {
            LocationBiasProvider.refresh(context)
        } else {
            locationPerm.launch(
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
            )
        }
    }

    // Anticipe la géoloc dès l'étape Photo & lieu (comme iOS/web) — best-effort, jamais bloquant.
    LaunchedEffect(vm.wizardStep) {
        if (vm.wizardStep == 2) ensureLocationBias()
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
                val resp = api.geocodeSearch(query, LocationBiasProvider.lat, LocationBiasProvider.lon)
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

    suspend fun doSave(force: Boolean) {
        val p = product ?: return
        if (p.beerName.isBlank()) {
            vm.showToast("Nom de bière requis", ToastPayload.Variant.WARN)
            return
        }
        saving = true
        try {
            val msg = vm.saveCheckin(
                product = p,
                rating = rating.toDouble(),
                flavors = flavors.toList(),
                hops = hops.toList(),
                comment = comment,
                photoFile = photoFile,
                force = force,
                location = location,
                locationLat = locationLat,
                locationLon = locationLon,
                locationOsmId = locationOsmId
            )
            if (msg.startsWith("duplicate|")) {
                val parts = msg.split("|")
                duplicateDetail = "Déjà notée: ${parts.getOrNull(1)} ★${parts.getOrNull(2)} (${parts.getOrNull(3)})"
                showDuplicate = true
            } else {
                vm.showToast(msg, ToastPayload.Variant.SUCCESS)
                resetWizard()
            }
        } catch (e: Exception) {
            vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
        } finally {
            saving = false
        }
    }

    if (showDuplicate) {
        AlertDialog(
            onDismissRequest = { showDuplicate = false },
            title = { Text("Déjà dégustée") },
            text = {
                Text(
                    if (duplicateDetail.isBlank()) "Ajouter cette nouvelle note à ton historique ?"
                    else duplicateDetail
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDuplicate = false
                    scope.launch { doSave(force = true) }
                }) { Text("Noter à nouveau") }
            },
            dismissButton = {
                TextButton(onClick = { showDuplicate = false }) { Text("Annuler") }
            }
        )
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        when (vm.wizardStep) {
            1 -> {
                BeerLead("Scan EAN optionnel — ou cherche directement sur Untappd.")

                // Scan live auto (parité iOS) + bouton photo secours
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(BeerColors.photoBg)
                        .border(1.dp, BeerColors.border, RoundedCornerShape(16.dp))
                ) {
                    if (hasCameraPermission) {
                        LiveBarcodeScanner(
                            enabled = !busy && vm.wizardStep == 1,
                            onCode = { code ->
                                scope.launch { lookupScannedEan(code, fromLive = true) }
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        Column(
                            Modifier
                                .fillMaxSize()
                                .clickable { ensureLiveCameraPermission() },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Text("📷", fontSize = 32.sp)
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "Autoriser la caméra pour le scan auto",
                                color = BeerColors.muted,
                                fontSize = 13.sp,
                            )
                        }
                    }

                    // Bouton photo (fallback comme iOS « Prendre photo »)
                    OutlinedButton(
                        onClick = { ensureCamera("scan") },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 12.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = BeerColors.card.copy(alpha = 0.92f),
                            contentColor = BeerColors.text,
                        ),
                        border = BorderStroke(1.dp, BeerColors.border),
                        shape = RoundedCornerShape(10.dp),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text("Prendre photo", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }

                    if (busy) {
                        CircularProgressIndicator(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(12.dp)
                                .size(22.dp),
                            color = BeerColors.accent,
                            strokeWidth = 2.dp,
                        )
                    }
                }
                Text(
                    scanStatus,
                    color = BeerColors.muted,
                    fontSize = 13.sp,
                    modifier = Modifier.fillMaxWidth(),
                )

                BeerCard {
                    Text("Chercher sur Untappd", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Top 5 résultats. Utilise Brasserie + Nom pour affiner.",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    BeerField("Brasserie (optionnel)", untappdBrewery, { untappdBrewery = it }, "ex. Les Intenables")
                    Spacer(Modifier.height(6.dp))
                    BeerField("Nom de la bière", untappdName, { untappdName = it }, "ex. Mama Whipa")
                    Spacer(Modifier.height(8.dp))
                    BeerPrimaryButton(
                        title = if (busy) "Recherche…" else "Chercher sur Untappd",
                        enabled = untappdName.length >= 2 || untappdBrewery.length >= 2,
                        busy = busy
                    ) {
                        scope.launch {
                            busy = true
                            untappdError = null
                            try {
                                val q = listOf(untappdBrewery, untappdName).filter { it.isNotBlank() }.joinToString(" ")
                                val resp = api.searchUntappd(q)
                                untappdResults = resp.results.orEmpty()
                                if (untappdResults.isEmpty()) untappdError = resp.error ?: "Aucun résultat"
                            } catch (e: Exception) {
                                untappdError = e.message
                            } finally {
                                busy = false
                            }
                        }
                    }
                    untappdError?.let { Text(it, color = BeerColors.error, fontSize = 12.sp) }
                    untappdResults.forEach { hit ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
                                .clickable {
                                    scope.launch {
                                        busy = true
                                        try {
                                            val fetched = api.untappdFetch(
                                                bid = hit.bid,
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty()
                                            )
                                            product = if (fetched.ok) {
                                                fetched.asProduct("").let { pr ->
                                                    if (pr.untappdBid == null) pr.copy(untappdBid = hit.bid) else pr
                                                }
                                            } else BeerProduct(
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty(),
                                                style = hit.styleFr ?: "Unknown",
                                                untappdBid = hit.bid
                                            )
                                            // Link EAN ↔ Untappd when we already scanned a barcode (iOS linkProduct)
                                            val bc = product?.barcode?.filter { it.isDigit() }.orEmpty()
                                            if (bc.length >= 8) {
                                                try {
                                                    api.linkProduct(
                                                        bid = hit.bid,
                                                        barcode = bc,
                                                        beerName = product!!.beerName,
                                                        brewery = product!!.brewery
                                                    )
                                                } catch (_: Exception) {
                                                }
                                            }
                                            scanStatus = "Untappd ✓"
                                            untappdResults = emptyList()
                                            vm.showToast("Bière sélectionnée ✓", ToastPayload.Variant.SUCCESS)
                                        } catch (e: Exception) {
                                            product = BeerProduct(
                                                beerName = hit.beerName,
                                                brewery = hit.brewery.orEmpty(),
                                                style = hit.styleFr ?: "Unknown",
                                                untappdBid = hit.bid
                                            )
                                            scanStatus = "Untappd ✓ (sans fetch)"
                                            untappdResults = emptyList()
                                        } finally {
                                            busy = false
                                        }
                                    }
                                }
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (!hit.photoURL.isNullOrBlank()) {
                                AsyncImage(
                                    model = hit.photoURL,
                                    contentDescription = null,
                                    modifier = Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)),
                                    contentScale = ContentScale.Crop
                                )
                                Spacer(Modifier.width(10.dp))
                            }
                            Column(Modifier.weight(1f)) {
                                Text(hit.beerName, color = BeerColors.text, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                Text(
                                    listOfNotNull(hit.brewery, hit.styleFr).joinToString(" · "),
                                    color = BeerColors.muted,
                                    fontSize = 11.sp
                                )
                            }
                            Text("›", color = BeerColors.muted)
                        }
                    }
                }

                // Manual entry
                BeerCard {
                    Text(
                        if (showManual) "▼ Saisie manuelle (secours)" else "▶ Saisie manuelle (secours)",
                        color = BeerColors.muted,
                        modifier = Modifier.clickable { showManual = !showManual }
                    )
                    if (showManual) {
                        Spacer(Modifier.height(8.dp))
                        BeerField("Nom de la bière", manualName, { manualName = it })
                        Spacer(Modifier.height(6.dp))
                        BeerField("Brasserie", manualBrewery, { manualBrewery = it })
                        Spacer(Modifier.height(6.dp))
                        BeerField("Style", manualStyle, { manualStyle = it }, "ex. IPA")
                        if (styleOptions.isNotEmpty()) {
                            Text("Styles serveur: tape le nom exact ou libre", color = BeerColors.muted, fontSize = 11.sp)
                        }
                        Spacer(Modifier.height(8.dp))
                        BeerSecondaryButton("Continuer") {
                            if (manualName.isBlank()) {
                                vm.showToast("Nom requis", ToastPayload.Variant.WARN)
                            } else {
                                val p = BeerProduct(
                                    beerName = manualName.trim(),
                                    brewery = manualBrewery.trim(),
                                    style = manualStyle.ifBlank { "Unknown" },
                                    barcode = manualEan.filter { it.isDigit() }
                                )
                                product = p
                                scanStatus = "Saisie manuelle ✓"
                                // Persist product for future EAN lookup (iOS saveProduct)
                                if (p.barcode.length >= 8) {
                                    scope.launch {
                                        try {
                                            api.saveProduct(p.barcode, p.beerName, p.brewery, p.style)
                                        } catch (_: Exception) {
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                BeerCard {
                    Text(
                        if (showEanManual) "▼ Code illisible ? Saisie EAN" else "▶ Code illisible ? Saisie EAN",
                        color = BeerColors.muted,
                        modifier = Modifier.clickable { showEanManual = !showEanManual }
                    )
                    if (showEanManual) {
                        Spacer(Modifier.height(8.dp))
                        BeerField("Code EAN", manualEan, { manualEan = it }, "ex. 5411680001111", KeyboardType.Number)
                        Spacer(Modifier.height(8.dp))
                        BeerSecondaryButton("Identifier par EAN") {
                            scope.launch {
                                val digits = manualEan.filter { it.isDigit() }
                                if (digits.length < 8) {
                                    scanStatus = "Code trop court"
                                    return@launch
                                }
                                busy = true
                                scanStatus = "Recherche…"
                                try {
                                    val res = api.lookup(digits)
                                    if (res.ok) {
                                        product = res.asProduct(digits)
                                        scanStatus = "Bière identifiée ✓"
                                        vm.showToast("Bière identifiée ✓", ToastPayload.Variant.SUCCESS)
                                    } else {
                                        scanStatus = res.error ?: "Introuvable"
                                        product = BeerProduct(barcode = digits)
                                    }
                                } catch (e: Exception) {
                                    scanStatus = e.message ?: "Erreur"
                                } finally {
                                    busy = false
                                }
                            }
                        }
                    }
                }

                product?.takeIf { it.beerName.isNotBlank() }?.let { p ->
                    BeerPreviewCard(p)
                    BeerSecondaryButton("+ Ajouter à la liste « À boire »") {
                        scope.launch {
                            try {
                                api.addWishlist(p.beerName, p.brewery, p.style, p.barcode)
                                vm.showToast("Ajouté à À boire ✓", ToastPayload.Variant.SUCCESS)
                            } catch (e: Exception) {
                                vm.showToast(e.message ?: "Échec", ToastPayload.Variant.ERROR)
                            }
                        }
                    }
                    BeerPrimaryButton("Continuer → photo") { vm.wizardStep = 2 }
                }
            }

            2 -> {
                BeerLead("Photo du verre (optionnel) et lieu de dégustation.")
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(BeerColors.card)
                        .border(2.dp, BeerColors.border, RoundedCornerShape(16.dp))
                        .clickable { ensureCamera("photo") },
                    contentAlignment = Alignment.Center
                ) {
                    if (photoFile != null) {
                        AsyncImage(
                            model = photoFile,
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize().padding(8.dp),
                            contentScale = ContentScale.Fit
                        )
                    } else {
                        Text("📷 Prendre une photo", color = BeerColors.muted)
                    }
                }
                if (photoFile != null) {
                    TextButton(onClick = { photoFile = null }) {
                        Text("Retirer la photo", color = BeerColors.error)
                    }
                }

                BeerCard {
                    Text("Où as-tu dégusté ?", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Nom du lieu et/ou lien (Maps, resto…) — optionnel.",
                        color = BeerColors.muted,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    BeerField(
                        label = "Lieu ou lien",
                        value = location,
                        onChange = {
                            if (it.length <= 300) location = it
                            locationLat = null
                            locationLon = null
                            locationOsmId = null
                            ensureLocationBias()
                            scheduleLocationSearch(it)
                        },
                        placeholder = "ex. Chez nous · Brasserie X · https://maps…"
                    )
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        if (locationLat != null) {
                            Text(
                                "✓ Lieu vérifié (OpenStreetMap)",
                                color = BeerColors.accent,
                                fontSize = 11.sp
                            )
                        } else {
                            Spacer(Modifier)
                        }
                        Text(
                            "${location.length}/300",
                            color = BeerColors.muted,
                            fontSize = 11.sp
                        )
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
                }

                BeerSecondaryButton("← Retour") { vm.wizardStep = 1 }
                BeerPrimaryButton("Continuer → note") { vm.wizardStep = 3 }
            }

            else -> {
                val p = product
                if (p != null && p.beerName.isNotBlank()) {
                    BeerLead(p.beerName)
                } else {
                    BeerLead("Pas de bière identifiée — retourne à l'étape 1.")
                }

                BeerCard {
                    UntappdRatingSlider(rating, { rating = it }, onTick = { vm.hapticTick() })
                }

                if (showFlavors) {
                    if (flavorTags.isNotEmpty()) {
                        BeerCard {
                            FlavorTagGrid(
                                title = if (p != null && p.displayStyle != "Unknown") "Goûts ${p.displayStyle}" else "Goûts",
                                tags = flavorTags,
                                selected = flavors,
                                maxCount = 8
                            ) { tag ->
                                flavors = if (tag in flavors) flavors - tag else flavors + tag
                            }
                        }
                    }
                    BeerCard {
                        Text("Goûts perso", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                        CustomTagInput("ex. pneus, sucrée…", customFlavor, { customFlavor = it }) {
                            val t = customFlavor.trim()
                            if (t.isNotBlank() && flavors.size < 8) {
                                flavors = flavors + t
                                customFlavor = ""
                            }
                        }
                        if (flavors.isNotEmpty()) {
                            Text("Sélectionnés: ${flavors.joinToString()}", color = BeerColors.muted, fontSize = 12.sp)
                        }
                        Text("Libre — 8 goûts max", color = BeerColors.muted, fontSize = 11.sp)
                    }
                }

                if (showHops) {
                    if (hopTags.isNotEmpty()) {
                        BeerCard {
                            FlavorTagGrid("Houblons", hopTags, hops, 6) { tag ->
                                hops = if (tag in hops) hops - tag else hops + tag
                            }
                        }
                    }
                    BeerCard {
                        Text("Houblons perso", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                        CustomTagInput("ex. Citra, Mosaic…", customHop, { customHop = it }) {
                            val t = customHop.trim()
                            if (t.isNotBlank() && hops.size < 6) {
                                hops = hops + t
                                customHop = ""
                                scope.launch { try { api.addHop(t) } catch (_: Exception) {} }
                            }
                        }
                        if (hops.isNotEmpty()) {
                            Text("Sélectionnés: ${hops.joinToString()}", color = BeerColors.muted, fontSize = 12.sp)
                        }
                    }
                }

                BeerCard {
                    Text("Commentaire (optionnel, 300 car.)", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(
                        value = comment,
                        onValueChange = { if (it.length <= 300) comment = it },
                        placeholder = { Text("Terrasse, avec elle, à refaire…", color = BeerColors.muted.copy(alpha = 0.6f)) },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
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
                    Text("${comment.length}/300", color = BeerColors.muted, fontSize = 11.sp, modifier = Modifier.align(Alignment.End))
                }

                BeerSecondaryButton("← Retour") { vm.wizardStep = 2 }
                BeerPrimaryButton(
                    title = if (saving) "Enregistrement…" else "Enregistrer",
                    enabled = product != null && product!!.beerName.isNotBlank() && rating >= 0.25f,
                    busy = saving
                ) {
                    scope.launch { doSave(force = false) }
                }

                TextButton(onClick = { resetWizard() }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Text("Reset wizard", color = BeerColors.muted)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}


suspend fun tryMlKitBarcode(context: Context, file: File): String? =
    withContext(Dispatchers.IO) {
        try {
            suspendCancellableCoroutine { cont ->
                try {
                    val img = com.google.mlkit.vision.common.InputImage.fromFilePath(context, Uri.fromFile(file))
                    val sc = com.google.mlkit.vision.barcode.BarcodeScanning.getClient()
                    sc.process(img)
                        .addOnSuccessListener { bs ->
                            val code = bs.firstOrNull { b ->
                                val f = b.format
                                (f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_13 ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_8 ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_A ||
                                    f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_E) &&
                                    b.rawValue != null
                            }?.rawValue ?: bs.firstOrNull { it.rawValue != null }?.rawValue
                            try { sc.close() } catch (_: Exception) {}
                            cont.resume(code)
                        }
                        .addOnFailureListener { ex ->
                            try { sc.close() } catch (_: Exception) {}
                            cont.resume(null)
                        }
                    cont.invokeOnCancellation { try { sc.close() } catch (_: Exception) {} }
                } catch (e: Exception) {
                    cont.resume(null)
                }
            }
        } catch (_: Exception) {
            null
        }
    }
