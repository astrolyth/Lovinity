import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/shared/models/cycle_record.dart';
import 'package:lovinity/features/cycle/domain/cycle_providers.dart';
import 'package:lovinity/features/cycle/presentation/cycle_screen.dart';

void main() {
  testWidgets('shows Start button when no active cycle', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    expect(find.text('Start period'), findsOneWidget);
  });

  testWidgets('shows End button + resting message during active cycle', (tester) async {
    final active = CycleRecord(
      id: 'a', userId: 'u', coupleId: 'c',
      startedOn: DateTime.now().subtract(const Duration(days: 1)),
      endedOn: null, visibility: 'private');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value([active])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    expect(find.text('End period'), findsOneWidget);
    expect(find.textContaining('Resting'), findsWidgets);
  });
}
