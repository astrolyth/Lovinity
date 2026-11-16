// Hijri/Gregorian conversion and recurrence for the shared calendar.
//
// Assertions here are round-trip and structural invariants rather than
// hardcoded almanac dates: the underlying Umm al-Qurā table is the authority
// on what 12 Rajab 1447 maps to, and re-asserting its own output as a literal
// would test nothing while looking authoritative.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/hijri_dates.dart';

void main() {
  group('HijriDay', () {
    test('formats and parses a stable YYYY-MM-DD key', () {
      const d = HijriDay(1447, 7, 12);
      expect(d.key, '1447-07-12');
      expect(HijriDay.parse('1447-07-12'), d);
    });

    test('rejects malformed keys rather than guessing', () {
      expect(HijriDay.parse('not-a-date'), isNull);
      expect(HijriDay.parse('1447-13-01'), isNull, reason: 'month > 12');
      expect(HijriDay.parse('1447-00-01'), isNull, reason: 'month < 1');
      expect(HijriDay.parse('1447-07-31'), isNull, reason: 'day > 30');
      expect(HijriDay.parse('1447-07'), isNull);
    });

    test('is value-equal', () {
      expect(const HijriDay(1447, 7, 12), const HijriDay(1447, 7, 12));
      expect(
        const HijriDay(1447, 7, 12).hashCode,
        const HijriDay(1447, 7, 12).hashCode,
      );
      expect(const HijriDay(1447, 7, 12), isNot(const HijriDay(1447, 7, 13)));
    });
  });

  group('conversion', () {
    test('round-trips Gregorian → Hijri → Gregorian across a year', () {
      for (var i = 0; i < 365; i += 7) {
        final g = DateTime(2026, 1, 1).add(Duration(days: i));
        final gregorianDay = DateTime(g.year, g.month, g.day);
        final h = hijriFromGregorian(gregorianDay);
        final back = gregorianFromHijri(h);
        expect(
          back,
          gregorianDay,
          reason: 'round trip failed for $gregorianDay via $h',
        );
      }
    });

    test('advances the Hijri day when the Gregorian day advances', () {
      final a = hijriFromGregorian(DateTime(2026, 8, 7));
      final b = hijriFromGregorian(DateTime(2026, 8, 8));
      expect(a, isNot(b));
    });

    test('places Ramadan 1447 inside 2026', () {
      // A deliberately loose sanity check on orientation — enough to catch a
      // conversion that is out by a year or a month, without asserting a
      // specific day the table already defines.
      final start = gregorianFromHijri(const HijriDay(1447, 9, 1));
      expect(start, isNotNull);
      expect(start!.year, 2026);
    });

    test('returns null outside the Umm al-Qurā table rather than throwing', () {
      expect(gregorianFromHijri(const HijriDay(900, 1, 1)), isNull);
      expect(gregorianFromHijri(const HijriDay(3000, 1, 1)), isNull);
    });
  });

  group('formatHijri', () {
    test('renders a readable month name', () {
      expect(formatHijri(const HijriDay(1447, 9, 1)), contains('1447'));
      expect(formatHijri(const HijriDay(1447, 9, 1)), contains('Ramadan'));
    });
  });

  group('nextHijriOccurrence', () {
    test('returns today when the anchor falls today', () {
      final today = DateTime(2026, 8, 7);
      final anchor = hijriFromGregorian(today);
      expect(nextHijriOccurrence(anchor: anchor, from: today), today);
    });

    test('never returns a date before `from`', () {
      final from = DateTime(2026, 8, 7);
      for (final month in [1, 3, 9, 12]) {
        final next =
            nextHijriOccurrence(anchor: HijriDay(1447, month, 15), from: from);
        expect(next, isNotNull);
        expect(
          next!.isBefore(from),
          isFalse,
          reason: 'month $month resolved to $next, before $from',
        );
      }
    });

    test('lands on a date whose Hijri month and day match the anchor', () {
      const anchor = HijriDay(1447, 10, 1); // 1 Shawwal — Eid al-Fitr
      final next = nextHijriOccurrence(anchor: anchor, from: DateTime(2026, 8, 7));
      expect(next, isNotNull);
      final resolved = hijriFromGregorian(next!);
      expect(resolved.month, anchor.month);
      expect(resolved.day, anchor.day);
    });

    test('recurs on the Hijri date, drifting against the Gregorian one', () {
      // The whole point of a Hijri anchor: an Islamic anniversary moves ~11
      // days earlier each Gregorian year. Two consecutive occurrences must be
      // roughly a lunar year apart, not exactly 365 days.
      const anchor = HijriDay(1447, 10, 1);
      final first = nextHijriOccurrence(anchor: anchor, from: DateTime(2026, 8, 7))!;
      final second = nextHijriOccurrence(
        anchor: anchor,
        from: first.add(const Duration(days: 1)),
      )!;
      final gap = second.difference(first).inDays;
      expect(gap, greaterThan(340));
      expect(gap, lessThan(360));
    });

    test('clamps an anchor day that does not exist in the target month', () {
      // A 30th-day anchor in a year where that month has only 29 days must
      // fall back to the 29th rather than silently rolling into the next
      // month — an anniversary should not migrate.
      const anchor = HijriDay(1447, 2, 30);
      final next = nextHijriOccurrence(anchor: anchor, from: DateTime(2026, 1, 1));
      expect(next, isNotNull);
      final resolved = hijriFromGregorian(next!);
      expect(resolved.month, 2, reason: 'must not roll into month 3');
      expect(resolved.day, anyOf(29, 30));
    });
  });

  group('nextGregorianOccurrence', () {
    final start = DateTime(2026, 3, 14);

    test('returns the start date itself when it is still ahead', () {
      expect(
        nextGregorianOccurrence(
            start: start, rrule: null, from: DateTime(2026, 1, 1)),
        start,
      );
    });

    test('returns null for a past one-off event', () {
      expect(
        nextGregorianOccurrence(
            start: start, rrule: null, from: DateTime(2027, 1, 1)),
        isNull,
      );
    });

    test('repeats yearly', () {
      expect(
        nextGregorianOccurrence(
            start: start, rrule: 'FREQ=YEARLY', from: DateTime(2026, 6, 1)),
        DateTime(2027, 3, 14),
      );
    });

    test('honours INTERVAL', () {
      expect(
        nextGregorianOccurrence(
          start: start,
          rrule: 'FREQ=YEARLY;INTERVAL=2',
          from: DateTime(2026, 6, 1),
        ),
        DateTime(2028, 3, 14),
      );
    });

    test('repeats daily, weekly and monthly', () {
      expect(
        nextGregorianOccurrence(
            start: start, rrule: 'FREQ=DAILY', from: DateTime(2026, 3, 20)),
        DateTime(2026, 3, 20),
      );
      expect(
        nextGregorianOccurrence(
            start: start, rrule: 'FREQ=WEEKLY', from: DateTime(2026, 3, 16)),
        DateTime(2026, 3, 21),
      );
      expect(
        nextGregorianOccurrence(
            start: start, rrule: 'FREQ=MONTHLY', from: DateTime(2026, 4, 1)),
        DateTime(2026, 4, 14),
      );
    });

    test('clamps a 29 February anniversary instead of drifting to 1 March', () {
      final leap = DateTime(2024, 2, 29);
      final next = nextGregorianOccurrence(
          start: leap, rrule: 'FREQ=YEARLY', from: DateTime(2026, 1, 1));
      expect(next, DateTime(2026, 2, 28),
          reason: 'must stay in February, not roll to 1 March');
    });

    test('clamps a 31st monthly anniversary in short months', () {
      final thirtyFirst = DateTime(2026, 1, 31);
      expect(
        nextGregorianOccurrence(
            start: thirtyFirst,
            rrule: 'FREQ=MONTHLY',
            from: DateTime(2026, 2, 1)),
        DateTime(2026, 2, 28),
      );
    });

    test('returns null for an unsupported rule rather than pretending', () {
      // Only the subset the calendar actually offers is supported. Silently
      // treating FREQ=HOURLY as yearly would put events on wrong days.
      expect(
        nextGregorianOccurrence(
            start: start, rrule: 'FREQ=HOURLY', from: DateTime(2026, 1, 1)),
        isNull,
      );
    });
  });

  group('all-day events', () {
    test('survives a round trip through storage unchanged', () {
      final date = DateTime(2026, 3, 14);
      final stored = allDayInstant(date);
      expect(stored.isUtc, isTrue);
      expect(allDayDateFrom(stored), date);
    });

    // The failure this prevents: an anniversary stored as a local instant and
    // rendered in the spouse's zone shows as the day before. Same falsehood
    // class as the prayer-log timezone bug — a date is not an instant.
    test('renders the same calendar day regardless of viewer timezone', () {
      final stored = allDayInstant(DateTime(2026, 3, 14));
      expect(allDayDateFrom(stored), DateTime(2026, 3, 14));
      // Reading it as an instant in a far-behind zone would yield the 13th;
      // reading the date fields must not.
      expect(allDayDateFrom(stored.toLocal()), DateTime(2026, 3, 14));
    });
  });
}
