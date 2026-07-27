// test/features/cycle/cycle_prediction_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/shared/models/cycle_record.dart';
import 'package:lovinity/features/cycle/domain/cycle_prediction.dart';

void main() {
  CycleRecord r(String id, DateTime s, DateTime? e) =>
      CycleRecord(id: id, userId: 'u', coupleId: 'c',
          startedOn: s, endedOn: e, visibility: 'private');

  test('maxHaidDays: hanafi 10, shafi 15', () {
    expect(maxHaidDays('hanafi'), 10);
    expect(maxHaidDays('shafi'), 15);
  });

  test('predictCycle averages start-to-start gaps and projects next start', () {
    // Starts 28 days apart: Jun 1, Jun 29, Jul 27.
    final history = [
      r('3', DateTime(2026, 7, 27), DateTime(2026, 8, 1)),
      r('2', DateTime(2026, 6, 29), DateTime(2026, 7, 4)),
      r('1', DateTime(2026, 6, 1), DateTime(2026, 6, 6)),
    ];
    final p = predictCycle(history);
    expect(p.avgCycleLength, 28);
    expect(p.avgPeriodLength, 5); // Jun1-6 => 5 day gaps averaged
    expect(p.nextStart, DateTime(2026, 8, 24)); // Jul 27 + 28
  });

  test('predictCycle returns nulls with fewer than two cycles', () {
    final p = predictCycle([r('1', DateTime(2026, 6, 1), DateTime(2026, 6, 6))]);
    expect(p.avgCycleLength, isNull);
    expect(p.nextStart, isNull);
  });
}
