// GENERATED from website/project/*.dc.html theme tokens — keep in sync with the design.
import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart' show ThemeExtension;

/// The seven Lovinity themes. Every color on every screen comes from one of these.
enum LovThemeId {
  midnight('Midnight'),
  emerald('Emerald'),
  lapis('Lapis'),
  rose('Rose'),
  desert('Desert'),
  sandstone('Sandstone'),
  pearl('Pearl');

  const LovThemeId(this.label);
  final String label;

  LovPalette get palette => LovPalette.all[this]!;

  static LovThemeId fromName(String? name) =>
      values.where((t) => t.name == name).firstOrNull ?? midnight;
}

/// Design tokens as a [ThemeExtension]; read with `context.lov`.
/// `hi` is the tint used for glass highlights and hairlines, `shadow` for depth.
class LovPalette extends ThemeExtension<LovPalette> {
  const LovPalette({
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.cardA,
    required this.cardB,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentHi,
    required this.accentLo,
    required this.accentSoft,
    required this.accentInk,
    required this.onAccent,
    required this.partner,
    required this.partnerHi,
    required this.partnerLo,
    required this.partnerSoft,
    required this.onPartner,
    required this.hi,
    required this.shadow,
  });

  final Brightness brightness;
  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surface2;
  final Color cardA;
  final Color cardB;
  final Color line;
  final Color line2;
  final Color text;
  final Color text2;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentHi;
  final Color accentLo;
  final Color accentSoft;
  final Color accentInk;
  final Color onAccent;
  final Color partner;
  final Color partnerHi;
  final Color partnerLo;
  final Color partnerSoft;
  final Color onPartner;
  final Color hi;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  static const all = <LovThemeId, LovPalette>{
    LovThemeId.midnight: LovPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF0A0A0A),
      bg2: Color(0xFF050505),
      surface: Color(0xFF141414),
      surface2: Color(0xFF1C1A16),
      cardA: Color(0xFF181715),
      cardB: Color(0xFF121211),
      line: Color(0xFF2A2722),
      line2: Color(0xFF4A4234),
      text: Color(0xFFF5F1E8),
      text2: Color(0xFFD4CBBA),
      muted: Color(0xFFA79E8E),
      faint: Color(0xFF6E6656),
      accent: Color(0xFFF2C14E),
      accentHi: Color(0xFFF8D891),
      accentLo: Color(0xFFE3A93A),
      accentSoft: Color(0xFF3A2E12),
      accentInk: Color(0xFFFCEACD),
      onAccent: Color(0xFF1A1205),
      partner: Color(0xFFE9A6A0),
      partnerHi: Color(0xFFF6D5D1),
      partnerLo: Color(0xFFD98A84),
      partnerSoft: Color(0xFF2A1C1C),
      onPartner: Color(0xFF1A1010),
      hi: Color.fromARGB(255, 255, 255, 255),
      shadow: Color.fromARGB(255, 0, 0, 0),
    ),
    LovThemeId.emerald: LovPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF06110D),
      bg2: Color(0xFF030A07),
      surface: Color(0xFF0D1C16),
      surface2: Color(0xFF12251D),
      cardA: Color(0xFF10211A),
      cardB: Color(0xFF0B1813),
      line: Color(0xFF1E3A2E),
      line2: Color(0xFF2F5444),
      text: Color(0xFFEEF5EF),
      text2: Color(0xFFC6D8CC),
      muted: Color(0xFF8FAE9F),
      faint: Color(0xFF5E7A6D),
      accent: Color(0xFFE3C26F),
      accentHi: Color(0xFFF1DA9C),
      accentLo: Color(0xFFC9A24B),
      accentSoft: Color(0xFF2C2A14),
      accentInk: Color(0xFFF6E7BE),
      onAccent: Color(0xFF14200F),
      partner: Color(0xFFF0A9A0),
      partnerHi: Color(0xFFF8D3CD),
      partnerLo: Color(0xFFD9847A),
      partnerSoft: Color(0xFF2C1C1A),
      onPartner: Color(0xFF2A1010),
      hi: Color.fromARGB(255, 255, 255, 255),
      shadow: Color.fromARGB(255, 0, 0, 0),
    ),
    LovThemeId.lapis: LovPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF070B16),
      bg2: Color(0xFF03060D),
      surface: Color(0xFF0F1626),
      surface2: Color(0xFF141D31),
      cardA: Color(0xFF121A2C),
      cardB: Color(0xFF0C1220),
      line: Color(0xFF22304D),
      line2: Color(0xFF34466B),
      text: Color(0xFFEEF2FA),
      text2: Color(0xFFC8D2E6),
      muted: Color(0xFF8E9BB8),
      faint: Color(0xFF5C6886),
      accent: Color(0xFF8EC5FF),
      accentHi: Color(0xFFBFDEFF),
      accentLo: Color(0xFF5EA6F0),
      accentSoft: Color(0xFF15304F),
      accentInk: Color(0xFFDCEBFF),
      onAccent: Color(0xFF061224),
      partner: Color(0xFFF2B6C9),
      partnerHi: Color(0xFFFAD9E3),
      partnerLo: Color(0xFFDB8EA6),
      partnerSoft: Color(0xFF2E1A24),
      onPartner: Color(0xFF2A0F1A),
      hi: Color.fromARGB(255, 255, 255, 255),
      shadow: Color.fromARGB(255, 0, 0, 0),
    ),
    LovThemeId.rose: LovPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF0C0809),
      bg2: Color(0xFF060404),
      surface: Color(0xFF171012),
      surface2: Color(0xFF1F1517),
      cardA: Color(0xFF1B1214),
      cardB: Color(0xFF120C0E),
      line: Color(0xFF33242A),
      line2: Color(0xFF50363F),
      text: Color(0xFFF8EEF0),
      text2: Color(0xFFE0CCD1),
      muted: Color(0xFFB39AA0),
      faint: Color(0xFF7A626A),
      accent: Color(0xFFF0A2B0),
      accentHi: Color(0xFFF8CCD5),
      accentLo: Color(0xFFDC7F92),
      accentSoft: Color(0xFF3E1F27),
      accentInk: Color(0xFFFFE1E7),
      onAccent: Color(0xFF2A0C14),
      partner: Color(0xFFF2C14E),
      partnerHi: Color(0xFFF8D891),
      partnerLo: Color(0xFFE3A93A),
      partnerSoft: Color(0xFF3A2E12),
      onPartner: Color(0xFF1A1205),
      hi: Color.fromARGB(255, 255, 255, 255),
      shadow: Color.fromARGB(255, 0, 0, 0),
    ),
    LovThemeId.desert: LovPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF120C08),
      bg2: Color(0xFF0A0604),
      surface: Color(0xFF1C140E),
      surface2: Color(0xFF241A12),
      cardA: Color(0xFF20170F),
      cardB: Color(0xFF160F0A),
      line: Color(0xFF3A2A1E),
      line2: Color(0xFF5A412E),
      text: Color(0xFFF7EDE3),
      text2: Color(0xFFE0CDBA),
      muted: Color(0xFFB49F8B),
      faint: Color(0xFF7D6A58),
      accent: Color(0xFFE8875A),
      accentHi: Color(0xFFF4B08E),
      accentLo: Color(0xFFCF6A3E),
      accentSoft: Color(0xFF3D2416),
      accentInk: Color(0xFFFFD9C2),
      onAccent: Color(0xFF2A1004),
      partner: Color(0xFFE9C46A),
      partnerHi: Color(0xFFF4DD9E),
      partnerLo: Color(0xFFCFA748),
      partnerSoft: Color(0xFF33290F),
      onPartner: Color(0xFF2A1F04),
      hi: Color.fromARGB(255, 255, 255, 255),
      shadow: Color.fromARGB(255, 0, 0, 0),
    ),
    LovThemeId.sandstone: LovPalette(
      brightness: Brightness.light,
      bg: Color(0xFFF6F1E7),
      bg2: Color(0xFFEAE2D2),
      surface: Color(0xFFFFFDF8),
      surface2: Color(0xFFEFE7D8),
      cardA: Color(0xFFFFFEFA),
      cardB: Color(0xFFF8F3E9),
      line: Color(0xFFE2D7C3),
      line2: Color(0xFFCDBE9F),
      text: Color(0xFF1E1A14),
      text2: Color(0xFF3E372B),
      muted: Color(0xFF7A6F5E),
      faint: Color(0xFFA39883),
      accent: Color(0xFFB8862B),
      accentHi: Color(0xFFD9AE5C),
      accentLo: Color(0xFF9C6F1E),
      accentSoft: Color(0xFFF3E4C2),
      accentInk: Color(0xFF5A4210),
      onAccent: Color(0xFFFFFDF8),
      partner: Color(0xFFC76B62),
      partnerHi: Color(0xFFE3A39C),
      partnerLo: Color(0xFFA9534B),
      partnerSoft: Color(0xFFF5DEDA),
      onPartner: Color(0xFFFFFFFF),
      hi: Color.fromARGB(255, 90, 66, 30),
      shadow: Color.fromARGB(255, 90, 70, 40),
    ),
    LovThemeId.pearl: LovPalette(
      brightness: Brightness.light,
      bg: Color(0xFFF3F6F4),
      bg2: Color(0xFFE5ECE8),
      surface: Color(0xFFFFFFFF),
      surface2: Color(0xFFE9F0EB),
      cardA: Color(0xFFFFFFFF),
      cardB: Color(0xFFF6F9F7),
      line: Color(0xFFD6E1DA),
      line2: Color(0xFFB7C9BE),
      text: Color(0xFF10201A),
      text2: Color(0xFF2C3E35),
      muted: Color(0xFF5F7469),
      faint: Color(0xFF93A59B),
      accent: Color(0xFF1F8A5B),
      accentHi: Color(0xFF4DB385),
      accentLo: Color(0xFF156B45),
      accentSoft: Color(0xFFD7EFE2),
      accentInk: Color(0xFF0F4A30),
      onAccent: Color(0xFFFFFFFF),
      partner: Color(0xFFD9776B),
      partnerHi: Color(0xFFEDB0A8),
      partnerLo: Color(0xFFBC5B50),
      partnerSoft: Color(0xFFF8E1DE),
      onPartner: Color(0xFFFFFFFF),
      hi: Color.fromARGB(255, 20, 60, 40),
      shadow: Color.fromARGB(255, 30, 60, 45),
    ),
  };

  @override
  LovPalette copyWith() => this;

  @override
  LovPalette lerp(LovPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return LovPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      bg2: c(bg2, other.bg2),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      cardA: c(cardA, other.cardA),
      cardB: c(cardB, other.cardB),
      line: c(line, other.line),
      line2: c(line2, other.line2),
      text: c(text, other.text),
      text2: c(text2, other.text2),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      accent: c(accent, other.accent),
      accentHi: c(accentHi, other.accentHi),
      accentLo: c(accentLo, other.accentLo),
      accentSoft: c(accentSoft, other.accentSoft),
      accentInk: c(accentInk, other.accentInk),
      onAccent: c(onAccent, other.onAccent),
      partner: c(partner, other.partner),
      partnerHi: c(partnerHi, other.partnerHi),
      partnerLo: c(partnerLo, other.partnerLo),
      partnerSoft: c(partnerSoft, other.partnerSoft),
      onPartner: c(onPartner, other.onPartner),
      hi: c(hi, other.hi),
      shadow: c(shadow, other.shadow),
    );
  }
}
