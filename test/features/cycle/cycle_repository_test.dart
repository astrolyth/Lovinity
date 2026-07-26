import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/shared/models/cycle_record.dart';

void main() {
  CycleRecord rec({DateTime? start, DateTime? end}) => CycleRecord(
        id: 'r', userId: 'u', coupleId: 'c',
        startedOn: start ?? DateTime(2026, 7, 1),
        endedOn: end, visibility: 'private',
      );

  test('isActiveOn true within an open cycle, false before start', () {
    final r = rec(start: DateTime(2026, 7, 10));
    expect(r.isActiveOn(DateTime(2026, 7, 12)), isTrue);
    expect(r.isActiveOn(DateTime(2026, 7, 9)), isFalse);
  });

  test('isActiveOn respects endedOn (inclusive)', () {
    final r = rec(start: DateTime(2026, 7, 10), end: DateTime(2026, 7, 15));
    expect(r.isActiveOn(DateTime(2026, 7, 15)), isTrue);
    expect(r.isActiveOn(DateTime(2026, 7, 16)), isFalse);
  });
}
