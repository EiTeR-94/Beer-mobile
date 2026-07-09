package fr.eiter.plexibeer.ui

import android.content.Context
import android.content.Intent
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

@Composable
fun BeerApp(context: Context) {
    val scope = rememberCoroutineScope()
    val api = remember { BeerAPI.getInstance(context) }

    var isLoggedIn by remember { mutableStateOf(false) }
    var user by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var currentScreen by remember { mutableStateOf("main") } // main, add, history, gallery, wishlist

    // Checkins and data
    var checkins by remember { mutableStateOf(listOf<CheckinItem>()) }
    var wishlist by remember { mutableStateOf(listOf<WishlistItem>()) }
    var stats by remember { mutableStateOf<HistoryStats?>(null) }

    // New checkin form state (wizard like)
    var beerName by remember { mutableStateOf("") }
    var brewery by remember { mutableStateOf("") }
    var style by remember { mutableStateOf("") }
    var rating by remember { mutableStateOf(7.5f) }
    var comment by remember { mutableStateOf("") }
    var photoFile by remember { mutableStateOf<File?>(null) }
    var lookupBarcode by remember { mutableStateOf("") }

    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        // Simple intent camera result handling (basic for now)
        if (result.resultCode == android.app.Activity.RESULT_OK) {
            // In real, we would get the file. For demo we create a temp note.
            // For full, we would copy the bitmap to file.
            error = "Photo prise (simplifié). Utilise la galerie pour tester l'upload complet."
        }
    }

    fun takePhoto() {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        cameraLauncher.launch(intent)
    }

    // Login
    fun doLogin(username: String, password: String) {
        scope.launch {
            isLoading = true
            error = null
            try {
                // Try discover first for best LAN endpoint
                api.discoverWorkingEndpoint()
                val resp = api.login(username, password)
                if (resp.ok == true || resp.user != null) {
                    user = resp.user ?: username
                    isLoggedIn = true
                    currentScreen = "main"
                    // Load initial data
                    refreshData(api, checkins = { checkins = it }, wishlist = { wishlist = it }, stats = { stats = it })
                } else {
                    error = resp.error ?: "Login échoué"
                }
            } catch (e: Exception) {
                error = "Erreur: ${e.message ?: "connexion impossible (LAN/VPN ?)"}"
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

    // Submit new checkin (core wizard action)
    fun submitCheckin() {
        scope.launch {
            isLoading = true
            try {
                val data = mapOf(
                    "beer_name" to beerName,
                    "brewery" to brewery,
                    "style" to (style.ifBlank { "Unknown" }),
                    "rating" to rating,
                    "comment" to comment.ifBlank { null }
                )
                val result = api.createCheckin(data)
                // If photo selected in future, upload here
                photoFile?.let { file ->
                    // For now photo handling is simplified
                }
                error = "Checkin ajouté !"
                // Refresh
                refreshData(api, checkins = { checkins = it }, wishlist = { wishlist = it }, stats = { stats = it })
                // Reset form
                beerName = ""; brewery = ""; style = ""; comment = ""; rating = 7.5f; photoFile = null
                currentScreen = "history"
            } catch (e: Exception) {
                error = "Erreur ajout: ${e.message}"
            }
            isLoading = false
        }
    }

    // Simple UI
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("🍺 Beer Log — Android (owner)", style = MaterialTheme.typography.headlineMedium, color = BeerColors.text)
        Text("LAN/VPN uniquement — même chose que iOS", style = MaterialTheme.typography.bodySmall, color = BeerColors.muted)

        if (!isLoggedIn) {
            // LOGIN SCREEN (owner only)
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

        // LOGGED IN
        Row {
            Text("Connecté: $user", modifier = Modifier.weight(1f))
            TextButton(onClick = { doLogout() }) { Text("Déconnexion") }
        }

        Spacer(Modifier.height(8.dp))

        // HEADER BUTTONS like iOS
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { currentScreen = "add" }) { Text("Nouveau") }
            Button(onClick = { currentScreen = "history" }) { Text("Historique") }
            Button(onClick = { currentScreen = "gallery" }) { Text("Galerie") }
            Button(onClick = { currentScreen = "wishlist" }) { Text("Wishlist") }
        }

        Spacer(Modifier.height(16.dp))

        when (currentScreen) {
            "main" -> {
                Text("Bienvenue ! Utilise les boutons ci-dessus.")
                Text("Base active: ${ServerSettings.effectiveBase}", style = MaterialTheme.typography.bodySmall)
                Button(onClick = { scope.launch { api.discoverWorkingEndpoint() } }) { Text("Re-prober LAN") }
            }
            "add" -> {
                // WIZARD / ADD CHECKIN
                Text("Nouveau checkin (comme le wizard iOS)", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(value = beerName, onValueChange = { beerName = it }, label = { Text("Nom de la bière") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = brewery, onValueChange = { brewery = it }, label = { Text("Brasserie") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = style, onValueChange = { style = it }, label = { Text("Style") }, modifier = Modifier.fillMaxWidth())
                Text("Note: ${rating.toInt()}/10")
                Slider(value = rating, onValueChange = { rating = it }, valueRange = 1f..10f, steps = 8)
                OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("Commentaire") }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
                Row {
                    Button(onClick = { takePhoto() }) { Text("📷 Prendre photo") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { submitCheckin() }, enabled = beerName.isNotBlank()) { Text("Enregistrer") }
                }
                if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error)
            }
            "history" -> {
                Text("Historique des checkins", style = MaterialTheme.typography.titleMedium)
                Button(onClick = { scope.launch { checkins = api.checkins() } }) { Text("Rafraîchir") }
                LazyColumn {
                    items(checkins) { item ->
                        Card(Modifier.padding(4.dp).fillMaxWidth()) {
                            Column(Modifier.padding(8.dp)) {
                                Text("${item.beerName} — ${item.brewery ?: ""}", style = MaterialTheme.typography.titleSmall)
                                Text("Note: ${item.rating}  ${item.style ?: ""}")
                                if (!item.comment.isNullOrBlank()) Text(item.comment)
                                if (!item.photoURL.isNullOrBlank()) {
                                    AsyncImage(model = item.photoURL, contentDescription = null, modifier = Modifier.height(120.dp))
                                }
                            }
                        }
                    }
                }
            }
            "gallery" -> {
                Text("Galerie photos", style = MaterialTheme.typography.titleMedium)
                val photos = checkins.filter { !it.photoURL.isNullOrBlank() }
                LazyColumn {
                    items(photos) { item ->
                        AsyncImage(model = item.photoURL, contentDescription = item.beerName, modifier = Modifier.fillMaxWidth().height(180.dp))
                        Text(item.beerName)
                    }
                }
            }
            "wishlist" -> {
                Text("Wishlist", style = MaterialTheme.typography.titleMedium)
                Button(onClick = { scope.launch { wishlist = api.wishlist() } }) { Text("Charger wishlist") }
                // Simple add
                var newName by remember { mutableStateOf("") }
                OutlinedTextField(value = newName, onValueChange = { newName = it }, label = { Text("Bière à ajouter") })
                Button(onClick = { scope.launch { if (newName.isNotBlank()) { api.addWishlist(newName, "", ""); wishlist = api.wishlist(); newName = "" } } }) { Text("Ajouter") }
                LazyColumn {
                    items(wishlist) { w ->
                        Text("• ${w.beerName} (${w.brewery ?: ""})")
                        TextButton(onClick = { scope.launch { api.deleteWishlist(w.id); wishlist = api.wishlist() } }) { Text("Supprimer") }
                    }
                }
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