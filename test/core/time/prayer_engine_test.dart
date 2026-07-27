import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';

void main() {
  setUpAll(() async {
    await initTimezones();
  });

  const london = PrayerLocation(
    latitude: 51.5074,
    longitude: -0.1278,
    timezone: 'Europe/London',
  );

  const mecca = PrayerLocation(
    latitude: 21.4225,
    longitude: 39.8262,
    timezone: 'Asia/Riyadh',
  );

  const nyc = PrayerLocation(
    latitude: 40.7128,
    longitude: -74.0060,
    timezone: 'America/New_York',
  );

  test('returns five prayers ordered by time', () {
    final times = prayerTimesForDay(
      date: DateTime(2026, 3, 20),
      loc: london,
    );

    expect(times.map((p) => p.prayer), [
      Prayer.fajr,
      Prayer.dhuhr,
      Prayer.asr,
      Prayer.maghrib,
      Prayer.isha,
    ]);

    for (var i = 1; i < times.length; i++) {
      expect(
        times[i].at.isAfter(times[i - 1].at),
        isTrue,
        reason: '${times[i].prayer} must be after ${times[i - 1].prayer}',
      );
    }
  });

  // Regression: the engine used to convert adhan's already-offset time as if
  // it were a real UTC instant, applying the timezone offset twice. Every
  // other test here is relative (ordering / DST offset), so a uniform shift
  // slipped through. These assert real wall-clock values.

  test('positive offset: Mecca Dhuhr sits at local solar noon, not shifted', () {
    final dhuhr = prayerTimesForDay(date: DateTime(2026, 6, 15), loc: mecca)
        .firstWhere((p) => p.prayer == Prayer.dhuhr);
    // Mecca solar noon is ~12:22 local (Asia/Riyadh, UTC+3).
    // Double-shifted it would read 15:22.
    expect(dhuhr.at.hour, 12,
        reason: 'Dhuhr must be near local solar noon, not offset-shifted');
    expect(dhuhr.at.timeZoneOffset, const Duration(hours: 3));
  });

  test('negative offset: Regina Dhuhr sits near local noon, not 6h early', () {
    const regina = PrayerLocation(
      latitude: 50.4452,
      longitude: -104.6189,
      timezone: 'America/Regina', // UTC-6, no DST
    );
    final dhuhr = prayerTimesForDay(date: DateTime(2026, 7, 16), loc: regina)
        .firstWhere((p) => p.prayer == Prayer.dhuhr);
    // Solar noon in Regina is ~12:52 local. Double-shifted it would read ~06:52.
    expect(dhuhr.at.hour, inInclusiveRange(12, 13),
        reason: 'Dhuhr must be near local noon in a negative-offset zone');
    expect(dhuhr.at.timeZoneOffset, const Duration(hours: -6));
  });

  test('Hanafi Asr is later than Shafi Asr', () {
    final shafi = prayerTimesForDay(
      date: DateTime(2026, 6, 15),
      loc: mecca,
      config: const PrayerConfig(madhab: Madhab.shafi),
    ).firstWhere((p) => p.prayer == Prayer.asr);

    final hanafi = prayerTimesForDay(
      date: DateTime(2026, 6, 15),
      loc: mecca,
      config: const PrayerConfig(madhab: Madhab.hanafi),
    ).firstWhere((p) => p.prayer == Prayer.asr);

    expect(hanafi.at.isAfter(shafi.at), isTrue);
  });

  test('DST spring-forward: 2026-03-08 New York Fajr is in EDT', () {
    // After DST switches on 2026-03-08, offset is UTC-4.
    final afterDst = prayerTimesForDay(
      date: DateTime(2026, 3, 10),
      loc: nyc,
    ).first;

    expect(afterDst.at.timeZoneOffset, const Duration(hours: -4));
  });

  test('DST fall-back: 2026-11-05 New York Fajr is in EST', () {
    final afterFallBack = prayerTimesForDay(
      date: DateTime(2026, 11, 5),
      loc: nyc,
    ).first;

    expect(afterFallBack.at.timeZoneOffset, const Duration(hours: -5));
  });

  test('nextPrayer picks tomorrow Fajr when today has passed', () {
    final lateNight = DateTime.utc(2026, 3, 20, 23, 59);
    final next = nextPrayer(now: lateNight, loc: london);
    expect(next.prayer, Prayer.fajr);
    expect(next.at.day, 21);
  });

  test('syncGap is commutative and always non-negative', () {
    final a = DateTime.utc(2026, 6, 1, 5, 15);
    final b = DateTime.utc(2026, 6, 1, 5, 30);
    expect(syncGap(a: a, b: b), const Duration(minutes: 15));
    expect(syncGap(a: b, b: a), const Duration(minutes: 15));
  });

  test('toHijri returns a HijriCalendar with sane bounds', () {
    final h = toHijri(DateTime(2026, 7, 12));
    expect(h.hYear, greaterThan(1400));
    expect(h.hMonth, inInclusiveRange(1, 12));
    expect(h.hDay, inInclusiveRange(1, 30));
  });
}
