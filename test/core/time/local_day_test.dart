// Per-person day anchoring.
//
// A couple's prayer log has TWO anchors, not one: each spouse's rows are
// filed under the calendar day in effect in THEIR OWN timezone. These are
// the pure primitives that resolve those anchors, so every falsehood the
// UI used to tell (a partner's check-in dropped because her date key
// differed from the viewer's) is preventable at this layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/local_day.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';

void main() {
  setUpAll(() async => initTimezones());

  group('dayKey', () {
    test('formats as zero-padded YYYY-MM-DD', () {
      expect(dayKey(DateTime(2026, 8, 6)), '2026-08-06');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(dayKey(DateTime(926, 1, 2)), '0926-01-02');
    });
  });

  group('localDayAt', () {
    // The motivating scenario: Toronto husband at 3:04 PM on Aug 6 is
    // simultaneous with Dhaka wife at 1:04 AM on Aug 7. One instant,
    // two calendar days. Neither is wrong.
    final instant = DateTime.utc(2026, 8, 6, 19, 4);

    test('resolves different calendar days for the same instant', () {
      expect(dayKey(localDayAt('America/Toronto', instant)), '2026-08-06');
      expect(dayKey(localDayAt('Asia/Dhaka', instant)), '2026-08-07');
    });

    test('handles the far side of the date line', () {
      // Kiritimati is UTC+14, Niue is UTC-11 — 25 hours apart.
      expect(dayKey(localDayAt('Pacific/Kiritimati', instant)), '2026-08-07');
      expect(dayKey(localDayAt('Pacific/Niue', instant)), '2026-08-06');
    });

    test('falls back to UTC for an unknown zone rather than throwing', () {
      expect(
        dayKey(localDayAt('Not/AZone', instant)),
        dayKey(localDayAt('UTC', instant)),
      );
    });

    test('respects DST — same wall clock, different UTC offset', () {
      // 03:30 UTC on 2026-01-15 is 22:30 on the 14th in New York (EST, -5).
      final winter = DateTime.utc(2026, 1, 15, 3, 30);
      expect(dayKey(localDayAt('America/New_York', winter)), '2026-01-14');
      // 03:30 UTC on 2026-07-15 is 23:30 on the 14th in New York (EDT, -4).
      final summer = DateTime.utc(2026, 7, 15, 3, 30);
      expect(dayKey(localDayAt('America/New_York', summer)), '2026-07-14');
      // ...but 04:30 UTC in summer has already rolled over to the 15th.
      final summerLate = DateTime.utc(2026, 7, 15, 4, 30);
      expect(dayKey(localDayAt('America/New_York', summerLate)), '2026-07-15');
    });
  });

  group('dayForOffset', () {
    final instant = DateTime.utc(2026, 8, 6, 19, 4);

    test('offset 0 is that zone\'s today', () {
      expect(
        dayKey(dayForOffset(tzId: 'Asia/Dhaka', offset: 0, at: instant)),
        '2026-08-07',
      );
    });

    test('offset 1 is that zone\'s yesterday, not the viewer\'s', () {
      // Dhaka's yesterday (Aug 6) happens to equal Toronto's today. That is
      // exactly why the offset must be resolved per-zone.
      expect(
        dayKey(dayForOffset(tzId: 'Asia/Dhaka', offset: 1, at: instant)),
        '2026-08-06',
      );
      expect(
        dayKey(dayForOffset(tzId: 'America/Toronto', offset: 1, at: instant)),
        '2026-08-05',
      );
    });

    test('crosses month and year boundaries', () {
      final firstOfMonth = DateTime.utc(2026, 8, 1, 12);
      expect(
        dayKey(dayForOffset(tzId: 'UTC', offset: 1, at: firstOfMonth)),
        '2026-07-31',
      );
      final newYear = DateTime.utc(2026, 1, 1, 12);
      expect(
        dayKey(dayForOffset(tzId: 'UTC', offset: 1, at: newYear)),
        '2025-12-31',
      );
      expect(
        dayKey(dayForOffset(tzId: 'UTC', offset: 40, at: firstOfMonth)),
        '2026-06-22',
      );
    });

    test('does not drift across a spring-forward DST boundary', () {
      // US DST begins 2026-03-08. Stepping back one day from the 9th must
      // land on the 8th, not the 7th — naive Duration(days: 1) subtraction
      // on a local DateTime is what produces that off-by-one.
      final after = DateTime.utc(2026, 3, 9, 18);
      expect(
        dayKey(dayForOffset(tzId: 'America/New_York', offset: 1, at: after)),
        '2026-03-08',
      );
      expect(
        dayKey(dayForOffset(tzId: 'America/New_York', offset: 2, at: after)),
        '2026-03-07',
      );
    });
  });

  group('zonesAgreeOnDay', () {
    test('true when both zones are on the same calendar day', () {
      final instant = DateTime.utc(2026, 8, 6, 12);
      expect(
        zonesAgreeOnDay('America/Toronto', 'America/New_York', instant),
        isTrue,
      );
    });

    test('false when the zones straddle midnight', () {
      final instant = DateTime.utc(2026, 8, 6, 19, 4);
      expect(zonesAgreeOnDay('America/Toronto', 'Asia/Dhaka', instant), isFalse);
    });

    test('true for identical zones regardless of instant', () {
      final instant = DateTime.utc(2026, 8, 6, 19, 4);
      expect(zonesAgreeOnDay('Asia/Dhaka', 'Asia/Dhaka', instant), isTrue);
    });
  });

  group('utcOffsetLabel', () {
    test('renders a signed hour offset between two zones', () {
      final instant = DateTime.utc(2026, 8, 6, 19, 4);
      // Dhaka (+6) is 10 hours ahead of Toronto (EDT, -4).
      expect(utcOffsetLabel('America/Toronto', 'Asia/Dhaka', instant), '+10h');
      expect(utcOffsetLabel('Asia/Dhaka', 'America/Toronto', instant), '-10h');
    });

    test('includes minutes for half-hour and quarter-hour zones', () {
      final instant = DateTime.utc(2026, 8, 6, 12);
      // Kolkata is +5:30; Kathmandu is +5:45.
      expect(utcOffsetLabel('UTC', 'Asia/Kolkata', instant), '+5h 30m');
      expect(utcOffsetLabel('Asia/Kolkata', 'Asia/Kathmandu', instant), '+15m');
    });

    test('is empty when the zones share an offset', () {
      final instant = DateTime.utc(2026, 8, 6, 12);
      expect(utcOffsetLabel('America/Toronto', 'America/New_York', instant), '');
    });
  });
}
