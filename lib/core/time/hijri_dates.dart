import 'package:hijri/hijri_calendar.dart';

/// Hijri/Gregorian conversion and recurrence for the shared calendar.
///
/// Two calendars run side by side here because a couple's dates genuinely
/// live in both: a civil wedding anniversary recurs on its Gregorian date,
/// while Eid, an Islamic marriage anniversary or the start of Ramadan recur on
/// their Hijri date and therefore drift ~11 days earlier each Gregorian year.
/// Storing only one and deriving the other loses that distinction, so
/// `calendar_events` carries `starts_at` *and* an optional `hijri_anchor`, and
/// this module resolves whichever one an event is anchored to.
///
/// Conversion is delegated to the `hijri` package's Umm al-Qurā tables. That
/// table is finite, so conversions outside its range return null rather than
/// throwing or fabricating a date.

const _monthNames = [
  'Muharram',
  'Safar',
  'Rabi al-Awwal',
  'Rabi al-Thani',
  'Jumada al-Ula',
  'Jumada al-Akhirah',
  'Rajab',
  'Shaban',
  'Ramadan',
  'Shawwal',
  'Dhul-Qadah',
  'Dhul-Hijjah',
];

/// A Hijri calendar date as a plain value — no clock, no zone.
class HijriDay {
  const HijriDay(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// Stable `YYYY-MM-DD` form, matching what `calendar_events.hijri_anchor`
  /// stores.
  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Parses [key]-form text. Returns null on anything malformed or out of
  /// range — a bad anchor should degrade the event to a plain Gregorian one,
  /// never crash the calendar.
  static HijriDay? parse(String? source) {
    if (source == null) return null;
    final parts = source.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12) return null;
    // Hijri months are 29 or 30 days; 30 is the ceiling for any month.
    if (d < 1 || d > 30) return null;
    return HijriDay(y, m, d);
  }

  @override
  bool operator ==(Object other) =>
      other is HijriDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'HijriDay($key)';
}

/// The Hijri date corresponding to the Gregorian calendar date [date].
HijriDay hijriFromGregorian(DateTime date) {
  final h = HijriCalendar.fromDate(DateTime(date.year, date.month, date.day));
  return HijriDay(h.hYear, h.hMonth, h.hDay);
}

/// The Gregorian calendar date for [h], or null when it falls outside the
/// Umm al-Qurā table the `hijri` package ships.
DateTime? gregorianFromHijri(HijriDay h) {
  try {
    final g = HijriCalendar().hijriToGregorian(h.year, h.month, h.day);
    final date = DateTime(g.year, g.month, g.day);
    // The table returns a value for some out-of-range inputs rather than
    // failing, so verify by converting back: a date that doesn't round-trip
    // wasn't really representable.
    final back = hijriFromGregorian(date);
    if (back != h) return null;
    return date;
  } catch (_) {
    return null;
  }
}

/// Number of days in Hijri month [month] of [year] (29 or 30).
int daysInHijriMonth(int year, int month) =>
    HijriCalendar().getDaysInMonth(year, month);

/// "1 Ramadan 1447".
String formatHijri(HijriDay h) {
  final name = (h.month >= 1 && h.month <= 12)
      ? _monthNames[h.month - 1]
      : 'Month ${h.month}';
  return '${h.day} $name ${h.year}';
}

/// The next Gregorian date on or after [from] whose Hijri month and day match
/// [anchor]. The anchor's *year* is ignored — it identifies which day of the
/// Islamic year recurs.
///
/// When the anchor day doesn't exist in the target year's month (a 30th in a
/// 29-day month) it clamps to that month's last day. Rolling forward instead
/// would migrate the anniversary into the following month, which is the one
/// thing an anniversary must never do.
///
/// Returns null when no occurrence is representable in the conversion table.
DateTime? nextHijriOccurrence({
  required HijriDay anchor,
  required DateTime from,
}) {
  final fromDate = DateTime(from.year, from.month, from.day);
  final startYear = hijriFromGregorian(fromDate).year;

  // Two candidate years is enough: the anchor either still lies ahead in the
  // current Hijri year or falls in the next one.
  for (var year = startYear; year <= startYear + 2; year++) {
    final lastDay = daysInHijriMonth(year, anchor.month);
    final day = anchor.day > lastDay ? lastDay : anchor.day;
    final candidate = gregorianFromHijri(HijriDay(year, anchor.month, day));
    if (candidate == null) continue;
    if (!candidate.isBefore(fromDate)) return candidate;
  }
  return null;
}

/// The next occurrence on or after [from] of an event starting at [start]
/// under [rrule].
///
/// Supports only `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY` with an optional
/// `INTERVAL`, which is the whole of what the calendar UI can create. An
/// unsupported rule returns null rather than being coerced into the nearest
/// supported one — putting an event on a confidently wrong day is worse than
/// showing no next occurrence.
///
/// Day-of-month is clamped, so a 29 February or 31st-of-the-month anniversary
/// stays in its month instead of spilling into the next.
DateTime? nextGregorianOccurrence({
  required DateTime start,
  required String? rrule,
  required DateTime from,
}) {
  final startDate = DateTime(start.year, start.month, start.day);
  final fromDate = DateTime(from.year, from.month, from.day);

  if (rrule == null || rrule.trim().isEmpty) {
    return startDate.isBefore(fromDate) ? null : startDate;
  }

  final parts = <String, String>{};
  for (final segment in rrule.toUpperCase().split(';')) {
    final kv = segment.split('=');
    if (kv.length == 2) parts[kv[0].trim()] = kv[1].trim();
  }

  final freq = parts['FREQ'];
  final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
  if (interval < 1) return null;
  // Validate the rule BEFORE the "start is still ahead" shortcut. Taking the
  // shortcut first would return the start date for a rule this function can't
  // actually expand, reporting a real-looking occurrence for a recurrence it
  // does not understand.
  if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
    return null;
  }
  if (!startDate.isBefore(fromDate)) return startDate;

  switch (freq) {
    case 'DAILY':
      final elapsed = fromDate.difference(startDate).inDays;
      final steps = (elapsed / interval).ceil();
      return startDate.add(Duration(days: steps * interval));

    case 'WEEKLY':
      final elapsedWeeks = fromDate.difference(startDate).inDays / 7;
      final steps = (elapsedWeeks / interval).ceil();
      return startDate.add(Duration(days: steps * interval * 7));

    case 'MONTHLY':
      final elapsed = (fromDate.year - startDate.year) * 12 +
          (fromDate.month - startDate.month);
      var steps = (elapsed / interval).ceil();
      for (var attempt = 0; attempt < 4; attempt++) {
        final candidate = _clampedDate(
          startDate.year,
          startDate.month + steps * interval,
          startDate.day,
        );
        if (!candidate.isBefore(fromDate)) return candidate;
        steps++;
      }
      return null;

    case 'YEARLY':
      final elapsed = fromDate.year - startDate.year;
      var steps = (elapsed / interval).ceil();
      for (var attempt = 0; attempt < 4; attempt++) {
        final candidate = _clampedDate(
          startDate.year + steps * interval,
          startDate.month,
          startDate.day,
        );
        if (!candidate.isBefore(fromDate)) return candidate;
        steps++;
      }
      return null;

    default:
      return null;
  }
}

/// Builds a date with [day] clamped to the real length of the target month, so
/// month arithmetic never rolls over into the following month.
DateTime _clampedDate(int year, int month, int day) {
  // DateTime normalises out-of-range months, so derive the true year/month
  // first, then clamp the day against that month's length.
  final normalised = DateTime(year, month, 1);
  final lastDay = DateTime(normalised.year, normalised.month + 1, 0).day;
  return DateTime(
    normalised.year,
    normalised.month,
    day > lastDay ? lastDay : day,
  );
}

/// Encodes an all-day calendar date for storage in a `timestamptz` column.
///
/// All-day events are *calendar dates*, not instants: an anniversary is "14
/// March" everywhere, not a moment that lands on the 13th for whoever is far
/// enough west. Pinning them to UTC midnight and reading only the date fields
/// back out ([allDayDateFrom]) keeps both spouses seeing the same day — the
/// same discipline `lib/core/time/local_day.dart` enforces for prayer days.
DateTime allDayInstant(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Reads an all-day event's calendar date back out, ignoring zone entirely.
DateTime allDayDateFrom(DateTime stored) {
  final utc = stored.toUtc();
  return DateTime(utc.year, utc.month, utc.day);
}
