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
    var message by remember { mutableStateOf("PlexiBeer Android — owner only (LAN/VPN)") }

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
            ServerSettings.resetToLan()
            message = "Base effective:\n${ServerSettings.effectiveBase}\n\nSur émulateur Windows : utilise les boutons dans MainActivity ou entre 10.0.2.2 si besoin."
        }) {
            Text("Reset base LAN")
        }

        Spacer(Modifier.height(8.dp))

        Text("Owner-only. Pas de guest 5G.")
        Text("PWA web pour les invités.")
        Text("Test sur Windows : LDPlayer / MuMu + artifact CI est le plus simple.")
    }
}