package com.nurtrino.hackernews.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isUnspecified
import com.nurtrino.hackernews.data.AppearanceMode
import com.nurtrino.hackernews.data.TextScale

/** The app icon's orange. */
val HnOrange = Color(0xFFFC5403)

/**
 * Per-depth rail colours for comment threads, and the source monograms.
 * Chosen to stay legible on both the light and dark surfaces.
 */
val ThreadPalette = listOf(
    HnOrange,
    Color(0xFF4C9EEB),
    Color(0xFF5CBD7A),
    Color(0xFFD971B8),
    Color(0xFF9985EB),
    Color(0xFFF0B83D),
    Color(0xFF66C7C7),
)

fun threadColor(depth: Int): Color = ThreadPalette[(if (depth < 0) -depth else depth) % ThreadPalette.size]

/** Stable colour for a string, so a domain always looks the same. */
fun stableColor(seed: String): Color {
    var hash = 5381L
    for (byte in seed.encodeToByteArray()) hash = hash * 33 + byte
    val index = ((hash % ThreadPalette.size) + ThreadPalette.size) % ThreadPalette.size
    return ThreadPalette[index.toInt()]
}

private val LightColors = lightColorScheme(
    primary = HnOrange,
    secondary = HnOrange,
    tertiary = HnOrange,
)

private val DarkColors = darkColorScheme(
    primary = HnOrange,
    secondary = HnOrange,
    tertiary = HnOrange,
)

object Metrics {
    const val MAX_INDENT_DEPTH = 8
}

@Composable
fun HackerNewsTheme(
    appearance: AppearanceMode,
    textScale: TextScale,
    content: @Composable () -> Unit,
) {
    val dark = when (appearance) {
        AppearanceMode.SYSTEM -> isSystemInDarkTheme()
        AppearanceMode.LIGHT -> false
        AppearanceMode.DARK -> true
    }

    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        typography = scaledTypography(textScale.factor),
        content = content,
    )
}

/** Applies the Settings text-size multiplier across the whole type scale. */
private fun scaledTypography(factor: Float): Typography {
    if (factor == 1.0f) return Typography()
    val base = Typography()

    fun TextStyle.scaled(): TextStyle = copy(
        fontSize = fontSize.scale(factor),
        lineHeight = lineHeight.scale(factor),
    )

    return Typography(
        displayLarge = base.displayLarge.scaled(),
        displayMedium = base.displayMedium.scaled(),
        displaySmall = base.displaySmall.scaled(),
        headlineLarge = base.headlineLarge.scaled(),
        headlineMedium = base.headlineMedium.scaled(),
        headlineSmall = base.headlineSmall.scaled(),
        titleLarge = base.titleLarge.scaled(),
        titleMedium = base.titleMedium.scaled(),
        titleSmall = base.titleSmall.scaled(),
        bodyLarge = base.bodyLarge.scaled(),
        bodyMedium = base.bodyMedium.scaled(),
        bodySmall = base.bodySmall.scaled(),
        labelLarge = base.labelLarge.scaled(),
        labelMedium = base.labelMedium.scaled(),
        labelSmall = base.labelSmall.scaled(),
    )
}

private fun TextUnit.scale(factor: Float): TextUnit =
    if (isUnspecified) this else this * factor
