// The OS widget's payload.
//
// A widget sits on a lock screen with no context, no navigation and no way to
// ask a follow-up question. Anything it states is taken at face value, which
// makes it the least forgiving surface in the app for a wrong or stale claim —
// hence the emphasis here on what travels with the counts and what happens when
// the payload is unusable.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:lovinity/features/widget/data/widget_snapshot.dart';
import 'package:timezone/timezone.dart' as tz;

WidgetSnapshot _snapshot({
  int ownCount = 3,
  int spouseCount = 1,
  String ownTz = 'America/Toronto',
  String spouseTz = 'America/Toronto',
  double? latitude,
  double? longitude,
}) =>
    WidgetSnapshot(
      ownName: 'Ridwan',
      spouseName: 'Aisha',
      ownCount: ownCount,
      spouseCount: spouseCount,
      ownTz: ownTz,
      spouseTz: spouseTz,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.utc(2026, 8, 8, 12),
    );

void main() {
  setUpAll(() async => initTimezones());

  group('serialisation', () {
    test('round-trips every field', () {
      final original = WidgetSnapshot(
        ownName: 'Ridwan',
        spouseName: 'Aisha',
        ownCount: 4,
        spouseCount: 5,
        ownTz: 'America/Toronto',
        spouseTz: 'Asia/Dhaka',
        nextPrayerName: 'Asr',
        nextPrayerAtIso: '2026-08-08T18:30:00.000Z',
        verseText: 'And He put between you affection and mercy.',
        verseReference: '30:21',
        latitude: 43.65,
        longitude: -79.38,
        calcMethod: 'north_america',
        madhab: 'hanafi',
        updatedAt: DateTime.utc(2026, 8, 8, 12),
      );

      final parsed = WidgetSnapshot.tryParse(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.ownName, 'Ridwan');
      expect(parsed.spouseCount, 5);
      expect(parsed.ownTz, 'America/Toronto');
      expect(parsed.spouseTz, 'Asia/Dhaka');
      expect(parsed.nextPrayerName, 'Asr');
      expect(parsed.verseReference, '30:21');
      expect(parsed.latitude, 43.65);
      expect(parsed.madhab, 'hanafi');
      expect(parsed.updatedAt, original.updatedAt);
    });

    // The extension is a separate process that cannot show a Dart error. A bad
    // payload must leave the previous render in place, not take the widget down.
    test('returns null for unusable input instead of throwing', () {
      expect(WidgetSnapshot.tryParse(null), isNull);
      expect(WidgetSnapshot.tryParse(''), isNull);
      expect(WidgetSnapshot.tryParse('not json'), isNull);
      expect(WidgetSnapshot.tryParse('{"ownName":"x"}'), isNull,
          reason: 'missing updatedAt is not recoverable');
      expect(WidgetSnapshot.tryParse('[]'), isNull);
    });

    test('fills sensible defaults for optional fields', () {
      final parsed = WidgetSnapshot.tryParse(
        '{"updatedAt":"2026-08-08T12:00:00.000Z"}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.ownCount, 0);
      expect(parsed.spouseCount, 0);
      expect(parsed.ownTz, 'UTC');
      expect(parsed.nextPrayerName, isNull);
    });
  });

  group('zonesDiffer', () {
    // This is what stops "Aisha 0 of 5" reading as neglect when it is 1am where
    // she is. Without both zones in the payload the widget cannot tell the
    // difference between a slow day and a day that has barely started.
    test('is false for a same-zone couple, so no extra chrome is shown', () {
      expect(_snapshot().zonesDiffer, isFalse);
    });

    test('is true when the spouses are in different zones', () {
      expect(
        _snapshot(ownTz: 'America/Toronto', spouseTz: 'Asia/Dhaka').zonesDiffer,
        isTrue,
      );
    });
  });

  group('canRecomputeLocally', () {
    // Prayer times are a pure function of place, date and method, so the widget
    // can keep its countdown honest with no network at all. Only the counts and
    // the verse actually need a round-trip.
    test('true once coordinates are present', () {
      expect(_snapshot(latitude: 43.65, longitude: -79.38).canRecomputeLocally,
          isTrue);
    });

    test('false when the user has never set a location', () {
      expect(_snapshot().canRecomputeLocally, isFalse);
    });

    test('false when only one coordinate is present', () {
      expect(_snapshot(latitude: 43.65).canRecomputeLocally, isFalse);
    });
  });

  group('sameContentAs', () {
    test('ignores updatedAt so an unchanged snapshot is not republished', () {
      final a = _snapshot();
      final b = WidgetSnapshot(
        ownName: a.ownName,
        spouseName: a.spouseName,
        ownCount: a.ownCount,
        spouseCount: a.spouseCount,
        ownTz: a.ownTz,
        spouseTz: a.spouseTz,
        // Two minutes later, identical content.
        updatedAt: a.updatedAt.add(const Duration(minutes: 2)),
      );
      expect(a.sameContentAs(b), isTrue);
    });

    test('detects a changed count', () {
      expect(_snapshot(ownCount: 3).sameContentAs(_snapshot(ownCount: 4)),
          isFalse);
    });

    test('detects a changed timezone', () {
      expect(
        _snapshot().sameContentAs(_snapshot(spouseTz: 'Asia/Dhaka')),
        isFalse,
        reason: 'travel changes what the widget must explain',
      );
    });

    test('is false against null', () {
      expect(_snapshot().sameContentAs(null), isFalse);
    });
  });

  group('buildSnapshot', () {
    test('carries the next prayer as an absolute instant', () {
      final location = tz.getLocation('America/Toronto');
      final at = tz.TZDateTime(location, 2026, 8, 8, 17, 30);
      final snapshot = buildSnapshot(
        ownName: 'Ridwan',
        spouseName: 'Aisha',
        ownCount: 2,
        spouseCount: 2,
        ownTz: 'America/Toronto',
        spouseTz: 'America/Toronto',
        now: DateTime.utc(2026, 8, 8, 12),
        nextPrayer: ScheduledPrayer(Prayer.asr, at),
      );

      expect(snapshot.nextPrayerName, 'Asr');
      // UTC on the wire: the native side renders it in the device's zone, and a
      // wall-clock string would be ambiguous the moment the user travels.
      expect(snapshot.nextPrayerAtIso, endsWith('Z'));
      expect(DateTime.parse(snapshot.nextPrayerAtIso!).isUtc, isTrue);
      // Compared as an instant: `TZDateTime` and `DateTime` do not compare
      // equal with `==` even when they denote the same moment.
      expect(
        DateTime.parse(snapshot.nextPrayerAtIso!).millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
      );
    });

    test('tolerates a missing next prayer and verse', () {
      final snapshot = buildSnapshot(
        ownName: 'Ridwan',
        spouseName: 'Aisha',
        ownCount: 0,
        spouseCount: 0,
        ownTz: 'UTC',
        spouseTz: 'UTC',
        now: DateTime.utc(2026, 8, 8, 12),
      );
      expect(snapshot.nextPrayerName, isNull);
      expect(snapshot.verseText, isNull);
      expect(snapshot.toJson(), isNotEmpty);
    });
  });
}
