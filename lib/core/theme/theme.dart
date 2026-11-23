import 'package:flutter/material.dart';

import 'lov_palette.dart';
import 'typography.dart';

export 'lov_palette.dart';

/// Builds the app [ThemeData] from one of the seven [LovThemeId] palettes so
/// stock Material widgets (sheets, dialogs, switches, fields, snackbars,
/// chips) already match the design before any custom widget is involved.
class LovTheme {
  const LovTheme._();

  static ThemeData light() => of(LovThemeId.sandstone);
  static ThemeData dark() => of(LovThemeId.midnight);

  static ThemeData of(LovThemeId id) => _build(id.palette);

  static ThemeData _build(LovPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accentInk,
      secondary: p.partner,
      onSecondary: p.onPartner,
      secondaryContainer: p.partnerSoft,
      onSecondaryContainer: p.partnerHi,
      tertiary: p.accentHi,
      onTertiary: p.onAccent,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.bg2,
      surfaceContainerLow: p.cardB,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: p.surface2,
      outline: p.line2,
      outlineVariant: p.line,
      error: const Color(0xFFE5534B),
      onError: Colors.white,
      shadow: p.shadow,
      scrim: p.shadow,
      inverseSurface: p.text,
      onInverseSurface: p.bg,
      inversePrimary: p.accentLo,
    );

    final base = LovTypography.build(
      brightness: p.brightness,
    ).apply(bodyColor: p.text, displayColor: p.text);
    final text = base.copyWith(
      bodySmall: base.bodySmall?.copyWith(color: p.muted),
      labelSmall: base.labelSmall?.copyWith(color: p.muted),
    );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    const stadium = StadiumBorder();
    final buttonText = text.labelLarge?.copyWith(fontSize: 16);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      textTheme: text,
      fontFamily: LovTypography.body,
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.hi.withValues(alpha: .04),
      hoverColor: p.hi.withValues(alpha: .05),
      dividerTheme: DividerThemeData(color: p.surface2, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.text, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: LovTypography.display,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
          color: p.text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.hi.withValues(alpha: .04),
        hintStyle: text.bodyLarge?.copyWith(color: p.faint),
        labelStyle: text.bodyMedium?.copyWith(color: p.muted),
        border: field(p.line),
        enabledBorder: field(p.line),
        focusedBorder: field(p.accent.withValues(alpha: .7), 1.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.surface2,
          disabledForegroundColor: p.faint,
          minimumSize: const Size(64, 54),
          shape: stadium,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          minimumSize: const Size(64, 54),
          shape: stadium,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.hi.withValues(alpha: .04),
          side: BorderSide(color: p.hi.withValues(alpha: .1)),
          minimumSize: const Size(64, 54),
          shape: stadium,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          minimumSize: const Size(44, 44),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(44, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        shape: const CircleBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFFFFDF8)),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.line,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        checkColor: WidgetStateProperty.all(p.onAccent),
        side: BorderSide(color: p.line2, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.line2,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: p.accent.withValues(alpha: .14),
        side: BorderSide(color: p.line),
        shape: stadium,
        labelStyle: text.bodyMedium?.copyWith(
          color: p.text2,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: text.bodyMedium?.copyWith(color: p.text),
        checkmarkColor: p.accent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.muted,
          selectedBackgroundColor: p.line,
          selectedForegroundColor: p.text,
          side: BorderSide(color: p.line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface.withValues(alpha: .97),
        modalBackgroundColor: p.surface.withValues(alpha: .97),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.line2,
        dragHandleSize: const Size(36, 5),
        modalBarrierColor: p.shadow.withValues(alpha: .5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: LovTypography.display,
          fontSize: 21,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surface,
        elevation: 0,
        actionTextColor: p.accent,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
        contentTextStyle: text.bodyMedium?.copyWith(color: p.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.hi.withValues(alpha: .09)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.line),
        ),
        textStyle: text.bodyMedium,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.line),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.accent,
        textColor: p.text,
        minTileHeight: 58,
        subtitleTextStyle: text.bodySmall?.copyWith(fontSize: 12.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surface2,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.line,
        thumbColor: p.accentHi,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.text,
        unselectedLabelColor: p.muted,
        indicatorColor: p.accent,
        dividerColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.partner,
        textColor: p.onPartner,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: .3),
        selectionHandleColor: p.accent,
      ),
      extensions: [p],
    );
  }
}

extension LovContext on BuildContext {
  /// The active design palette (falls back to Midnight outside a Lov theme).
  LovPalette get lov =>
      Theme.of(this).extension<LovPalette>() ?? LovThemeId.midnight.palette;

  /// True when the user asked the OS to reduce motion.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Whether endless decorative loops (glow drift, sheen, beam) may run.
  bool get allowLoops => lovLoopingMotion && !reduceMotion;
}

/// Global switch for endless decorative animation. Widget tests turn it off
/// (test/flutter_test_config.dart) so pumpAndSettle can settle.
bool lovLoopingMotion = true;
