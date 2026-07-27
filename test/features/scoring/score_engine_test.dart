import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/shared/models/cycle_record.dart';
import 'package:lovinity/features/scoring/domain/score_engine.dart';

void main() {
  final all = {Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha};
  DayLog full(DateTime d) => DayLog(date: d, prayed: {...all});
  DayLog some(DateTime d, Set<Prayer> p) => DayLog(date: d, prayed: p);

  test('pct = prayed / due over the window', () {
    final logs = [
      full(DateTime(2026, 7, 1)),
      some(DateTime(2026, 7, 2), {Prayer.fajr, Prayer.dhuhr}),
    ];
    final r = computeScore(
      logs: logs, cycles: const [],
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 2));
    expect(r.due, 10);
    expect(r.prayed, 7);
    expect(r.pct, closeTo(0.7, 1e-9));
  });

  test('exempt days are removed from the denominator', () {
    final cycles = [CycleRecord(
      id: 'c', userId: 'u', coupleId: 'c', visibility: 'private',
      startedOn: DateTime(2026, 7, 2), endedOn: DateTime(2026, 7, 2))];
    final logs = [full(DateTime(2026, 7, 1))]; // nothing logged on the 2nd
    final r = computeScore(
      logs: logs, cycles: cycles,
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 2));
    expect(r.due, 5); // only the 1st counts
    expect(r.prayed, 5);
    expect(r.pct, 1.0);
  });

  test('streak freezes across an exempt gap instead of breaking', () {
    final cycles = [CycleRecord(
      id: 'c', userId: 'u', coupleId: 'c', visibility: 'private',
      startedOn: DateTime(2026, 7, 3), endedOn: DateTime(2026, 7, 4))];
    final logs = [
      full(DateTime(2026, 7, 1)),
      full(DateTime(2026, 7, 2)),
      // 3rd & 4th exempt, no logs
      full(DateTime(2026, 7, 5)),
    ];
    final r = computeScore(
      logs: logs, cycles: cycles,
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 5));
    expect(r.currentStreak, 3); // 1,2,(skip 3,4),5 all prayed
  });

  test('a missed non-exempt day breaks the streak', () {
    final logs = [
      full(DateTime(2026, 7, 1)),
      some(DateTime(2026, 7, 2), {Prayer.fajr}), // missed day
      full(DateTime(2026, 7, 3)),
    ];
    final r = computeScore(
      logs: logs, cycles: const [],
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 3));
    expect(r.currentStreak, 1); // only the 3rd
  });
}
