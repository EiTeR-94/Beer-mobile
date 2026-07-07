package fr.eiter.plexibeer

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import fr.eiter.plexibeer.ui.theme.PlexiBeerTheme

@Composable
fun PlexiBeerApp() {
    var message by remember { mutableStateOf("PlexiBeer Android - Même logique que iOS native") }
    var isLocalMode by remember { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("PlexiBeer", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(16.dp))
        Text(message)
        Spacer(Modifier.height(16.dp))

        Button(onClick = {
            isLocalMode = true
            message = "Mode Local (WiFi/VPN) - base: ${ServerSettings.lanApiBase}"
        }) {
            Text("Mode Comptes Locaux (LAN)")
        }

        Spacer(Modifier.height(8.dp))

        Button(onClick = {
            isLocalMode = false
            message = "Mode Invité 5G - base: ${ServerSettings.passkeyBaseURLs.first()}"
        }) {
            Text("Mode Invités (5G)")
        }

        Spacer(Modifier.height(16.dp))

        Text("App prête pour build. Logique identique à l'iOS :")
        Text("- Locaux : LAN path")
        Text("- Invités : 5G public path")
    }
}