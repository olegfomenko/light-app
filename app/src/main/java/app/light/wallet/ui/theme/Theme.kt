package app.light.wallet.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.light.wallet.R

// Design tokens — "Bitcoin Lightning Wallet Design" (Lightning Wallet.dc.html).
// Visual direction adapted from "Crypto Wallet App UI Template" by DSCODE.
object Tokens {
    val Bg = Color(0xFF0A0E12)
    val Card = Color(0xFF11171E)          // list rows / cards
    val CardDeep = Color(0xFF0D1319)      // inputs / kv panels
    val Sheet = Color(0xFF10161D)
    val Field = Color(0xFF131A21)
    val Text = Color(0xFFEEF3F6)
    val TextMid = Color(0xFFB7C2CC)
    val Dim = Color(0xFF7E8B99)
    val Faint = Color(0xFF5A6673)
    val Label = Color(0xFF9FB0BC)
    val Accent = Color(0xFFFACC15)
    val AccentHi = Color(0xFFFDE047)
    val AccentInk = Color(0xFF241A02)
    val Green = Color(0xFF34D399)
    val Red = Color(0xFFF8716F)
    val Orange = Color(0xFFFB923C)
    val OrangeSoft = Color(0xFFFDBA74)
    val Purple = Color(0xFFA78BFA)
    val Btc = Color(0xFFF7931A)
    val Border = Color(0x12FFFFFF)        // rgba(255,255,255,.07)
    val BorderSoft = Color(0x0DFFFFFF)    // rgba(255,255,255,.05)
}

val Manrope = FontFamily(
    Font(R.font.manrope_regular, FontWeight.Normal),
    Font(R.font.manrope_medium, FontWeight.Medium),
    Font(R.font.manrope_semibold, FontWeight.SemiBold),
    Font(R.font.manrope_bold, FontWeight.Bold),
    Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
)

// ui-monospace in the design; SF Mono is not redistributable, JetBrains Mono
// is the closest open equivalent.
val MonoFont = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
    Font(R.font.jetbrains_mono_semibold, FontWeight.SemiBold),
    Font(R.font.jetbrains_mono_bold, FontWeight.Bold),
)

val SpaceGrotesk = FontFamily(
    Font(R.font.space_grotesk_regular, FontWeight.Normal),
    Font(R.font.space_grotesk_medium, FontWeight.Medium),
    Font(R.font.space_grotesk_semibold, FontWeight.SemiBold),
    Font(R.font.space_grotesk_bold, FontWeight.Bold),
)

private val DarkColors = darkColorScheme(
    primary = Tokens.Accent,
    onPrimary = Tokens.AccentInk,
    secondary = Tokens.Purple,
    background = Tokens.Bg,
    surface = Tokens.Card,
    surfaceVariant = Tokens.CardDeep,
    onBackground = Tokens.Text,
    onSurface = Tokens.Text,
    error = Tokens.Red,
    outline = Tokens.Border,
)

private val AppTypography = Typography(
    displaySmall = TextStyle(          // balance numerals
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold,
        fontSize = 32.sp, letterSpacing = (-0.5).sp,
    ),
    headlineSmall = TextStyle(         // tab titles
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold, fontSize = 24.sp,
    ),
    titleMedium = TextStyle(           // sheet titles / section headers
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold, fontSize = 19.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold, fontSize = 15.sp,
    ),
    bodyLarge = TextStyle(fontFamily = Manrope, fontSize = 15.sp),
    bodyMedium = TextStyle(fontFamily = Manrope, fontSize = 14.sp),
    bodySmall = TextStyle(fontFamily = Manrope, fontSize = 12.5.sp),
    labelLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp),
    labelMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 12.5.sp),
    labelSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 12.5.sp),
)

@Composable
fun LightAppTheme(content: @Composable () -> Unit) {
    // The design is dark-only by intent. The Surface pins LocalContentColor
    // to the design's text color for every screen.
    MaterialTheme(colorScheme = DarkColors, typography = AppTypography) {
        Surface(color = Tokens.Bg, contentColor = Tokens.Text, content = content)
    }
}
