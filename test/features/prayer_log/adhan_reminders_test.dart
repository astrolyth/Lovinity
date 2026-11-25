import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:lovinity/features/prayer_log/domain/adhan_reminders.dart';

void main() {
  setUpAll(initTimezones);

  test('only future prayers are scheduled, with stable per-slot ids', () {
    const loc = PrayerLocation(
      latitude: 51.5074,
      longitude: -0.1278,
      timezone: 'Europe/London',
    );
    final today = prayerTimesForDay(date: DateTime(2026, 11, 25), loc: loc);
    final tomorrow = prayerTimesForDay(date: DateTime(2026, 11, 26), loc: loc);
    // Just after today's Asr: Maghrib and Isha remain, plus all of tomorrow.
    final now = today[2].at.add(const Duration(minutes: 1));

    final slots = adhanSlots([today, tomorrow], now);
    expect(slots.map((s) => s.$1), [7003, 7004, 7005, 7006, 7007, 7008, 7009]);
    expect(slots.first.$2.prayer, Prayer.maghrib);
    expect(adhanSlots(const [], now), isEmpty);
  });
}
