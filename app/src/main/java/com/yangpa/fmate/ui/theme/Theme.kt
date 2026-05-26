package com.yangpa.fmate.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val FieldGreen = Color(0xFF0F8F43)
val FreshGreen = Color(0xFF25C767)
val PitchDark = Color(0xFF162317)
val WarmSand = Color(0xFFF2EAD9)
val SurfaceCream = Color(0xFFFFFCF6)
val CitrusOrange = Color(0xFFFF8A2A)
val TeamBlue = Color(0xFF234B8D)
val Ink = Color(0xFF142114)
val MutedInk = Color(0xFF657166)

private val FMateColors = lightColorScheme(
    primary = FieldGreen,
    onPrimary = Color.White,
    secondary = CitrusOrange,
    onSecondary = Color.White,
    tertiary = TeamBlue,
    background = WarmSand,
    onBackground = Ink,
    surface = SurfaceCream,
    onSurface = Ink,
)

private val FMateTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 32.sp,
        lineHeight = 38.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 24.sp,
        lineHeight = 30.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 20.sp,
        lineHeight = 26.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 21.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 14.sp,
        lineHeight = 18.sp,
    ),
)

@Composable
fun FMateTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = FMateColors,
        typography = FMateTypography,
        content = content,
    )
}
