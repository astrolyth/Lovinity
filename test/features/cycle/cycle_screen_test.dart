import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/shared/models/cycle_record.dart';
import 'package:lovinity/shared/models/user_profile.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/cycle/domain/cycle_providers.dart';
import 'package:lovinity/features/cycle/presentation/cycle_screen.dart';

const _wifeProfile = UserProfile(
  id: 'wife',
  displayName: 'Naziha',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'muslim_world_league',
  gender: 'female',
);

const _husbandProfile = UserProfile(
  id: 'husband',
  displayName: 'Ridwan',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'muslim_world_league',
  gender: 'male',
);

void main() {
  testWidgets('wife: shows Start button when no active cycle', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownProfileProvider.overrideWith((ref) async => _wifeProfile),
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Start period'), findsOneWidget);
  });

  testWidgets('wife: shows End button + resting message during active cycle',
      (tester) async {
    final active = CycleRecord(
      id: 'a', userId: 'u', coupleId: 'c',
      startedOn: DateTime.now().subtract(const Duration(days: 1)),
      endedOn: null, visibility: 'private');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownProfileProvider.overrideWith((ref) async => _wifeProfile),
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value([active])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('End period'), findsOneWidget);
    expect(find.textContaining('Resting'), findsWidgets);
  });

  testWidgets('husband: never sees Start/End period controls', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownProfileProvider.overrideWith((ref) async => _husbandProfile),
        partnerSharedCycleProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Start period'), findsNothing);
    expect(find.text('End period'), findsNothing);
  });

  testWidgets('husband: sees empty state when partner has no shared records',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownProfileProvider.overrideWith((ref) async => _husbandProfile),
        partnerSharedCycleProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nothing shared yet.'), findsOneWidget);
  });

  testWidgets('husband: sees a resting message when partner has an active '
      'shared cycle', (tester) async {
    final active = CycleRecord(
      id: 'a', userId: 'wife', coupleId: 'c',
      startedOn: DateTime.now().subtract(const Duration(days: 1)),
      endedOn: null, visibility: 'shared');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownProfileProvider.overrideWith((ref) async => _husbandProfile),
        partnerSharedCycleProvider.overrideWith((ref) => Stream.value([active])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("resting"), findsWidgets);
    expect(find.text('Start period'), findsNothing);
    expect(find.text('End period'), findsNothing);
  });

  testWidgets('shows a loading indicator until the profile resolves',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: CycleScreen()),
    ));
    // No pump beyond the initial frame: ownProfileProvider is still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Start period'), findsNothing);
  });
}
