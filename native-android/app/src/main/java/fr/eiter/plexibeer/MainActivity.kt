package fr.eiter.plexibeer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import fr.eiter.plexibeer.ui.BeerApp
import fr.eiter.plexibeer.ui.theme.PlexiBeerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Use effective LAN base by default (good for real device / LDPlayer / MuMu on same LAN)
        ServerSettings.useEffectiveBaseIfNeeded()

        setContent {
            PlexiBeerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    BeerApp(context = this@MainActivity)
                }
            }
        }
    }
}