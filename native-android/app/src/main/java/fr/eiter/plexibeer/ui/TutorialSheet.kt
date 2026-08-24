package fr.eiter.plexibeer.ui

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import coil.compose.AsyncImage
import fr.eiter.plexibeer.*
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume



data class TutorialStep(val icon: String, val title: String, val text: String)

val beerTutorialSteps = listOf(
    TutorialStep(
        icon = "🍺",
        title = "Bienvenue sur Beer Log",
        text = "Garde une trace de toutes tes dégustations : quelques secondes suffisent pour scanner, noter et te souvenir de tes bières préférées."
    ),
    TutorialStep(
        icon = "📷",
        title = "1. Trouve ta bière",
        text = "Scanne le code-barres, ou cherche-la sur Untappd (brasserie + nom). Rien trouvé ? La saisie manuelle est toujours là en secours."
    ),
    TutorialStep(
        icon = "📸",
        title = "2. Photo & lieu",
        text = "Ajoute une photo du verre et le lieu de dégustation si tu veux — tout est optionnel, tu peux passer directement à la note."
    ),
    TutorialStep(
        icon = "⭐",
        title = "3. Note & ressenti",
        text = "Glisse le curseur pour la note, choisis les goûts et les houblons qui correspondent, ajoute un petit commentaire si l'envie te prend."
    ),
    TutorialStep(
        icon = "📜",
        title = "Retrouve tout",
        text = "Historique, Galerie photos et recherche : tu retombes toujours sur tes dégustations passées en 2 clics."
    ),
    TutorialStep(
        icon = "🍺🎁",
        title = "À boire & idées cadeaux",
        text = "Ta liste « À boire » garde tes envies de côté. « Idées cadeaux » suggère des bières à offrir selon vos notes à tous les deux."
    ),
    TutorialStep(
        icon = "📖",
        title = "Le Grimoire Beerquest",
        text = "Chaque dégustation te fait gagner de l'XP, débloque des quêtes et des badges. Si le jeu est actif pour toi, retrouve tout ça dans le Grimoire."
    ),
    TutorialStep(
        icon = "✅",
        title = "C'est tout !",
        text = "Tu es prêt·e. Ce tutoriel reste accessible à tout moment depuis Mon compte → Tutoriel."
    ),
)

@Composable
fun TutorialSheet(vm: AppViewModel) {
    var index by remember { mutableIntStateOf(0) }
    val step = beerTutorialSteps[index]
    val isLast = index == beerTutorialSteps.lastIndex

    SheetScaffold("Comment ça marche", onClose = { vm.closeSheet() }) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(step.icon, fontSize = 52.sp)
            Spacer(Modifier.height(14.dp))
            Text(
                step.title,
                color = BeerColors.accent,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(8.dp))
            Text(
                step.text,
                color = BeerColors.muted,
                fontSize = 14.sp,
                lineHeight = 20.sp,
                textAlign = TextAlign.Center
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
            beerTutorialSteps.indices.forEach { i ->
                Box(
                    modifier = Modifier
                        .height(6.dp)
                        .width(if (i == index) 20.dp else 6.dp)
                        .clip(RoundedCornerShape(50))
                        .background(if (i == index) BeerColors.accent else BeerColors.border)
                )
            }
        }

        Spacer(Modifier.height(14.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (index > 0) {
                BeerGhostButton(
                    title = "← Précédent",
                    onClick = { index -= 1 },
                    modifier = Modifier.weight(1f)
                )
            }
            BeerPrimaryButton(
                title = if (isLast) "Compris !" else "Suivant →",
                modifier = Modifier.weight(1f)
            ) {
                if (isLast) vm.closeSheet() else index += 1
            }
        }
    }
}
