import 'package:flutter/material.dart';

import 'tokens.dart';

/// Space Grotesk (display) · Inter (body) · Amiri (Arabic).
/// Bundled locally under [assets/fonts/].
class LovTypography {
  const LovTypography._();

  static const String display = 'SpaceGrotesk';
  static const String body = 'Inter';
  static const String arabic = 'Amiri';

  static TextTheme build({required Brightness brightness}) {
    final baseColor = brightness == Brightness.dark
        ? LovColors.textPrimaryDark
        : LovColors.textPrimary;
    final subColor = brightness == Brightness.dark
        ? LovColors.textSecondaryDark
        : LovColors.textSecondary;

    return TextTheme(
      // Display — Space Grotesk, tight-leading, negative tracking
      displayLarge: TextStyle(
        fontFamily: display,
        fontSize: 48,
        fontWeight: FontWeight.w500,
        height: 1.05,
        letterSpacing: -1.2,
        color: baseColor,
      ),
      displayMedium: TextStyle(
        fontFamily: display,
        fontSize: 36,
        fontWeight: FontWeight.w500,
        height: 1.1,
        letterSpacing: -0.8,
        color: baseColor,
      ),
      displaySmall: TextStyle(
        fontFamily: display,
        fontSize: 28,
        fontWeight: FontWeight.w500,
        height: 1.15,
        letterSpacing: -0.4,
        color: baseColor,
      ),
      headlineLarge: TextStyle(
        fontFamily: display,
        fontSize: 24,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: baseColor,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),

      // Titles — Inter, semibold
      titleLarge: TextStyle(
        fontFamily: body,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: baseColor,
      ),
      titleMedium: TextStyle(
        fontFamily: body,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),

      // Body — Inter, relaxed
      bodyLarge: TextStyle(
        fontFamily: body,
        fontSize: 16,
        height: 1.5,
        color: baseColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: body,
        fontSize: 14,
        height: 1.5,
        color: baseColor,
      ),
      bodySmall: TextStyle(
        fontFamily: body,
        fontSize: 12,
        height: 1.4,
        color: subColor,
      ),

      // Labels — Inter, tuned for buttons + tiny UI
      labelLarge: TextStyle(
        fontFamily: body,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: baseColor,
      ),
      labelMedium: TextStyle(
        fontFamily: body,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: baseColor,
      ),
      labelSmall: TextStyle(
        fontFamily: body,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: subColor,
      ),
    );
  }

  /// Amiri for Arabic text (Qur'an verses, du'a, calligraphy contexts).
  static TextStyle arabicText({
    double fontSize = 22,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: arabic,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: 1.9,
    );
  }
}
