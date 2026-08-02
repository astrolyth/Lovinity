// test/features/prayer_log/prayer_notification_detector_test.dart
//
// Regression coverage for FIX 2 (partner-sync): the notification pump's
// `newRowDetector` key must include the row's date, not just user+prayer.
// Without the date in the key, the same prayer logged on two different
// calendar days would collide on one key, and `newRowDetector` -- which
// only fires for keys absent from the previous emission -- would treat the
// second day's check-in as a re-emit of the first and never notify.
//
// This mirrors the exact `keyOf` used in
// lib/features/prayer_log/domain/prayer_log_providers.dart's
// prayerNotificationPumpProvider.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/activity_detectors.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/shared/models/prayer_log.dart';

PrayerLogEntry _entry({
  required String userId,
  required DateTime date,
  required Prayer prayer,
  DateTime? timeLogged,
}) =>
    PrayerLogEntry(
      userId: userId,
      date: date,
      prayer: prayer,
      status: PrayerStatus.prayed,
      timeLogged: timeLogged ?? date,
    );

void main() {
  group('prayer pump detector key (userId:dateKey:prayer)', () {
    String keyOf(PrayerLogEntry e) => '${e.userId}:${e.dateKey}:${e.prayer.dbName}';

    test(
        'the same prayer logged on two different days notifies both times',
        () {
      final fired = <PrayerLogEntry>[];
      final detector = newRowDetector<PrayerLogEntry>(
        keyOf: keyOf,
        onNew: fired.add,
      );

      final day1 = _entry(
        userId: 'partner',
        date: DateTime(2026, 7, 30),
        prayer: Prayer.fajr,
      );
      // Baseline emission: existing history, must not fire.
      detector([day1]);
      expect(fired, isEmpty);

      final day2 = _entry(
        userId: 'partner',
        date: DateTime(2026, 7, 31),
        prayer: Prayer.fajr,
      );
      // Day 2's check-in is a genuinely new row (different date), so it
      // must fire even though user+prayer match day 1's.
      detector([day1, day2]);
      expect(fired, [day2]);
    });

    test(
        'a partner row dated differently from the local device is not '
        'dropped by the key (regression for FIX 2)', () {
      // Simulates the actual bug: partner's device is a day ahead, so her
      // row's `date` differs from what this device thinks "today" is. The
      // detector must still treat it as a distinct, notify-worthy key --
      // this only holds if the key includes the date.
      final fired = <PrayerLogEntry>[];
      final detector = newRowDetector<PrayerLogEntry>(
        keyOf: keyOf,
        onNew: fired.add,
      );

      detector(const []); // baseline: nothing logged yet
      final partnerRow = _entry(
        userId: 'partner',
        date: DateTime(2026, 8, 1), // partner's local "today"
        prayer: Prayer.isha,
      );
      detector([partnerRow]);
      expect(fired, [partnerRow]);
    });

    test('without a date in the key, the second day would be swallowed '
        '(demonstrates why the date must be included)', () {
      final fired = <PrayerLogEntry>[];
      // Deliberately the OLD/broken key shape, to document the regression
      // this fix prevents.
      final detector = newRowDetector<PrayerLogEntry>(
        keyOf: (e) => '${e.userId}:${e.prayer.dbName}',
        onNew: fired.add,
      );

      final day1 = _entry(
        userId: 'partner',
        date: DateTime(2026, 7, 30),
        prayer: Prayer.dhuhr,
      );
      detector([day1]);
      expect(fired, isEmpty);

      final day2 = _entry(
        userId: 'partner',
        date: DateTime(2026, 7, 31),
        prayer: Prayer.dhuhr,
      );
      detector([day1, day2]);
      // With the broken key, day2 collides with day1's key and is silently
      // dropped -- this is the bug the date-inclusive key fixes.
      expect(fired, isEmpty);
    });
  });
}
