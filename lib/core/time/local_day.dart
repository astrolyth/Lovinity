import 'package:timezone/timezone.dart' as tz;

import 'timezone_bootstrap.dart';

/// Per-person calendar-day anchoring.
///
/// A couple's prayer log has TWO day anchors, never one. Ṣalāt obligation is
/// local: a spouse in Dhaka prays her Fajr on her Friday while her husband in
/// Toronto is still in his Thursday afternoon. `prayer_logs.date` therefore
/// stores the *logger's* own calendar day, and any code reading those rows
/// must resolve each row against its own owner's zone.
///
/// Resolving both spouses against a single date key is what produced the
/// original bug: the partner's row was silently dropped and the UI rendered
/// "Not yet" for prayers she had already completed.
///
/// ## The "floating date" convention
///
/// [localDayAt] and [dayForOffset] return a [DateTime] used purely as a
/// *calendar date value* — only `year`/`month`/`day` are meaningful. The
/// object is constructed in the host's zone and its clock fields are
/// arbitrary, so never compare two of these as instants and never hand one to
/// something that reads its time. Format with [dayKey] and compare those.

/// [d] as a stable `YYYY-MM-DD` key, matching the Postgres `date` text form
/// that `prayer_logs.date` round-trips through.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The calendar day in effect in [tzId] at the instant [at].
///
/// An unknown or malformed zone degrades to UTC (via [locationOrUtc]) rather
/// than throwing — a stale or corrupt profile timezone must not be able to
/// take down the prayer log.
DateTime localDayAt(String tzId, DateTime at) {
  final local = tz.TZDateTime.from(at, locationOrUtc(tzId));
  return DateTime(local.year, local.month, local.day);
}

/// The wall-clock time in [tzId] at the instant [at]. Used by the dual clock,
/// which must show each spouse their partner's real local time.
tz.TZDateTime localTimeAt(String tzId, DateTime at) =>
    tz.TZDateTime.from(at, locationOrUtc(tzId));

/// The calendar day [offset] days before today *in [tzId]*.
///
/// `offset: 0` is that zone's today, `1` its yesterday, and so on. Resolving
/// the same offset against each spouse's own zone is what lets one screen
/// show two truthful days at once.
///
/// Steps via the day field rather than `subtract(Duration(days: offset))`:
/// Duration arithmetic on a local [DateTime] shifts by exact hours, so a DST
/// transition in the *host's* zone would land the result on 23:00 of the
/// wrong day. `DateTime`'s constructor normalises out-of-range day values, so
/// underflow across month and year boundaries is handled for us.
DateTime dayForOffset({
  required String tzId,
  required int offset,
  required DateTime at,
}) {
  final today = localDayAt(tzId, at);
  return DateTime(today.year, today.month, today.day - offset);
}

/// Whether [tzA] and [tzB] are on the same calendar day at instant [at].
///
/// Drives the adaptive header: when true the UI shows a single date line, and
/// only expands into the dual clock when the two zones genuinely disagree.
bool zonesAgreeOnDay(String tzA, String tzB, DateTime at) =>
    dayKey(localDayAt(tzA, at)) == dayKey(localDayAt(tzB, at));

/// How far ahead [tzB] is of [tzA] at instant [at], as a signed label such as
/// `+10h`, `-5h 30m`, or `+15m`. Empty when the two zones share an offset.
///
/// Computed from live UTC offsets rather than a static table so DST is
/// reflected — the gap between London and New York really is 5h for part of
/// the year and 4h for the rest.
String utcOffsetLabel(String tzA, String tzB, DateTime at) {
  final delta = localTimeAt(tzB, at).timeZoneOffset -
      localTimeAt(tzA, at).timeZoneOffset;
  if (delta == Duration.zero) return '';

  final sign = delta.isNegative ? '-' : '+';
  final abs = delta.abs();
  final hours = abs.inHours;
  final minutes = abs.inMinutes % 60;

  if (hours == 0) return '$sign${minutes}m';
  if (minutes == 0) return '$sign${hours}h';
  return '$sign${hours}h ${minutes}m';
}
