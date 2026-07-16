package fr.eiter.plexibeer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import fr.eiter.plexibeer.ui.BeerApp
import fr.eiter.plexibeer.ui.theme.BeerColors
import fr.eiter.plexibeer.ui.theme.PlexiBeerTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ServerSettings.useEffectiveBaseIfNeeded()
        setContent {
            PlexiBeerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = BeerColors.bg
                ) {
                    BeerApp(vm = vm)
                }
            }
        }
    }
}
