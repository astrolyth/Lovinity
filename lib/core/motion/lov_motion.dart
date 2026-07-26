import 'package:flutter/widgets.dart';

/// The single source of truth for motion in Sakīnah.
///
/// All animation curves and durations flow from here so screens speak
/// one motion language. Every consumer should honor
/// [MediaQuery.disableAnimationsOf] via [SakMotion.motionEnabled].
class SakMotion {
  const SakMotion._();

  // Durations
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration gentle = Duration(milliseconds: 400);
  static const Duration hero = Duration(milliseconds: 480);
  static const Duration slow = Duration(milliseconds: 700);
  static const Duration breathe = Duration(milliseconds: 4000);

  // Curves
  static const Curve enter = Cubic(0.16, 1, 0.3, 1); // emphasised gentle-out
  static const Curve standardCurve = Cubic(0.4, 0, 0.2, 1);
  static const Curve springOut = Cubic(0.34, 1.56, 0.64, 1); // gentle overshoot
  static const Curve breatheCurve = Curves.easeInOut;

  /// Whether the OS has requested reduced motion. Widgets should collapse
  /// animations to a single fade when this returns false.
  static bool motionEnabled(BuildContext context) {
    return !MediaQuery.disableAnimationsOf(context);
  }
}
