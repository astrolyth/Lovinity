import 'package:adhan/adhan.dart' as adhan;
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

/// The five daily prayers Lovinity tracks.
///
/// The upstream [adhan.Prayer] enum also includes `sunrise` and `none`;
/// this app deliberately only surfaces the five obligatory salāt.
enum Prayer { fajr, dhuhr, asr, maghrib, isha }

extension PrayerLabel on Prayer {
  String get displayName => switch (this) {
        Prayer.fajr => 'Fajr',
        Prayer.dhuhr => 'Dhuhr',
        Prayer.asr => 'Asr',
        Prayer.maghrib => 'Maghrib',
        Prayer.isha => 'Isha',
      };
}

/// Location + IANA timezone. TZ comes from the user profile (not the device)
/// so prayer times are reproducible across devices and testable.
class PrayerLocation {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });

  final double latitude;
  final double longitude;
  final String timezone; // IANA, e.g. "Europe/London"
}

enum Madhab { shafi, hanafi }

/// Which set of Fajr/Isha angles to use.
///
/// Wraps [adhan.CalculationMethod]. Lovinity exposes the common presets;
/// users can extend later.
enum CalcMethod {
  muslimWorldLeague,
  egyptian,
  karachi,
  ummAlQura,
  dubai,
  moonsightingCommittee,
  northAmerica,
  kuwait,
  qatar,
  singapore,
  turkey,
  tehran,
}

class PrayerConfig {
  const PrayerConfig({
    this.method = CalcMethod.muslimWorldLeague,
    this.madhab = Madhab.shafi,
  });

  final CalcMethod method;
  final Madhab madhab;
}

/// A prayer + its time in the location's timezone.
class ScheduledPrayer {
  const ScheduledPrayer(this.prayer, this.at);

  final Prayer prayer;
  final tz.TZDateTime at;
}

/// Compute the five prayer times for [date] at [loc].
///
/// Times returned are in the location's timezone using the [timezone] package,
/// independent of the host's clock or timezone.
List<ScheduledPrayer> prayerTimesForDay({
  required DateTime date,
  required PrayerLocation loc,
  PrayerConfig config = const PrayerConfig(),
}) {
  final coords = adhan.Coordinates(loc.latitude, loc.longitude);
  final components = adhan.DateComponents(date.year, date.month, date.day);
  final params = _paramsFor(config);

  // adhan expects a utcOffset; compute the location's offset for [date].
  final location = tz.getLocation(loc.timezone);
  final anchor =
      tz.TZDateTime(location, date.year, date.month, date.day, 12);
  final offset = anchor.timeZoneOffset;

  final times = adhan.PrayerTimes(coords, components, params, utcOffset: offset);

  return [
    ScheduledPrayer(Prayer.fajr, _toTz(times.fajr, location)),
    ScheduledPrayer(Prayer.dhuhr, _toTz(times.dhuhr, location)),
    ScheduledPrayer(Prayer.asr, _toTz(times.asr, location)),
    ScheduledPrayer(Prayer.maghrib, _toTz(times.maghrib, location)),
    ScheduledPrayer(Prayer.isha, _toTz(times.isha, location)),
  ];
}

/// The next prayer after [now] at [loc].
///
/// If Isha has passed today, returns tomorrow's Fajr.
ScheduledPrayer nextPrayer({
  required DateTime now,
  required PrayerLocation loc,
  PrayerConfig config = const PrayerConfig(),
}) {
  final today = prayerTimesForDay(date: now, loc: loc, config: config);
  final upcoming = today.where((p) => p.at.isAfter(now));
  if (upcoming.isNotEmpty) return upcoming.first;

  final tomorrow = prayerTimesForDay(
    date: now.add(const Duration(days: 1)),
    loc: loc,
    config: config,
  );
  return tomorrow.first;
}

/// Time delta between the same prayer logged by two spouses.
Duration syncGap({required DateTime a, required DateTime b}) {
  return a.isAfter(b) ? a.difference(b) : b.difference(a);
}

/// Hijri conversion (based on Umm al-Qurā tabular calendar via the [hijri] package).
HijriCalendar toHijri(DateTime greg) => HijriCalendar.fromDate(greg);

adhan.CalculationParameters _paramsFor(PrayerConfig config) {
  final method = _mapMethod(config.method);
  final params = method.getParameters();
  params.madhab = config.madhab == Madhab.shafi
      ? adhan.Madhab.shafi
      : adhan.Madhab.hanafi;
  return params;
}

adhan.CalculationMethod _mapMethod(CalcMethod m) => switch (m) {
      CalcMethod.muslimWorldLeague => adhan.CalculationMethod.muslim_world_league,
      CalcMethod.egyptian => adhan.CalculationMethod.egyptian,
      CalcMethod.karachi => adhan.CalculationMethod.karachi,
      CalcMethod.ummAlQura => adhan.CalculationMethod.umm_al_qura,
      CalcMethod.dubai => adhan.CalculationMethod.dubai,
      CalcMethod.moonsightingCommittee =>
        adhan.CalculationMethod.moon_sighting_committee,
      CalcMethod.northAmerica => adhan.CalculationMethod.north_america,
      CalcMethod.kuwait => adhan.CalculationMethod.kuwait,
      CalcMethod.qatar => adhan.CalculationMethod.qatar,
      CalcMethod.singapore => adhan.CalculationMethod.singapore,
      CalcMethod.turkey => adhan.CalculationMethod.turkey,
      CalcMethod.tehran => adhan.CalculationMethod.tehran,
    };

/// adhan, given a `utcOffset`, returns the time already shifted into that
/// offset — i.e. the location's wall clock — but still flagged `isUtc: true`.
/// Converting it as an instant would apply the offset a second time (Mecca
/// Dhuhr 12:22 would become 15:22). Rebuild it from its calendar fields so the
/// wall clock is preserved and `location` resolves the real offset/DST.
tz.TZDateTime _toTz(DateTime dt, tz.Location location) {
  return tz.TZDateTime(
    location,
    dt.year,
    dt.month,
    dt.day,
    dt.hour,
    dt.minute,
    dt.second,
  );
}
