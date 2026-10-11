import 'dart:convert';

import '../../../core/time/prayer_engine.dart';

/// What the OS home-screen widget renders.
///
/// A flat, serialisable value with no Flutter or Supabase types, because it has
/// to cross into a Swift WidgetKit extension and a Kotlin AppWidgetProvider —
/// separate processes that never run Dart. Keeping it pure also makes the
/// interesting part (what the widget is allowed to claim) unit-testable without
/// a device.
///
/// ## Why the counts carry timezones
///
/// The widget is the single worst place for a mis-anchored prayer count. It
/// sits on a lock screen with no context, no "yesterday" toggle and no way to
/// ask a question, so "Aisha 0 of 5" reads as neglect rather than as "her day
/// started forty minutes ago". Both zones travel with the snapshot so the
/// widget can say which day each count belongs to, exactly as the in-app dual
/// clock does (see `lib/core/time/local_day.dart`).
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.ownName,
    required this.spouseName,
    required this.ownCount,
    required this.spouseCount,
    required this.ownTz,
    required this.spouseTz,
    required this.updatedAt,
    this.nextPrayerName,
    this.nextPrayerAtIso,
    this.verseText,
    this.verseReference,
    this.latitude,
    this.longitude,
    this.calcMethod,
    this.madhab,
  });

  final String ownName;
  final String spouseName;
  final int ownCount;
  final int spouseCount;

  /// IANA zones for each spouse. Equal zones mean the widget can drop the
  /// day-attribution line entirely, matching the app's adaptive behaviour.
  final String ownTz;
  final String spouseTz;

  final String? nextPrayerName;
  final String? nextPrayerAtIso;
  final String? verseText;
  final String? verseReference;

  /// Coordinates and calculation settings, so the native side can recompute the
  /// next prayer itself rather than showing a stale one.
  ///
  /// This is what lets the widget stay correct without the network: prayer
  /// times are a pure function of place, date and method. Only the check-in
  /// counts and the verse genuinely need a round-trip, and those degrade
  /// gracefully to "as of <time>" while the countdown stays live.
  final double? latitude;
  final double? longitude;
  final String? calcMethod;
  final String? madhab;

  final DateTime updatedAt;

  bool get zonesDiffer => ownTz != spouseTz;

  /// True when the widget has enough to recompute prayer times on its own.
  bool get canRecomputeLocally => latitude != null && longitude != null;

  Map<String, Object?> toMap() => {
        'ownName': ownName,
        'spouseName': spouseName,
        'ownCount': ownCount,
        'spouseCount': spouseCount,
        'ownTz': ownTz,
        'spouseTz': spouseTz,
        'nextPrayerName': nextPrayerName,
        'nextPrayerAtIso': nextPrayerAtIso,
        'verseText': verseText,
        'verseReference': verseReference,
        'latitude': latitude,
        'longitude': longitude,
        'calcMethod': calcMethod,
        'madhab': madhab,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  String toJson() => jsonEncode(toMap());

  /// Parses a snapshot back. Returns null rather than throwing on anything
  /// malformed — a corrupt payload should leave the widget showing its previous
  /// state, not crash the extension.
  static WidgetSnapshot? tryParse(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(source) as Map);
      return WidgetSnapshot(
        ownName: (m['ownName'] ?? 'You') as String,
        spouseName: (m['spouseName'] ?? 'Your spouse') as String,
        ownCount: (m['ownCount'] as num?)?.toInt() ?? 0,
        spouseCount: (m['spouseCount'] as num?)?.toInt() ?? 0,
        ownTz: (m['ownTz'] ?? 'UTC') as String,
        spouseTz: (m['spouseTz'] ?? 'UTC') as String,
        nextPrayerName: m['nextPrayerName'] as String?,
        nextPrayerAtIso: m['nextPrayerAtIso'] as String?,
        verseText: m['verseText'] as String?,
        verseReference: m['verseReference'] as String?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        calcMethod: m['calcMethod'] as String?,
        madhab: m['madhab'] as String?,
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Value equality so the writer can skip a platform round-trip (and the
  /// widget-reload it triggers) when nothing the widget displays has changed.
  /// [updatedAt] is excluded deliberately — including it would make every
  /// snapshot unequal and defeat the check entirely.
  bool sameContentAs(WidgetSnapshot? other) =>
      other != null &&
      other.ownName == ownName &&
      other.spouseName == spouseName &&
      other.ownCount == ownCount &&
      other.spouseCount == spouseCount &&
      other.ownTz == ownTz &&
      other.spouseTz == spouseTz &&
      other.nextPrayerName == nextPrayerName &&
      other.nextPrayerAtIso == nextPrayerAtIso &&
      other.verseText == verseText &&
      other.verseReference == verseReference &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.calcMethod == calcMethod &&
      other.madhab == madhab;
}

/// Builds the snapshot from already-resolved inputs.
///
/// Takes plain values rather than reading providers so it can be tested
/// directly; the provider layer supplies them.
WidgetSnapshot buildSnapshot({
  required String ownName,
  required String spouseName,
  required int ownCount,
  required int spouseCount,
  required String ownTz,
  required String spouseTz,
  required DateTime now,
  ScheduledPrayer? nextPrayer,
  String? verseText,
  String? verseReference,
  double? latitude,
  double? longitude,
  String? calcMethod,
  String? madhab,
}) {
  return WidgetSnapshot(
    ownName: ownName,
    spouseName: spouseName,
    ownCount: ownCount,
    spouseCount: spouseCount,
    ownTz: ownTz,
    spouseTz: spouseTz,
    nextPrayerName: nextPrayer?.prayer.displayName,
    nextPrayerAtIso: nextPrayer?.at.toUtc().toIso8601String(),
    verseText: verseText,
    verseReference: verseReference,
    latitude: latitude,
    longitude: longitude,
    calcMethod: calcMethod,
    madhab: madhab,
    updatedAt: now,
  );
}
