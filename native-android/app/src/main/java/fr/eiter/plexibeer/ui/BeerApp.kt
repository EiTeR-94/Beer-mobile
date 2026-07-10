package fr.eiter.plexibeer.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Composable
fun BeerApp(context: Context) {
    val scope = rememberCoroutineScope()
    val api = remember { BeerAPI.getInstance(context) }

    var isLoggedIn by remember { mutableStateOf(false) }
    var user by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var currentScreen by remember { mutableStateOf("main") } // legacy, main = always wizard now
    var currentSheet by remember { mutableStateOf<String?>(null) } // like iOS BeerSheet: history, gallery, wishlist...

    var checkins by remember { mutableStateOf(listOf<CheckinItem>()) }
    var wishlist by remember { mutableStateOf(listOf<WishlistItem>()) }
    var stats by remember { mutableStateOf<HistoryStats?>(null) }

    // Add form state (wizard-like screen)
    var beerName by remember { mutableStateOf("") }
    var brewery by remember { mutableStateOf("") }
    var style by remember { mutableStateOf("") }
    var rating by remember { mutableStateOf(3.5f) }
    var comment by remember { mutableStateOf("") }
    var photoFile by remember { mutableStateOf<File?>(null) }
    var lookupBarcode by remember { mutableStateOf("") }
    var lookupStatus by remember { mutableStateOf("") }
    var wizardStep by remember { mutableStateOf(1) }

    var pendingPhotoFile by remember { mutableStateOf<File?>(null) }
    var pendingScanFile by remember { mutableStateOf<File?>(null) }

    // Additional state for closer iOS parity
    var untappdBrewery by remember { mutableStateOf("") }
    var untappdName by remember { mutableStateOf("") }
    var untappdResults by remember { mutableStateOf(listOf<UntappdHit>()) }
    var untappdError by remember { mutableStateOf<String?>(null) }
    var selectedUntappdBid by remember { mutableStateOf<Int?>(null) }
    var styleOptions by remember { mutableStateOf(listOf<StyleOption>()) }
    var manualStyle by remember { mutableStateOf("") }
    var flavors by remember { mutableStateOf(setOf<String>()) }
    var hops by remember { mutableStateOf(setOf<String>()) }
    var customFlavorInput by remember { mutableStateOf("") }
    var customHopInput by remember { mutableStateOf("") }
    var flavorTags by remember { mutableStateOf(listOf<String>()) }
    var hopTags by remember { mutableStateOf(listOf<String>()) }
    var busy by remember { mutableStateOf(false) }

    // For wishlist add (hoisted to avoid recompose issues)
    var newWishName by remember { mutableStateOf("") }

    // Load data when opening sheets (like iOS sheets bootstrap), and styles for wizard (always)
    LaunchedEffect(Unit) {
        try {
            styleOptions = api.styles()
            val fh = api.flavorsAndHops()
            flavorTags = fh.flavors ?: emptyList()
            hopTags = fh.hops ?: emptyList()
        } catch (_: Exception) {}
    }

    // Load when sheet changes (mirrors .task / onChange in HistorySheetView etc)
    LaunchedEffect(currentSheet) {
        when (currentSheet) {
            "history" -> scope.launch {
                checkins = api.checkins(50)
                stats = api.stats()
            }
            "gallery" -> scope.launch {
                checkins = api.checkins(100)
            }
            "wishlist" -> scope.launch {
                wishlist = api.wishlist()
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            error = "Permission caméra refusée"
        }
        // after grant, user re-taps the button (scan or photo)
    }

    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) {
            error = "Photo prise (simplifié pour test)."
        }
    }

    fun goToStep(s: Int) { if (s in 1..3) wizardStep = s }  // 3 steps like iOS

    fun resetAddForm() {
        beerName = ""; brewery = ""; style = ""; comment = ""; rating = 3.5f
        photoFile = null; pendingPhotoFile = null; lookupBarcode = ""; lookupStatus = ""; wizardStep = 1
        untappdBrewery = ""; untappdName = ""; untappdResults = emptyList(); untappdError = null
        selectedUntappdBid = null
        manualStyle = ""; flavors = emptySet(); hops = emptySet(); customFlavorInput = ""; customHopInput = ""
    }

    fun takePhoto() {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        cameraLauncher.launch(intent)
    }

    // TakePicture for full res used by scan (and could for photo)
    val takePictureLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        if (success && pendingPhotoFile != null) {
            photoFile = pendingPhotoFile
        } else {
            pendingPhotoFile = null
        }
    }

    fun createTempFile(ctx: Context, prefix: String): File {
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        val dir = File(ctx.cacheDir, "beer").apply { mkdirs() }
        return File(dir, "${prefix}_${ts}.jpg")
    }

    fun launchPhotoCapture(ctx: Context) {
        try {
            val f = createTempFile(ctx, "photo")
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
            pendingPhotoFile = f
            takePictureLauncher.launch(uri)
        } catch (e: Exception) { error = "Prep photo: ${e.message}" }
    }

    // ML Kit barcode scan support
    val barcodeScanLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        val f = pendingScanFile
        pendingScanFile = null
        if (success && f != null) {
            scope.launch {
                isLoading = true
                try {
                    val code = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        kotlinx.coroutines.suspendCancellableCoroutine<String?> { cont ->
                            try {
                                val img = com.google.mlkit.vision.common.InputImage.fromFilePath(context, Uri.fromFile(f))
                                val sc = com.google.mlkit.vision.barcode.BarcodeScanning.getClient()
                                sc.process(img)
                                    .addOnSuccessListener { bs: List<com.google.mlkit.vision.barcode.common.Barcode> ->
                                        val code = bs.firstOrNull { b: com.google.mlkit.vision.barcode.common.Barcode ->
                                            val f = b.format
                                            (f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_13 || f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_8 || f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_A || f == com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_E) && b.rawValue != null
                                        }?.rawValue ?: bs.firstOrNull { b2: com.google.mlkit.vision.barcode.common.Barcode -> b2.rawValue != null }?.rawValue
                                        try { sc.close() } catch (_: Exception) {}
                                        cont.resume(code)
                                    }
                                    .addOnFailureListener { ex: Exception ->
                                        try { sc.close() } catch (_: Exception) {}
                                        cont.resumeWithException(ex)
                                    }
                                cont.invokeOnCancellation { try { sc.close() } catch (_: Exception) {} }
                            } catch (e: Exception) {
                                cont.resumeWithException(e)
                            }
                        }
                    }
                    if (!code.isNullOrBlank()) {
                        lookupBarcode = code
                        lookupStatus = "Scan ML Kit OK — lookup..."
                        try {
                            val resp = api.lookup(code.filter { c -> c.isDigit() })
                            if (resp.ok && !resp.beerName.isNullOrBlank()) {
                                beerName = resp.beerName ?: beerName
                                brewery = resp.brewery ?: brewery
                                style = resp.style ?: style
                                lookupStatus = "✓ Identifiée via scan: ${resp.beerName}"
                            } else {
                                lookupStatus = resp.error ?: "Scanné $code (introuvable, manuel OK)"
                            }
                        } catch (e: Exception) {
                            lookupStatus = "Lookup échec après scan: ${e.message}"
                        }
                    } else {
                        lookupStatus = "ML Kit n'a pas lu de code-barres valide."
                    }
                } catch (e: Exception) {
                    lookupStatus = "Erreur ML Kit: ${e.message}"
                } finally {
                    isLoading = false
                    try { f.delete() } catch (_: Exception) {}
                }
            }
        }
    }

    fun launchScanCapture(ctx: Context) {
        try {
            val f = createTempFile(ctx, "scan")
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
            pendingScanFile = f
            barcodeScanLauncher.launch(uri)
        } catch (e: Exception) {
            error = "Prep scan: ${e.message}"; pendingScanFile = null
        }
    }

    fun startBarcodeScan() {
        val p = Manifest.permission.CAMERA
        if (ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED) {
            launchScanCapture(context)
        } else {
            permissionLauncher.launch(p)
        }
    }

    fun takePhotoFull() {
        val p = Manifest.permission.CAMERA
        if (ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED) {
            launchPhotoCapture(context)
        } else {
            permissionLauncher.launch(p)
        }
    }

    fun doLogin(username: String, password: String) {
        scope.launch {
            isLoading = true
            error = null
            try {
                api.discoverWorkingEndpoint()
                val resp = api.login(username, password)
                if (resp.ok == true || resp.user != null) {
                    user = resp.user ?: username
                    isLoggedIn = true
                    currentSheet = null
                    refreshData(api, checkins = { checkins = it }, wishlist = { wishlist = it }, stats = { stats = it })
                } else {
                    error = resp.error ?: "Login échoué"
                }
            } catch (e: Exception) {
                error = "Erreur: ${e.message ?: "connexion (LAN/VPN ?)"}"
            }
            isLoading = false
        }
    }

    fun doLogout() {
        scope.launch {
            api.logout()
            isLoggedIn = false
            user = ""
            currentSheet = null
        }
    }

    fun submitCheckin() {
        scope.launch {
            isLoading = true
            try {
                val r = (rating / 2f).coerceIn(0.25f, 5f).toDouble()
                val bc = lookupBarcode.filter { it.isDigit() }.ifBlank { null }
                val untappdBid = selectedUntappdBid
                val id = api.createCheckinMultipart(
                    beerName = beerName,
                    brewery = brewery,
                    style = style.ifBlank { "Unknown" },
                    rating = r,
                    comment = comment.ifBlank { null },
                    photoFile = photoFile,
                    barcode = bc ?: "",
                    untappdBid = untappdBid,
                    flavors = flavors.toList(),
                    hops = hops.toList(),
                    force = false
                )
                error = "Checkin ajouté ✓ (id=$id)"
                refreshData(api, checkins = { checkins = it }, wishlist = { wishlist = it }, stats = { stats = it })
                resetAddForm()
                currentSheet = "history"   // open history sheet after submit (like iOS flow after save)
            } catch (e: Exception) {
                if (e.message?.contains("déjà", ignoreCase = true) == true || e.message?.contains("duplicate", ignoreCase = true) == true) {
                    error = "Déjà dégustée. Force ? (non implémenté)"
                } else {
                    error = "Erreur ajout: ${e.message}"
                }
            }
            isLoading = false
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(12.dp)) {
        if (!isLoggedIn) {
            Spacer(Modifier.height(24.dp))
            var loginUser by remember { mutableStateOf("eiter") }
            var loginPass by remember { mutableStateOf("") }
            OutlinedTextField(value = loginUser, onValueChange = { loginUser = it }, label = { Text("Utilisateur owner") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(value = loginPass, onValueChange = { loginPass = it }, label = { Text("Mot de passe") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(12.dp))
            Button(onClick = { doLogin(loginUser, loginPass) }, modifier = Modifier.fillMaxWidth(), enabled = !isLoading) {
                Text(if (isLoading) "Connexion..." else "Se connecter")
            }
            if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            Text("Base LAN: ${ServerSettings.effectiveBase}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
        } else {
            // === ROOT STRUCTURE aligned with iOS MainView ===
            // Header user + logout
            Row {
                Text("Connecté: $user", modifier = Modifier.weight(1f))
                TextButton(onClick = { doLogout() }) { Text("Déconnexion") }
            }

            // Header like iOS: title + grid of action buttons (ghost style)
            // This is the key part that makes the UX "the same": wizard is the main content.
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text("Beer Log", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("scan · photo · note", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                Spacer(Modifier.height(8.dp))

                // 3-col grid of buttons (approximates LazyVGrid in MainView)
                Column {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(onClick = { currentSheet = "wishlist" }, modifier = Modifier.weight(1f)) { Text("À boire", maxLines = 1) }
                        OutlinedButton(onClick = { currentSheet = "history" }, modifier = Modifier.weight(1f)) { Text("Historique", maxLines = 1) }
                        OutlinedButton(onClick = { currentSheet = "gallery" }, modifier = Modifier.weight(1f)) { Text("Galerie", maxLines = 1) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
                        OutlinedButton(onClick = { /* gifts not yet */ }, modifier = Modifier.weight(1f), enabled = false) { Text("Idées cadeaux") }
                        OutlinedButton(onClick = { currentSheet = "wishlist" }, modifier = Modifier.weight(1f)) { Text("Wishlist") }
                        OutlinedButton(onClick = { wizardStep = 1; resetAddForm() }, modifier = Modifier.weight(1f)) { Text("Reset wizard") }
                    }
                }
            }

            Spacer(Modifier.height(8.dp))

            // THE WIZARD IS ALWAYS THE MAIN CONTENT (exactly like MainView + BeerWizardView in iOS)
            // No more "currentScreen" swap hiding the wizard.
            Column(modifier = Modifier.padding(horizontal = 8.dp)) {
                Text("Nouveau checkin — Étape $wizardStep / 3", style = MaterialTheme.typography.titleMedium)
                Text("bière → photo → note", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                // Step nav (closer to BeerStepNav: 1 Bière, 2 Photo, 3 Note)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                    for (s in 1..3) {
                        val label = when (s) {
                            1 -> "1 Bière"
                            2 -> "2 Photo"
                            3 -> "3 Note"
                            else -> ""
                        }
                        val isCurrent = s == wizardStep
                        Button(
                            onClick = { if (s <= wizardStep || s == wizardStep - 1) goToStep(s) },
                            modifier = Modifier.weight(1f),
                            colors = if (isCurrent)
                                ButtonDefaults.buttonColors()
                            else ButtonDefaults.outlinedButtonColors()
                        ) {
                            Text(label, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }

                // === UNCONDITIONAL WIZARD (the main content of the app, like iOS) ===
                // 3 steps to match iOS BeerWizardView + BeerStepNav
                when (wizardStep) {
                    1 -> {
                        // Step 1: Lookup / scan / Untappd / manual (mirrors stepBeer)
                        Text("Scan EAN optionnel — ou cherche directement sur Untappd.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                        OutlinedTextField(value = lookupBarcode, onValueChange = { lookupBarcode = it }, label = { Text("Code-barres EAN (optionnel)") }, modifier = Modifier.fillMaxWidth())
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = {
                                scope.launch {
                                    lookupStatus = "Recherche..."
                                    try {
                                        val resp = api.lookup(lookupBarcode.filter { it.isDigit() })
                                        if (resp.beerName != null) {
                                            beerName = resp.beerName ?: ""
                                            brewery = resp.brewery ?: ""
                                            style = resp.style ?: ""
                                            lookupStatus = "✓ Identifiée"
                                        } else lookupStatus = resp.error ?: "Introuvable"
                                    } catch (e: Exception) { lookupStatus = e.message ?: "err" }
                                }
                            }, enabled = lookupBarcode.isNotBlank()) { Text("Lookup EAN") }
                            Button(onClick = { startBarcodeScan() }) { Text("📷 Scanner (ML Kit)") }
                        }
                        if (lookupStatus.isNotBlank()) Text(lookupStatus, style = MaterialTheme.typography.bodySmall)

                        // Untappd (same fields + results as iOS)
                        Text("Chercher sur Untappd", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                        OutlinedTextField(value = untappdBrewery, onValueChange = { untappdBrewery = it }, label = { Text("Brasserie (optionnel)") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = untappdName, onValueChange = { untappdName = it }, label = { Text("Nom de la bière") }, modifier = Modifier.fillMaxWidth())
                        Button(
                            onClick = {
                                scope.launch {
                                    busy = true; untappdError = null
                                    try {
                                        val resp = api.searchUntappd(untappdBrewery, untappdName)
                                        untappdResults = resp.results ?: emptyList()
                                        if (untappdResults.isEmpty()) untappdError = "Aucun résultat"
                                    } catch (e: Exception) { untappdError = e.message }
                                    busy = false
                                }
                            },
                            enabled = untappdName.length >= 2 || untappdBrewery.length >= 2,
                            modifier = Modifier.fillMaxWidth()
                        ) { Text(if (busy) "Recherche…" else "Chercher sur Untappd") }
                        if (untappdError != null) Text(untappdError!!, color = MaterialTheme.colorScheme.error)

                        untappdResults.forEach { hit ->
                            OutlinedButton(onClick = {
                                beerName = hit.beerName
                                brewery = hit.brewery ?: ""
                                style = hit.styleFr ?: ""
                                selectedUntappdBid = hit.bid
                                untappdResults = emptyList()
                                lookupStatus = "Untappd ✓"
                            }, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                                Text("${hit.beerName} — ${hit.brewery ?: ""}")
                            }
                        }

                        OutlinedTextField(value = beerName, onValueChange = { beerName = it }, label = { Text("Nom de la bière *") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = brewery, onValueChange = { brewery = it }, label = { Text("Brasserie") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = style, onValueChange = { style = it }, label = { Text("Style") }, modifier = Modifier.fillMaxWidth())

                        Button(onClick = { goToStep(2) }, enabled = beerName.isNotBlank(), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) { Text("Continuer → Photo") }
                    }
                    2 -> {
                        // Step 2: Photo (matches stepPhoto)
                        Text("Photo du verre avec la canette à côté (optionnel).", style = MaterialTheme.typography.bodySmall)
                        Button(onClick = { takePhotoFull() }, modifier = Modifier.fillMaxWidth()) { Text("📷 Prendre une photo") }
                        if (photoFile != null) {
                            Text("Photo prête ✓", modifier = Modifier.padding(top = 4.dp))
                            AsyncImage(model = photoFile, contentDescription = null, modifier = Modifier.height(160.dp).fillMaxWidth())
                            TextButton(onClick = { photoFile = null }) { Text("Retirer la photo") }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                            Button(onClick = { goToStep(1) }) { Text("← Retour") }
                            Button(onClick = { goToStep(3) }, modifier = Modifier.weight(1f)) { Text("Continuer → Note") }
                        }
                    }
                    3 -> {
                        // Step 3: Note + flavors + hops + comment + submit (merged review into step 3 like iOS)
                        Text("Note (0.25-5)", style = MaterialTheme.typography.titleSmall)
                        Slider(value = rating, onValueChange = { rating = it }, valueRange = 0.25f..5f, steps = 19)
                        Text("%.2f / 5".format(rating))

                        OutlinedTextField(value = comment, onValueChange = { if (it.length <= 120) comment = it }, label = { Text("Commentaire (optionnel, 120 car.)") }, modifier = Modifier.fillMaxWidth())

                        // Flavors (basic version of FlavorTagGrid + custom)
                        Text("Goûts", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedTextField(value = customFlavorInput, onValueChange = { customFlavorInput = it }, label = { Text("Goût perso") }, modifier = Modifier.weight(1f))
                            Button(onClick = {
                                if (customFlavorInput.isNotBlank()) {
                                    flavors = flavors + customFlavorInput.trim()
                                    customFlavorInput = ""
                                }
                            }) { Text("+") }
                        }
                        if (flavors.isNotEmpty()) {
                            Text("Sélectionnés: ${flavors.joinToString()}", style = MaterialTheme.typography.bodySmall)
                        }

                        // Hops
                        Text("Houblons", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedTextField(value = customHopInput, onValueChange = { customHopInput = it }, label = { Text("Houblon perso") }, modifier = Modifier.weight(1f))
                            Button(onClick = {
                                if (customHopInput.isNotBlank()) {
                                    hops = hops + customHopInput.trim()
                                    customHopInput = ""
                                }
                            }) { Text("+") }
                        }
                        if (hops.isNotEmpty()) {
                            Text("Sélectionnés: ${hops.joinToString()}", style = MaterialTheme.typography.bodySmall)
                        }

                        // Review card + actions
                        Card(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                            Column(Modifier.padding(12.dp)) {
                                Text("${beerName.ifBlank { "(non identifiée)" }} — ${brewery}", style = MaterialTheme.typography.titleSmall)
                                Text("Style: ${style.ifBlank { "—" }}  ·  Note: %.2f/5".format(rating))
                                if (comment.isNotBlank()) Text("« $comment »")
                                if (flavors.isNotEmpty()) Text("Goûts: ${flavors.joinToString()}")
                                if (hops.isNotEmpty()) Text("Houblons: ${hops.joinToString()}")
                                if (photoFile != null) Text("📷 Photo incluse")
                            }
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { goToStep(2) }) { Text("← Retour") }
                            Button(
                                onClick = { submitCheckin() },
                                enabled = beerName.isNotBlank(),
                                modifier = Modifier.weight(1f)
                            ) { Text("Enregistrer la dégustation") }
                        }
                    }
                }

                if (error != null) {
                    Text(error!!, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
                }
            }
        }

        // === SHEET OVERLAYS (equivalent to fullScreenCover in iOS) ===
        // When a sheet is open we show it instead of (or on top of) the wizard.
        // For now: full takeover with close button — makes navigation feel like sheets.
        if (currentSheet != null) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(12.dp)
                    .background(MaterialTheme.colorScheme.background)
            ) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        when (currentSheet) {
                            "history" -> "Historique"
                            "gallery" -> "Galerie photos"
                            "wishlist" -> "À boire / Wishlist"
                            else -> "Détail"
                        },
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = {
                        currentSheet = null
                        // refresh main data on close like iOS
                        scope.launch {
                            try { checkins = api.checkins(30); stats = api.stats(); wishlist = api.wishlist() } catch (_: Exception) {}
                        }
                    }) { Text("Fermer ✕") }
                }
                Spacer(Modifier.height(8.dp))

                when (currentSheet) {
                    "history" -> HistorySheetContent(
                        checkins = checkins,
                        stats = stats,
                        onRefresh = { scope.launch { checkins = api.checkins(50); stats = api.stats() } }
                    )
                    "gallery" -> GallerySheetContent(
                        checkins = checkins,
                        onRefresh = { scope.launch { checkins = api.checkins(100) } }
                    )
                    "wishlist" -> WishlistSheetContent(
                        wishlist = wishlist,
                        newWishName = newWishName,
                        onNewWishChange = { newWishName = it },
                        onAdd = {
                            scope.launch {
                                if (newWishName.isNotBlank()) {
                                    try {
                                        api.addWishlist(newWishName, "", "Unknown")
                                        wishlist = api.wishlist()
                                        newWishName = ""
                                    } catch (e: Exception) { error = e.message }
                                }
                            }
                        },
                        onDelete = { id ->
                            scope.launch {
                                api.deleteWishlist(id)
                                wishlist = api.wishlist()
                            }
                        },
                        onRefresh = { scope.launch { wishlist = api.wishlist() } }
                    )
                    else -> Text("Sheet inconnue")
                }
            }
        }

        if (isLoading) CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
    }
}

// Extracted sheet contents for clarity (can be moved to own files later)
@Composable
private fun HistorySheetContent(
    checkins: List<CheckinItem>,
    stats: HistoryStats?,
    onRefresh: () -> Unit
) {
    val s = stats
    Column {
        if (s != null && s.total > 0) {
            Text("Total: ${s.total}  ·  Moyenne: ${s.avgRating ?: "—"}", style = MaterialTheme.typography.bodySmall)
        }
        Button(onClick = onRefresh, modifier = Modifier.padding(vertical = 4.dp)) { Text("Rafraîchir") }

        if (checkins.isEmpty()) {
            Text("Aucune dégustation. Note ta première bière depuis l'accueil !", modifier = Modifier.padding(16.dp))
        } else {
            LazyColumn {
                items(checkins) { item ->
                    Card(
                        modifier = Modifier
                            .padding(4.dp)
                            .fillMaxWidth()
                            .clickable { /* TODO: future CheckinDetail like iOS */ }
                    ) {
                        Column(Modifier.padding(8.dp)) {
                            if (!item.photoURL.isNullOrBlank()) {
                                AsyncImage(model = item.photoURL, contentDescription = null, modifier = Modifier.height(110.dp).fillMaxWidth())
                            }
                            Text("${item.beerName} — ${item.brewery ?: ""}", style = MaterialTheme.typography.titleSmall)
                            Text("★ ${item.rating}  ·  ${item.style ?: ""}")
                            if (!item.comment.isNullOrBlank()) Text(item.comment ?: "", style = MaterialTheme.typography.bodySmall)
                            if (item.flavors?.isNotEmpty() == true) Text("Goûts: ${item.flavors.joinToString()}", style = MaterialTheme.typography.bodySmall)
                            if (item.hops?.isNotEmpty() == true) Text("Houblons: ${item.hops.joinToString()}", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GallerySheetContent(checkins: List<CheckinItem>, onRefresh: () -> Unit) {
    val photos = checkins.filter { !it.photoURL.isNullOrBlank() }
    Column {
        Text("${photos.size} photos", style = MaterialTheme.typography.bodySmall)
        Button(onClick = onRefresh) { Text("Rafraîchir") }
        if (photos.isEmpty()) {
            Text("Aucune photo pour l'instant.")
        } else {
            LazyColumn {
                items(photos) { item ->
                    Column(modifier = Modifier.padding(bottom = 12.dp)) {
                        AsyncImage(model = item.photoURL, contentDescription = null, modifier = Modifier.height(220.dp).fillMaxWidth())
                        Text("${item.beerName} — ${item.brewery ?: ""}", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun WishlistSheetContent(
    wishlist: List<WishlistItem>,
    newWishName: String,
    onNewWishChange: (String) -> Unit,
    onAdd: () -> Unit,
    onDelete: (Int) -> Unit,
    onRefresh: () -> Unit
) {
    Column {
        Row {
            OutlinedTextField(value = newWishName, onValueChange = onNewWishChange, label = { Text("Nom bière à ajouter") }, modifier = Modifier.weight(1f))
            Button(onClick = onAdd, modifier = Modifier.padding(start = 8.dp)) { Text("Ajouter") }
        }
        Button(onClick = onRefresh, modifier = Modifier.padding(vertical = 4.dp)) { Text("Rafraîchir") }

        if (wishlist.isEmpty()) {
            Text("Liste « À boire » vide.")
        } else {
            LazyColumn {
                items(wishlist) { w ->
                    Row(modifier = Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("• ${w.beerName} (${w.brewery ?: ""})", modifier = Modifier.weight(1f))
                        TextButton(onClick = { onDelete(w.id) }) { Text("Suppr") }
                    }
                }
            }
        }
    }
}
}

private suspend fun refreshData(
    api: BeerAPI,
    checkins: (List<CheckinItem>) -> Unit,
    wishlist: (List<WishlistItem>) -> Unit,
    stats: (HistoryStats?) -> Unit
) {
    try {
        checkins(api.checkins(30))
        wishlist(api.wishlist())
        stats(api.stats())
    } catch (_: Exception) {}
}
