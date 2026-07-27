import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform-aware haptic helpers.
///
/// Mobile-only: no-op on web, macOS, Windows, and Linux.
class LovHaptics {
  const LovHaptics._();

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<void> light() async {
    if (!_isMobile) return;
    await HapticFeedback.lightImpact();
  }

  static Future<void> medium() async {
    if (!_isMobile) return;
    await HapticFeedback.mediumImpact();
  }

  static Future<void> heavy() async {
    if (!_isMobile) return;
    await HapticFeedback.heavyImpact();
  }

  static Future<void> selection() async {
    if (!_isMobile) return;
    await HapticFeedback.selectionClick();
  }

  /// "Two heartbeats" pattern used for pair-success moments.
  static Future<void> heartbeats() async {
    if (!_isMobile) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }
}
