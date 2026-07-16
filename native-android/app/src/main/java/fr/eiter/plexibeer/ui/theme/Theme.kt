package fr.eiter.plexibeer.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Exact iOS Theme.swift palette — always dark (Beer Log). */
object BeerColors {
    val bg = Color(0xFF0F1419)
    val fieldBg = Color(0xFF0F1419)
    val card = Color(0xFF1A222C)
    val text = Color(0xFFF1F5F9)
    val muted = Color(0xFF94A3B8)
    val accent = Color(0xFFF59E0B)
    val accent2 = Color(0xFFD97706)
    val border = Color(0xFF2D3A4A)
    val star = Color(0xFFFBBF24)
    val starOff = Color(0xFF475569)
    val ok = Color(0xFF34D399)
    val error = Color(0xFFF87171)
    val btnPrimaryText = Color(0xFF1A1208)
    val photoBg = Color(0xFF0A0A0C)
}

private val DarkColors = darkColorScheme(
    primary = BeerColors.accent,
    onPrimary = BeerColors.btnPrimaryText,
    secondary = BeerColors.accent2,
    background = BeerColors.bg,
    surface = BeerColors.card,
    onBackground = BeerColors.text,
    onSurface = BeerColors.text,
    outline = BeerColors.border,
    error = BeerColors.error,
    onError = BeerColors.text
)

private val BeerTypography = Typography(
    headlineLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = BeerColors.text),
    headlineSmall = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = BeerColors.text),
    titleMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = BeerColors.text),
    titleSmall = TextStyle(fontSize = 13.6.sp, fontWeight = FontWeight.SemiBold, color = BeerColors.text),
    bodyLarge = TextStyle(fontSize = 14.sp, color = BeerColors.text),
    bodyMedium = TextStyle(fontSize = 13.sp, color = BeerColors.text),
    bodySmall = TextStyle(fontSize = 12.sp, color = BeerColors.muted),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = TextStyle(fontSize = 11.5.sp, color = BeerColors.muted)
)

@Composable
fun PlexiBeerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
        typography = BeerTypography,
        content = content
    )
}
