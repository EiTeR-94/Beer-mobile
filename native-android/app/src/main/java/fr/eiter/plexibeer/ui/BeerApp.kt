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

    var currentScreen by remember { mutableStateOf("main") }

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

    // Load styles and flavors when entering add (like onAppear in iOS)
    LaunchedEffect(currentScreen) {
        if (currentScreen == "add") {
            try {
                styleOptions = api.styles()
                val fh = api.flavorsAndHops()
                flavorTags = fh.flavors ?: emptyList()
                hopTags = fh.hops ?: emptyList()
            } catch (_: Exception) {}
        }
        if (currentScreen == "history") {
            scope.launch { checkins = api.checkins(50) }
        }
        if (currentScreen == "gallery") {
            scope.launch { checkins = api.checkins(100) }
        }
        if (currentScreen == "wishlist") {
            scope.launch { wishlist = api.wishlist() }
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

    fun goToStep(s: Int) { if (s in 1..4) wizardStep = s }

    fun resetAddForm() {
        beerName = ""; brewery = ""; style = ""; comment = ""; rating = 3.5f
        photoFile = null; pendingPhotoFile = null; lookupBarcode = ""; lookupStatus = ""; wizardStep = 1
        untappdBrewery = ""; untappdName = ""; untappdResults = emptyList(); untappdError = null
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
                    currentScreen = "main"
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
            currentScreen = "main"
        }
    }

    fun submitCheckin() {
        scope.launch {
            isLoading = true
            try {
                val r = (rating / 2f).coerceIn(0.25f, 5f).toDouble()
                val bc = lookupBarcode.filter { it.isDigit() }.ifBlank { null }
                val untappdBid = untappdResults.firstOrNull()?.bid
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
                currentScreen = "history"
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

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("🍺 Beer Log — Android (owner)", style = MaterialTheme.typography.headlineMedium)
        Text("LAN/VPN uniquement — même chose que iOS", style = MaterialTheme.typography.bodySmall)

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
            Row {
                Text("Connecté: $user", modifier = Modifier.weight(1f))
                TextButton(onClick = { doLogout() }) { Text("Déconnexion") }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { wizardStep = 1; resetAddForm() }) { Text("Nouveau / Reset Wizard") }
                Button(onClick = { currentScreen = "history" }) { Text("Historique") }
                Button(onClick = { currentScreen = "gallery" }) { Text("Galerie") }
                Button(onClick = { currentScreen = "wishlist" }) { Text("Wishlist") }
            }
            Spacer(Modifier.height(16.dp))

            when (currentScreen) {
                "main" -> {
                    // The wizard is always shown like in iOS MainView
                    Column {
                        Text("Nouveau checkin - Étape $wizardStep / 4", style = MaterialTheme.typography.titleMedium)
                        Text("lookup → photo → note → review", style = MaterialTheme.typography.bodySmall)

                        // Step nav pills
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                            for (s in 1..4) {
                                val label = when (s) {
                                    1 -> "Lookup"
                                    2 -> "Photo"
                                    3 -> "Note"
                                    4 -> "Review"
                                    else -> ""
                                }
                                Button(
                                    onClick = { if (s <= wizardStep) goToStep(s) },
                                    modifier = Modifier.weight(1f)
                                ) { Text(label, style = MaterialTheme.typography.labelSmall) }
                            }
                        }

                        when (wizardStep) {
                            1 -> {
                                // Step 1: Lookup / enter (closer to iOS)
                                Text("Scan EAN optionnel — ou cherche sur Untappd.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                                OutlinedTextField(value = lookupBarcode, onValueChange = { lookupBarcode = it }, label = { Text("Code-barres EAN (optionnel)") }, modifier = Modifier.fillMaxWidth())
                                Row {
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
                                if (lookupStatus.isNotBlank()) Text(lookupStatus)

                                // Untappd search like iOS
                                Text("Chercher sur Untappd", style = MaterialTheme.typography.titleSmall)
                                OutlinedTextField(value = untappdBrewery, onValueChange = { untappdBrewery = it }, label = { Text("Brasserie (optionnel)") }, modifier = Modifier.fillMaxWidth())
                                OutlinedTextField(value = untappdName, onValueChange = { untappdName = it }, label = { Text("Nom de la bière") }, modifier = Modifier.fillMaxWidth())
                                Button(onClick = {
                                    scope.launch {
                                        busy = true; untappdError = null
                                        try {
                                            val resp = api.searchUntappd(untappdBrewery, untappdName)
                                            untappdResults = resp.results ?: emptyList()
                                            if (untappdResults.isEmpty()) untappdError = "Aucun résultat"
                                        } catch (e: Exception) { untappdError = e.message }
                                        busy = false
                                    }
                                }, enabled = untappdName.length >= 2 || untappdBrewery.length >= 2) { Text(if (busy) "Recherche…" else "Chercher sur Untappd") }
                                if (untappdError != null) Text(untappdError!!, color = MaterialTheme.colorScheme.error)
                                untappdResults.forEach { hit ->
                                    Button(onClick = {
                                        beerName = hit.beerName
                                        brewery = hit.brewery ?: ""
                                        style = hit.styleFr ?: ""
                                        untappdResults = emptyList()
                                    }) {
                                        Text("${hit.beerName} - ${hit.brewery ?: ""}")
                                    }
                                }

                                OutlinedTextField(value = beerName, onValueChange = { beerName = it }, label = { Text("Nom de la bière *") }, modifier = Modifier.fillMaxWidth())
                                OutlinedTextField(value = brewery, onValueChange = { brewery = it }, label = { Text("Brasserie") }, modifier = Modifier.fillMaxWidth())
                                OutlinedTextField(value = style, onValueChange = { style = it }, label = { Text("Style") }, modifier = Modifier.fillMaxWidth())

                                Button(onClick = { goToStep(2) }, enabled = beerName.isNotBlank(), modifier = Modifier.fillMaxWidth()) { Text("Continuer → Photo") }
                            }
                            2 -> {
                                // Step 2: Photo
                                Text("Photo de la bière / du verre")
                                Button(onClick = { takePhoto() }, modifier = Modifier.fillMaxWidth()) { Text("📷 Prendre photo (full res)") }
                                if (photoFile != null) {
                                    Text("Photo prête")
                                    AsyncImage(model = photoFile, contentDescription = null, modifier = Modifier.height(120.dp).fillMaxWidth())
                                    TextButton(onClick = { photoFile = null }) { Text("Retirer") }
                                }
                                Row {
                                    Button(onClick = { goToStep(1) }) { Text("← Retour") }
                                    Spacer(Modifier.width(8.dp))
                                    Button(onClick = { goToStep(3) }) { Text("Continuer → Note") }
                                }
                            }
                            3 -> {
                                // Step 3: Rating / comment + flavors/hops (closer to iOS)
                                Text("Note (0.25-5)")
                                Slider(value = rating, onValueChange = { rating = it }, valueRange = 0.25f..5f, steps = 19)
                                Text("%.2f / 5".format(rating))
                                OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("Commentaire") }, modifier = Modifier.fillMaxWidth())

                                // Flavors
                                Text("Flavors")
                                Row {
                                    OutlinedTextField(value = customFlavorInput, onValueChange = { customFlavorInput = it }, label = { Text("Custom flavor") }, modifier = Modifier.weight(1f))
                                    Button(onClick = {
                                        if (customFlavorInput.isNotBlank()) {
                                            flavors = flavors + customFlavorInput.trim()
                                            customFlavorInput = ""
                                        }
                                    }) { Text("+") }
                                }
                                if (flavors.isNotEmpty()) Text("Selected: ${flavors.joinToString()}")

                                // Hops
                                Text("Hops")
                                Row {
                                    OutlinedTextField(value = customHopInput, onValueChange = { customHopInput = it }, label = { Text("Custom hop") }, modifier = Modifier.weight(1f))
                                    Button(onClick = {
                                        if (customHopInput.isNotBlank()) {
                                            hops = hops + customHopInput.trim()
                                            customHopInput = ""
                                        }
                                    }) { Text("+") }
                                }
                                if (hops.isNotEmpty()) Text("Selected: ${hops.joinToString()}")

                                Row {
                                    Button(onClick = { goToStep(2) }) { Text("← Retour") }
                                    Spacer(Modifier.width(8.dp))
                                    Button(onClick = { goToStep(4) }) { Text("Continuer → Review") }
                                }
                            }
                            4 -> {
                                // Step 4: Review & submit
                                Card(modifier = Modifier.fillMaxWidth()) {
                                    Column(Modifier.padding(12.dp)) {
                                        Text("${beerName} - ${brewery}", style = MaterialTheme.typography.titleSmall)
                                        Text("Style: $style  |  Note: %.2f/5".format(rating))
                                        if (comment.isNotBlank()) Text("Comment: $comment")
                                        if (flavors.isNotEmpty()) Text("Flavors: ${flavors.joinToString()}")
                                        if (hops.isNotEmpty()) Text("Hops: ${hops.joinToString()}")
                                        if (photoFile != null) Text("📷 Photo incluse")
                                    }
                                }
                                Row {
                                    Button(onClick = { goToStep(3) }) { Text("← Retour") }
                                    Spacer(Modifier.width(8.dp))
                                    Button(onClick = { submitCheckin() }, enabled = beerName.isNotBlank(), modifier = Modifier.weight(1f)) { Text("Enregistrer la dégustation") }
                                }
                            }
                            else -> {}
                        }
                        if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error)
                    }
                }
                "history" -> {
                    Text("Historique", style = MaterialTheme.typography.titleMedium)
                    if (stats != null) {
                        Text("Total: ${stats.total} | Avg: ${stats.avgRating ?: "-"}", style = MaterialTheme.typography.bodySmall)
                    }
                    Row {
                        Button(onClick = { scope.launch { checkins = api.checkins(50) } }) { Text("Rafraîchir") }
                        Button(onClick = { /* TODO: filters */ }) { Text("Filtres") }
                    }
                    if (checkins.isEmpty()) {
                        Text("Aucune dégustation. Note ta première bière !", style = MaterialTheme.typography.bodyMedium)
                    } else {
                        LazyColumn {
                            items(checkins) { item ->
                                Card(Modifier.padding(4.dp).fillMaxWidth().clickable { /* TODO: open detail like iOS CheckinDetailView */ }) {
                                    Column(Modifier.padding(8.dp)) {
                                        if (!item.photoURL.isNullOrBlank()) {
                                            AsyncImage(model = item.photoURL, contentDescription = null, modifier = Modifier.height(100.dp).fillMaxWidth())
                                        }
                                        Text("${item.beerName} — ${item.brewery ?: ""}", style = MaterialTheme.typography.titleSmall)
                                        Text("Note: ${item.rating} | ${item.style ?: ""}")
                                        if (!item.comment.isNullOrBlank()) Text(item.comment ?: "")
                                        if (item.flavors != null && item.flavors.isNotEmpty()) Text("Flavors: ${item.flavors.joinToString()}")
                                        if (item.hops != null && item.hops.isNotEmpty()) Text("Hops: ${item.hops.joinToString()}")
                                    }
                                }
                            }
                        }
                    }
                }
                "gallery" -> {
                    Text("Galerie", style = MaterialTheme.typography.titleMedium)
                    Button(onClick = { scope.launch { checkins = api.checkins(100) } }) { Text("Rafraîchir") }
                    val ps = checkins.filter { !it.photoURL.isNullOrBlank() }
                    if (ps.isEmpty()) {
                        Text("Aucune photo. Ajoute des checkins avec photos !")
                    } else {
                        LazyColumn {
                            items(ps) { item ->
                                Column {
                                    AsyncImage(model = item.photoURL, contentDescription = null, modifier = Modifier.height(200.dp).fillMaxWidth())
                                    Text("${item.beerName} — ${item.brewery ?: ""}")
                                }
                            }
                        }
                    }
                }
                "wishlist" -> {
                    Text("Wishlist", style = MaterialTheme.typography.titleMedium)
                    // Add to wishlist
                    Row {
                        OutlinedTextField(value = newWishName, onValueChange = { newWishName = it }, label = { Text("Nom bière") }, modifier = Modifier.weight(1f))
                        Button(onClick = {
                            if (newWishName.isNotBlank()) {
                                scope.launch {
                                    try {
                                        api.addWishlist(newWishName, "", "Unknown")
                                        wishlist = api.wishlist()
                                        newWishName = ""
                                    } catch (e: Exception) { error = e.message }
                                }
                            }
                        }) { Text("Ajouter") }
                    }
                    Button(onClick = { scope.launch { wishlist = api.wishlist() } }) { Text("Rafraîchir") }
                    if (wishlist.isEmpty()) {
                        Text("Wishlist vide.")
                    } else {
                        LazyColumn {
                            items(wishlist) { w ->
                                Row {
                                    Text("• ${w.beerName} (${w.brewery ?: ""})")
                                    Spacer(Modifier.weight(1f))
                                    Button(onClick = {
                                        scope.launch {
                                            api.deleteWishlist(w.id)
                                            wishlist = api.wishlist()
                                        }
                                    }) { Text("X") }
                                }
                            }
                        }
                    }
                }
                else -> {}
            }
        }
        if (isLoading) CircularProgressIndicator()
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
