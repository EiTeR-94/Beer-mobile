package fr.eiter.plexibeer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import fr.eiter.plexibeer.AdminFeedbackItem
import fr.eiter.plexibeer.AdminFeedbackStats
import fr.eiter.plexibeer.AppViewModel
import fr.eiter.plexibeer.RpgAdminFlags
import fr.eiter.plexibeer.RpgAdminPlayer
import fr.eiter.plexibeer.RpgAdminPlayerDetail
import fr.eiter.plexibeer.RpgAdminPlayersResponse
import fr.eiter.plexibeer.RpgBadge
import fr.eiter.plexibeer.RpgCelebration
import fr.eiter.plexibeer.RpgClassInfo
import fr.eiter.plexibeer.RpgLoot
import fr.eiter.plexibeer.RpgProfile
import fr.eiter.plexibeer.RpgQuest
import fr.eiter.plexibeer.RpgState
import fr.eiter.plexibeer.ToastPayload
import fr.eiter.plexibeer.displayIcon
import fr.eiter.plexibeer.rarityLabelFr
import fr.eiter.plexibeer.ui.theme.BeerColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


@Composable
fun SectionTitle(t: String) {
    Text(
        t,
        color = BeerColors.text,
        fontWeight = FontWeight.Bold,
        fontSize = 14.sp,
        modifier = Modifier.padding(bottom = 6.dp)
    )
}

@Composable
fun StatTile(ico: String, value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .border(1.dp, BeerColors.border, RoundedCornerShape(10.dp))
            .background(BeerColors.card)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(ico, fontSize = 14.sp)
        Text(value, color = BeerColors.text, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
        Text(label, color = BeerColors.muted, fontSize = 9.sp)
    }
}
