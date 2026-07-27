import 'package:flutter/material.dart';

/// Design tokens for Lovinity — Together in Every Prayer palette.
///
/// Dark mode is the hero look: near-black surfaces, bright gold accent,
/// sampled from the Lovinity mark. Light mode is a warm cream/gold variant
/// of the same palette, not a separate cool theme.
/// Warm neutrals reserved for Arabic script rendering only.
class LovColors {
  const LovColors._();

  // ---- Light (warm cream + bronze gold) ----
  static const Color background = Color(0xFFFBF6EC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0E6D0);
  static const Color surfaceSunken = Color(0xFFF6EEDC);
  static const Color accent = Color(0xFFA6690F);
  static const Color accentSoft = Color(0xFFF3E3C0);
  static const Color accentInk = Color(0xFF6B4509);
  static const Color textPrimary = Color(0xFF1A1610);
  static const Color textSecondary = Color(0xFF6B6255);
  static const Color textTertiary = Color(0xFFA69C8C);
  static const Color divider = Color(0xFFE8DFCB);
  static const Color success = Color(0xFF2E7D5B);
  static const Color warning = Color(0xFFA46A22);
  static const Color error = Color(0xFF8A2E36);

  // ---- Dark (near-black + bright gold, hero) ----
  static const Color backgroundDark = Color(0xFF0A0A0A);
  static const Color surfaceDark = Color(0xFF141414);
  static const Color surfaceMutedDark = Color(0xFF1C1A16);
  static const Color surfaceSunkenDark = Color(0xFF0C0C0B);
  static const Color accentDark = Color(0xFFF2C14E);
  static const Color accentSoftDark = Color(0xFF3A2E12);
  static const Color accentInkDark = Color(0xFFFCEACD);
  static const Color textPrimaryDark = Color(0xFFF5F1E8);
  static const Color textSecondaryDark = Color(0xFFA79E8E);
  static const Color textTertiaryDark = Color(0xFF6E6656);
  static const Color dividerDark = Color(0xFF2A2722);
}

class LovSpace {
  const LovSpace._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double xxxxl = 72;
}

class LovRadius {
  const LovRadius._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

class LovElevation {
  const LovElevation._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0F1611), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> cardDark = [
    BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

class LovDuration {
  const LovDuration._();
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration gentle = Duration(milliseconds: 400);
  static const Duration slow = Duration(milliseconds: 600);
}

class LovCurves {
  const LovCurves._();
  // Emphasised gentle-out for entrances
  static const Curve enter = Cubic(0.16, 1, 0.3, 1);
  // Standard for state changes
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);
}
