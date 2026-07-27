import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

class LovTheme {
  const LovTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? LovColors.accentDark : LovColors.accent,
      onPrimary: isDark ? LovColors.backgroundDark : Colors.white,
      secondary: isDark ? LovColors.accentSoftDark : LovColors.accentSoft,
      onSecondary: isDark ? LovColors.accentInkDark : LovColors.accentInk,
      surface: isDark ? LovColors.surfaceDark : LovColors.surface,
      onSurface: isDark ? LovColors.textPrimaryDark : LovColors.textPrimary,
      surfaceContainerLow: isDark
          ? LovColors.surfaceMutedDark
          : LovColors.surfaceMuted,
      surfaceContainerHigh: isDark
          ? LovColors.surfaceDark
          : LovColors.surface,
      outlineVariant: isDark ? LovColors.dividerDark : LovColors.divider,
      error: LovColors.error,
      onError: Colors.white,
    );

    final textTheme = LovTypography.build(brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? LovColors.backgroundDark : LovColors.background,
      textTheme: textTheme,
      fontFamily: LovTypography.body,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(
        color: isDark ? LovColors.dividerDark : LovColors.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? LovColors.backgroundDark : LovColors.background,
        foregroundColor:
            isDark ? LovColors.textPrimaryDark : LovColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? LovColors.surfaceMutedDark : LovColors.surfaceMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: isDark
              ? LovColors.textTertiaryDark
              : LovColors.textTertiary,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: isDark
              ? LovColors.textSecondaryDark
              : LovColors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LovRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LovRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LovSpace.lg,
          vertical: LovSpace.md + 2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? LovColors.surfaceMutedDark : LovColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark
              ? LovColors.textPrimaryDark
              : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LovRadius.md),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? LovColors.surfaceDark : LovColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LovRadius.md),
          side: BorderSide(
            color: isDark ? LovColors.dividerDark : LovColors.divider,
          ),
        ),
        textStyle: textTheme.bodyMedium,
      ),
    );
  }
}
