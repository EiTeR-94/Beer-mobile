package fr.eiter.plexibeer

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import fr.eiter.plexibeer.ui.theme.PlexiBeerTheme
import kotlinx.coroutines.launch

@Composable
fun PlexiBeerApp() {
    var isLoggedIn by remember { mutableStateOf(false) }
    var isGuest by remember { mutableStateOf(false) }
    var user by remember { mutableStateOf<String?>(null) }
    var checkins by remember { mutableStateOf<List<CheckinItem>>(emptyList()) }
    var showWizard by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = remember { BeerAPI.getInstance(context) }

    if (!isLoggedIn) {
        LoginScreen(
            onLocalLogin = { username, password ->
                scope.launch {
                    try {
                        api.setGuestMode(false)
                        api.setBaseURL(ServerSettings.lanApiBase)
                        val resp = api.login(username, password)
                        if (resp.ok == true) {
                            user = resp.user
                            isGuest = false
                            isLoggedIn = true
                            checkins = api.checkins()
                        } else {
                            // show error
                        }
                    } catch (e: Exception) {
                        // handle timeout etc.
                    }
                }
            },
            onGuestActivate = {
                // For Android, use Passkey / Credential Manager
                // For now, simulate guest login (full passkey impl would use androidx.credentials)
                scope.launch {
                    api.setGuestMode(true)
                    api.setBaseURL(ServerSettings.passkeyBaseURLs.first())
                    // In real: do passkey register/verify like iOS PasskeyAuth
                    user = "invité-5g"
                    isGuest = true
                    isLoggedIn = true
                    checkins = api.checkins()
                }
            }
        )
    } else {
        if (showWizard) {
            BeerWizardScreen(
                api = api,
                isGuest = isGuest,
                onDone = {
                    showWizard = false
                    scope.launch { checkins = api.checkins() }
                },
                onCancel = { showWizard = false }
            )
        } else {
            MainScreen(
                user = user ?: "Utilisateur",
                isGuest = isGuest,
                checkins = checkins,
                onAdd = { showWizard = true },
                onRefresh = { scope.launch { checkins = api.checkins() } },
                onLogout = {
                    isLoggedIn = false
                    user = null
                    checkins = emptyList()
                }
            )
        }
    }
}

@Composable
fun LoginScreen(
    onLocalLogin: (String, String) -> Unit,
    onGuestActivate: () -> Unit
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("PlexiBeer", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(32.dp))

        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("Nom d'utilisateur (local)") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(8.dp))

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Mot de passe") },
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(16.dp))

        Button(
            onClick = { onLocalLogin(username, password) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Connexion (Comptes locaux - WiFi/VPN)")
        }

        Spacer(Modifier.height(8.dp))

        Button(
            onClick = onGuestActivate,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Activer avec Passkey (Invités 5G)")
        }

        Spacer(Modifier.height(16.dp))
        Text(
            "Comptes locaux : uniquement en WiFi ou VPN\n" +
            "Invités : 5G/4G uniquement via passkey",
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
fun MainScreen(
    user: String,
    isGuest: Boolean,
    checkins: List<CheckinItem>,
    onAdd: () -> Unit,
    onRefresh: () -> Unit,
    onLogout: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Bienvenue $user ${if (isGuest) "(Invité 5G)" else ""}", style = MaterialTheme.typography.headlineSmall)
            Button(onClick = onLogout) { Text("Déconnexion") }
        }

        Spacer(Modifier.height(16.dp))

        Button(onClick = onAdd, modifier = Modifier.fillMaxWidth()) {
            Text("+ Nouvelle dégustation")
        }

        Spacer(Modifier.height(8.dp))

        Button(onClick = onRefresh, modifier = Modifier.fillMaxWidth()) {
            Text("Rafraîchir")
        }

        Spacer(Modifier.height(16.dp))

        Text("Historique", style = MaterialTheme.typography.titleMedium)
        LazyColumn {
            items(checkins) { item ->
                Card(modifier = Modifier.padding(4.dp).fillMaxWidth()) {
                    Column(Modifier.padding(8.dp)) {
                        Text("${item.beer_name} - ${item.brewery}")
                        Text("Style: ${item.style}  Note: ${item.rating ?: "?"}")
                        item.comment?.let { Text(it) }
                    }
                }
            }
        }
    }
}

// Simplified Wizard matching iOS BeerWizardView
@Composable
fun BeerWizardScreen(
    api: BeerAPI,
    isGuest: Boolean,
    onDone: () -> Unit,
    onCancel: () -> Unit
) {
    var beerName by remember { mutableStateOf("") }
    var brewery by remember { mutableStateOf("") }
    var style by remember { mutableStateOf("") }
    var rating by remember { mutableStateOf(3.0) }
    var comment by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("Nouvelle dégustation", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))

        OutlinedTextField(value = beerName, onValueChange = { beerName = it }, label = { Text("Nom de la bière") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = brewery, onValueChange = { brewery = it }, label = { Text("Brasserie") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = style, onValueChange = { style = it }, label = { Text("Style") }, modifier = Modifier.fillMaxWidth())

        Spacer(Modifier.height(16.dp))
        Text("Note: ${rating}")
        Slider(value = rating.toFloat(), onValueChange = { rating = it.toDouble() }, valueRange = 0f..5f, steps = 9)

        OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("Commentaire") }, modifier = Modifier.fillMaxWidth())

        Spacer(Modifier.height(24.dp))

        Row {
            Button(onClick = onCancel, modifier = Modifier.weight(1f)) { Text("Annuler") }
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = {
                    scope.launch {
                        val data = mapOf(
                            "beer_name" to beerName,
                            "brewery" to brewery,
                            "style" to style,
                            "rating" to rating,
                            "comment" to comment,
                            "abv" to "5.0", // placeholder
                            "flavors" to "[]",
                            "hops" to "[]"
                        )
                        try {
                            api.createCheckin(data)
                            onDone()
                        } catch (e: Exception) {
                            // error handling
                        }
                    }
                },
                modifier = Modifier.weight(1f)
            ) { Text("Enregistrer") }
        }

        Text("Note: Barcode scanner + photo à implémenter comme dans l'iOS (CameraX + MLKit)", style = MaterialTheme.typography.bodySmall)
    }
}