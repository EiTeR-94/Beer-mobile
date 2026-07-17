package fr.eiter.plexibeer

import android.content.Intent
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
        handleInviteIntent(intent)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInviteIntent(intent)
    }

    private fun handleInviteIntent(intent: Intent?) {
        val data = intent?.data?.toString() ?: return
        if (data.contains("/beer/join")) {
            vm.offerInviteLink(data)
        }
    }
}
