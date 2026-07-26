import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/prayer_log/presentation/prayer_log_screen.dart';
import 'package:lovinity/shared/models/cycle_record.dart';

CycleRecord _record({
  required DateTime startedOn,
  DateTime? endedOn,
}) =>
    CycleRecord(
      id: 'rec-1',
      userId: 'user-1',
      coupleId: 'couple-1',
      startedOn: startedOn,
      endedOn: endedOn,
      visibility: 'private',
    );

void main() {
  final selectedDate = DateTime(2026, 7, 15);

  test('true when isWife and a CycleRecord isActiveOn selectedDate', () {
    final record = _record(
      startedOn: DateTime(2026, 7, 14),
      endedOn: DateTime(2026, 7, 16),
    );

    final result = isSelectedDateExemptForCurrentUser(
      isWife: true,
      ownCycleHistory: [record],
      selectedDate: selectedDate,
    );

    expect(result, isTrue);
  });

  test('false when not a wife even if a record is active', () {
    final record = _record(
      startedOn: DateTime(2026, 7, 14),
      endedOn: DateTime(2026, 7, 16),
    );

    final result = isSelectedDateExemptForCurrentUser(
      isWife: false,
      ownCycleHistory: [record],
      selectedDate: selectedDate,
    );

    expect(result, isFalse);
  });

  test('false when wife but no record covers the date', () {
    final record = _record(
      startedOn: DateTime(2026, 6, 1),
      endedOn: DateTime(2026, 6, 5),
    );

    final result = isSelectedDateExemptForCurrentUser(
      isWife: true,
      ownCycleHistory: [record],
      selectedDate: selectedDate,
    );

    expect(result, isFalse);
  });
}
