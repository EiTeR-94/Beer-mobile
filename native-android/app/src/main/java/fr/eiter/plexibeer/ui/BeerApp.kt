package fr.eiter.plexibeer.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.launch
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

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

    // Multi-step wizard state
    var wizardStep by remember { mutableStateOf(1) }

    // Form fields kept as-is
    var beerName by remember { mutableStateOf("") }
    var brewery by remember { mutableStateOf("") }
    var style by remember { mutableStateOf("") }
    var rating by remember { mutableStateOf(3.0f) }
    var comment by remember { mutableStateOf("") }
    var photoFile by remember { mutableStateOf<File?>(null) }
    var lookupBarcode by remember { mutableStateOf("") }
    var lookupStatus by remember { mutableStateOf("") }
    var photoUri by remember { mutableStateOf<Uri?>(null) }
    var pendingPhotoFile by remember { mutableStateOf<File?>(null) }
    var pendingScanFile by remember { mutableStateOf<File?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchTakePhoto(context) else error = "Permission caméra refusée."
    }

    val takePictureLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (success && pendingPhotoFile != null) {
            photoFile = pendingPhotoFile
            photoUri = Uri.fromFile(pendingPhotoFile)
        }
    }

    fun createTempPhotoFile(ctx: Context): File {
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        return File(File(ctx.cacheDir, "images").apply { mkdirs() }, "JPEG_${ts}_.jpg")
    }

    fun launchTakePhoto(ctx: Context) {
        try {
            val f = createTempPhotoFile(ctx)
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
            pendingPhotoFile = f
            takePictureLauncher.launch(uri)
        } catch (e: Exception) { error = "Photo err: ${e.message}" }
    }

    fun takePhoto() {
        val p = Manifest.permission.CAMERA
        if (ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED) launchTakePhoto(context)
        else permissionLauncher.launch(p)
    }

    fun doLogin(u: String, p: String) {
        scope.launch {
            isLoading = true; error = null
            try {
                api.discoverWorkingEndpoint()
                val r = api.login(u, p)
                if (r.ok == true || r.user != null) {
                    user = r.user ?: u; isLoggedIn = true; currentScreen = "main"
                    refreshData(api, { checkins = it }, { wishlist = it }, { stats = it })
                } else error = r.error ?: "Login failed"
            } catch (e: Exception) { error = "Err: ${e.message}" }
            isLoading = false
        }
    }

    fun doLogout() { scope.launch { api.logout(); isLoggedIn = false; user = ""; currentScreen = "main" } }

    fun submitCheckin() {
        scope.launch {
            isLoading = true; error = null
            try {
                val r = rating.coerceIn(0.25f, 5.0f).toDouble()
                val data = mapOf<String, Any?>(
                    "beer_name" to beerName,
                    "brewery" to brewery,
                    "style" to (style.ifBlank { "Unknown" }),
                    "rating" to r,
                    "comment" to comment.ifBlank { null },
                    "barcode" to lookupBarcode.filter { it.isDigit() }.ifBlank { null }
                )
                val result = api.createCheckin(data)
                val id = (result["id"] as? Number)?.toInt() ?: 0
                if (photoFile != null && id > 0) {
                    try { api.uploadPhoto(id, photoFile!!) } catch (_: Exception) {}
                }
                error = "Checkin ajouté ✓ (id=$id)"
                refreshData(api, { checkins = it }, { wishlist = it }, { stats = it })
                resetAddForm()
                currentScreen = "history"
            } catch (e: Exception) { error = "Erreur: ${e.message}" }
            isLoading = false
        }
    }

    fun resetAddForm() {
        beerName = ""; brewery = ""; style = ""; comment = ""; rating = 3.0f
        photoFile = null; photoUri = null; pendingPhotoFile = null; lookupBarcode = ""; lookupStatus = ""; wizardStep = 1
    }

    fun goToStep(s: Int) { if (s in 1..4) wizardStep = s }

    // ROOT UI
    Column(modifier = Modifier.fillMaxSize().background(BeerColors.bg).padding(16.dp)) {
        Text("🍺 Beer Log — Android (owner)", style = MaterialTheme.typography.headlineMedium, color = BeerColors.text)
        Text("LAN/VPN uniquement — même chose que iOS", style = MaterialTheme.typography.bodySmall, color = BeerColors.muted)

        if (!isLoggedIn) {
            Spacer(Modifier.height(24.dp))
            var lu by remember { mutableStateOf("eiter") }; var lp by remember { mutableStateOf("") }
            OutlinedTextField(value = lu, onValueChange = { lu = it }, label = { Text("Utilisateur owner") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(value = lp, onValueChange = { lp = it }, label = { Text("Mot de passe") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(12.dp))
            Button(onClick = { doLogin(lu, lp) }, modifier = Modifier.fillMaxWidth(), enabled = !isLoading) { Text(if (isLoading) "Connexion..." else "Se connecter") }
            if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error)
            Text("Base: ${ServerSettings.effectiveBase}", style = MaterialTheme.typography.bodySmall)
        } else {
            Row {
                Text("Connecté: $user", modifier = Modifier.weight(1f), color = BeerColors.text)
                TextButton(onClick = { doLogout() }) { Text("Déconnexion") }
            }
            Spacer(Modifier.height(8.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { currentScreen = "add"; wizardStep = 1 }) { Text("Nouveau") }
                Button(onClick = { currentScreen = "history" }) { Text("Historique") }
                Button(onClick = { currentScreen = "gallery" }) { Text("Galerie") }
                Button(onClick = { currentScreen = "wishlist" }) { Text("Wishlist") }
            }
            Spacer(Modifier.height(16.dp))

            when (currentScreen) {
                "main" -> {
                    Text("Bienvenue ! Utilise « Nouveau » pour le wizard.", color = BeerColors.text)
                    Text("Base: ${ServerSettings.effectiveBase}", color = BeerColors.muted, style = MaterialTheme.typography.bodySmall)
                    Button(onClick = { scope.launch { api.discoverWorkingEndpoint() } }) { Text("Re-prober LAN") }
                }
                "add" -> {
                    // 4-STEP WIZARD
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                            Text("Nouveau checkin", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = BeerColors.text)
                            Text("lookup/enter → photo → rating/comment → review & submit", style = MaterialTheme.typography.bodySmall, color = BeerColors.muted)
                        }

                        WizardStepNav(wizardStep) { if (it <= wizardStep) goToStep(it) }

                        Column(
                            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 2.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            when (wizardStep) {
                                1 -> Step1BeerLookup(
                                    beerName, { beerName = it },
                                    brewery, { brewery = it },
                                    style, { style = it },
                                    lookupBarcode, { lookupBarcode = it; lookupStatus = "" },
                                    lookupStatus,
                                    { code -> scope.launch {
                                        lookupStatus = "Recherche…"
                                        try {
                                            val resp = api.lookup(code.filter { it.isDigit() })
                                            if (resp.ok && !resp.beerName.isNullOrBlank()) {
                                                beerName = resp.beerName ?: beerName
                                                brewery = resp.brewery ?: brewery
                                                style = resp.style ?: style
                                                lookupStatus = "✓ Identifiée"
                                            } else lookupStatus = resp.error ?: "Introuvable (manuel)"
                                        } catch (e: Exception) { lookupStatus = e.message ?: "err" }
                                    } },
                                    { if (beerName.isNotBlank()) goToStep(2) }
                                )
                                2 -> Step2Photo(photoFile, photoUri, { takePhoto() }, {
                                    photoFile = null; photoUri = null; pendingPhotoFile = null
                                }, { goToStep(1) }, { goToStep(3) })
                                3 -> Step3RatingComment(rating, { rating = it }, comment, { comment = it }, beerName, { goToStep(2) }, { goToStep(4) })
                                4 -> Step4ReviewSubmit(beerName, brewery, style, rating, comment, photoFile != null, { goToStep(3) }, { submitCheckin() }, isLoading)
                            }
                            if (!error.isNullOrBlank()) {
                                Text(error!!, color = if (error!!.contains("✓")) BeerColors.ok else MaterialTheme.colorScheme.error)
                            }
                        }

                        Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            TextButton(onClick = { resetAddForm(); currentScreen = "main" }) { Text("Annuler", color = BeerColors.muted) }
                            if (wizardStep > 1) TextButton(onClick = { goToStep(wizardStep-1) }) { Text("← Retour", color = BeerColors.text) }
                        }
                    }
                }
                "history" -> {
                    Text("Historique", style = MaterialTheme.typography.titleMedium, color = BeerColors.text)
                    Button(onClick = { scope.launch { checkins = api.checkins() } }) { Text("Rafraîchir") }
                    LazyColumn { items(checkins) { itm ->
                        Card(Modifier.padding(4.dp).fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = BeerColors.card)) {
                            Column(Modifier.padding(8.dp)) {
                                Text("${itm.beerName} — ${itm.brewery ?: ""}", color = BeerColors.text)
                                Text("Note ${itm.rating} ${itm.style ?: ""}", color = BeerColors.muted)
                                if (!itm.comment.isNullOrBlank()) Text(itm.comment!!, color = BeerColors.text)
                                if (!itm.photoURL.isNullOrBlank()) AsyncImage(itm.photoURL, null, Modifier.height(110.dp))
                            }
                        }
                    }}
                }
                "gallery" -> {
                    Text("Galerie", style = MaterialTheme.typography.titleMedium, color = BeerColors.text)
                    val ph = checkins.filter { !it.photoURL.isNullOrBlank() }
                    LazyColumn { items(ph) { itm -> AsyncImage(itm.photoURL, itm.beerName, Modifier.fillMaxWidth().height(160.dp)); Text(itm.beerName, color = BeerColors.muted) } }
                }
                "wishlist" -> {
                    Text("Wishlist", style = MaterialTheme.typography.titleMedium, color = BeerColors.text)
                    Button(onClick = { scope.launch { wishlist = api.wishlist() } }) { Text("Charger") }
                    var nn by remember { mutableStateOf("") }
                    OutlinedTextField(nn, { nn = it }, label = { Text("Nom") })
                    Button({ scope.launch { if (nn.isNotBlank()) { api.addWishlist(nn, "", ""); wishlist = api.wishlist(); nn = "" } } }) { Text("Ajouter") }
                    LazyColumn { items(wishlist) { w -> Text("• ${w.beerName}", color = BeerColors.text); TextButton({ scope.launch { api.deleteWishlist(w.id); wishlist = api.wishlist() } }) { Text("Suppr") } } }
                }
            }
            if (isLoading) CircularProgressIndicator(color = BeerColors.accent)
        }
    }
}

private suspend fun refreshData(api: BeerAPI, c: (List<CheckinItem>) -> Unit, w: (List<WishlistItem>) -> Unit, s: (HistoryStats?) -> Unit) {
    try { c(api.checkins(30)); w(api.wishlist()); s(api.stats()) } catch (_: Exception) {}
}

// Wizard helpers - header progress + 4 steps (iOS feel)
@Composable
fun WizardStepNav(step: Int, onSel: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(1 to "1. Bière", 2 to "2. Photo", 3 to "3. Note", 4 to "4. Valider").forEach { (i, t) ->
            val act = i == step
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(999.dp)).background(if (act) BeerColors.accent else BeerColors.card)
                    .border(1.dp, if (act) Color.Transparent else BeerColors.border, RoundedCornerShape(999.dp))
                    .clickable { onSel(i) }.padding(vertical = 6.dp),
                Alignment.Center
            ) { Text(t, color = if (act) BeerColors.btnPrimaryText else BeerColors.muted, fontSize = 10.sp, fontWeight = if (act) FontWeight.SemiBold else FontWeight.Normal) }
        }
    }
}

@Composable
fun Step1BeerLookup(
    beerName: String, onBeerName: (String) -> Unit,
    brewery: String, onBrewery: (String) -> Unit,
    style: String, onStyle: (String) -> Unit,
    ean: String, onEan: (String) -> Unit,
    status: String,
    onLookup: (String) -> Unit,
    onNext: () -> Unit
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Étape 1 : infos bière (lookup EAN ou saisie manuelle)", color = BeerColors.muted, fontSize = 13.sp)

        Card(colors = CardDefaults.cardColors(BeerColors.card), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("EAN / Code-barres", color = BeerColors.text, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                OutlinedTextField(ean, onEan, label = { Text("ex 5411680001111") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                Button(onClick = { onLookup(ean) }, enabled = ean.length >= 8, colors = ButtonDefaults.buttonColors(BeerColors.card)) { Text("Lookup EAN", color = BeerColors.text) }
                if (status.isNotBlank()) Text(status, color = BeerColors.ok, fontSize = 12.sp)
            }
        }

        Card(colors = CardDefaults.cardColors(BeerColors.card), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(beerName, onBeerName, label = { Text("Nom de la bière *") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(brewery, onBrewery, label = { Text("Brasserie") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(style, onStyle, label = { Text("Style") }, modifier = Modifier.fillMaxWidth())
            }
        }

        Button(onClick = onNext, enabled = beerName.isNotBlank(), modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(BeerColors.accent)) {
            Text("Continuer → photo", color = BeerColors.btnPrimaryText, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun Step2Photo(
    pf: File?, pu: Uri?,
    onTake: () -> Unit, onClear: () -> Unit,
    onBack: () -> Unit, onNext: () -> Unit
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Étape 2 : photo (optionnelle)", color = BeerColors.muted)

        Box(Modifier.fillMaxWidth().height(180.dp).clip(RoundedCornerShape(14.dp)).background(BeerColors.card).border(2.dp, BeerColors.border, RoundedCornerShape(14.dp)).clickable(onClick = onTake), Alignment.Center) {
            if (pu != null) AsyncImage(pu, null, Modifier.fillMaxSize().padding(4.dp).clip(RoundedCornerShape(8.dp)))
            else if (pf != null) AsyncImage(pf, null, Modifier.fillMaxSize().padding(4.dp).clip(RoundedCornerShape(8.dp)))
            else { Text("📷 Prendre la photo du verre", color = BeerColors.muted) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onClear, enabled = pf != null, Modifier.weight(1f)) { Text("Effacer photo") }
            Button(onClick = onTake, Modifier.weight(1f), colors = ButtonDefaults.buttonColors(BeerColors.card)) { Text("📷 Appareil photo", color = BeerColors.text) }
        }
        Button(onClick = onNext, Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(BeerColors.accent)) { Text("Continuer → note", color = BeerColors.btnPrimaryText, fontWeight = FontWeight.SemiBold) }
    }
}

@Composable
fun Step3RatingComment(
    rt: Float, onRt: (Float) -> Unit,
    cm: String, onCm: (String) -> Unit,
    nm: String,
    onBack: () -> Unit, onNext: () -> Unit
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (nm.isNotBlank()) Text(nm, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 16.sp)

        Card(colors = CardDefaults.cardColors(BeerColors.card), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(10.dp)) {
                Text("Note", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                Text("%.2f / 5".format(rt), color = BeerColors.star, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Slider(rt, { onRt(it.coerceIn(0.25f, 5f)) }, valueRange = 0.25f..5f, steps = 18)
            }
        }

        Card(colors = CardDefaults.cardColors(BeerColors.card), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(10.dp)) {
                Text("Commentaire (120 max)", color = BeerColors.text, fontWeight = FontWeight.SemiBold)
                OutlinedTextField(cm, { if (it.length <= 120) onCm(it) }, modifier = Modifier.fillMaxWidth().heightIn(70.dp), placeholder = { Text("Terrasse...") })
                Text("${cm.length}/120", fontSize = 11.sp, color = BeerColors.muted, modifier = Modifier.align(Alignment.End))
            }
        }

        Button(onClick = onNext, enabled = rt >= 0.25f, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(BeerColors.accent)) {
            Text("Continuer → validation", color = BeerColors.btnPrimaryText, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun Step4ReviewSubmit(
    nm: String, br: String, st: String,
    rt: Float, cm: String, hasP: Boolean,
    onBack: () -> Unit, onSub: () -> Unit, busy: Boolean
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Étape 4 : vérification & envoi", color = BeerColors.muted)

        Card(colors = CardDefaults.cardColors(BeerColors.card), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(nm.ifBlank { "— " }, color = BeerColors.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text("Brasserie: ${br.ifBlank { "—" }} · Style: ${st.ifBlank { "Unknown" }}", color = BeerColors.muted, fontSize = 12.sp)
                Text("Note: %.2f/5".format(rt), color = BeerColors.star, fontWeight = FontWeight.SemiBold)
                if (cm.isNotBlank()) Text("Comment: $cm", color = BeerColors.text)
                Text(if (hasP) "Photo: incluse" else "Photo: —", color = BeerColors.muted)
            }
        }

        Button(onClick = onSub, enabled = !busy && nm.isNotBlank(), modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(BeerColors.accent)) {
            Text(if (busy) "Enregistrement..." else "Enregistrer la dégustation", color = BeerColors.btnPrimaryText, fontWeight = FontWeight.SemiBold)
        }
    }
}
