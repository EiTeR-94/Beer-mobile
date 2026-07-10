package fr.eiter.plexibeer.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Couleurs inspirées du Theme.swift iOS (dark mode dominant pour Beer Log)
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
    val ok = Color(0xFF34D399)
    val error = Color(0xFFF87171)
    val btnPrimaryText = Color(0xFF1A1208)
    val photoBg = Color(0xFF0A0A0C)
}

private val LightColors = lightColorScheme(
    primary = Color(0xFF8B5CF6),
    onPrimary = Color.White,
    background = Color(0xFFF8F1E9),
    surface = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = BeerColors.accent,
    onPrimary = BeerColors.btnPrimaryText,
    background = BeerColors.bg,
    surface = BeerColors.card,
    onSurface = BeerColors.text,
    outline = BeerColors.border,
)

@Composable
fun PlexiBeerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colors = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colors,
        content = content
    )
}