import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/calendar/domain/calendar_providers.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/domain/adhkar_providers.dart';
import 'package:lovinity/features/duas/domain/dua_library_providers.dart';
import 'package:lovinity/features/duas/domain/dua_suggestions.dart';
import 'package:lovinity/features/duas/domain/suggestion_providers.dart';
import 'package:lovinity/features/duas/presentation/dua_for_today_card.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/shared/models/user_profile.dart';
import 'package:lovinity/shared/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'adhkar_progress_store_test.dart' show MemStorage;

const _profile = UserProfile(
  id: 'me',
  displayName: 'Me',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'x',
);

LibraryDua _d(String id, String tag) => LibraryDua(
      id: id,
      title: 'Dua $id',
      arabic: 'x',
      translation: 'tr',
      repeatCount: 1,
      tags: [tag],
      sortOrder: 0,
    );

Future<MemStorage> _pump(WidgetTester tester, List<LibraryDua> lib) async {
  final mem = MemStorage();
  final session = Session(
    accessToken: 't',
    tokenType: 'bearer',
    user: const User(
        id: 'me', appMetadata: {}, userMetadata: {}, aud: 'a', createdAt: '2020-01-01'),
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      duaLibraryProvider.overrideWith((ref) async => lib),
      authSessionProvider.overrideWith((ref) => Stream.value(session)),
      ownProfileProvider.overrideWith((ref) async => _profile),
      spouseProfileProvider.overrideWith((ref) async => null),
      upcomingEventsProvider.overrideWithValue(const []),
      secureStorageProvider.overrideWithValue(mem as FlutterSecureStorage),
      nowProvider.overrideWithValue(() => DateTime.utc(2026, 11, 17, 12)),
    ],
    child: Consumer(builder: (_, ref, _) {
      ref.watch(authSessionProvider);
      return MaterialApp(
        theme: LovTheme.dark(),
        home: const Scaffold(body: SingleChildScrollView(child: DuaForTodayCard())),
      );
    }),
  ));
  await tester.pumpAndSettle();
  return mem;
}

void main() {
  setUpAll(() async => initTimezones());

  testWidgets('empty library renders nothing', (tester) async {
    await _pump(tester, const []);
    expect(find.text('DUA FOR TODAY · FOR THE TWO OF YOU'), findsNothing);
  });

  testWidgets('mood chip writes, re-renders, and clears', (tester) async {
    final mem = await _pump(tester, [_d('a', 'distress'), _d('b', 'dhikr')]);
    expect(find.text('DUA FOR TODAY · FOR THE TWO OF YOU'), findsOneWidget);
    await tester.tap(find.text('Anxious'));
    await tester.pumpAndSettle();
    expect(mem.data['mood:2026-11-17'], 'anxious');
    expect(find.text("Because you're feeling anxious"), findsOneWidget);
    await tester.tap(find.text('Anxious'));
    await tester.pumpAndSettle();
    expect(mem.data.containsKey('mood:2026-11-17'), isFalse);
    expect(find.text("Because you're feeling anxious"), findsNothing);
  });

  testWidgets('resume past local midnight resets mood and day key (no tab)',
      (tester) async {
    // Pacific/Auckland is UTC+13 in November.
    var now = DateTime.utc(2026, 11, 16, 10, 30); // 23:30 on the 16th
    final c = ProviderContainer(overrides: [
      ownProfileProvider.overrideWith((ref) async => const UserProfile(
            id: 'me',
            displayName: 'Me',
            timezone: 'Pacific/Auckland',
            madhhab: 'shafi',
            calcMethod: 'x',
          )),
      secureStorageProvider
          .overrideWithValue(MemStorage() as FlutterSecureStorage),
      nowProvider.overrideWithValue(() => now),
    ]);
    c.listen(dayTickProvider, (_, _) {}); // as HomeScreen does
    await c.read(ownProfileProvider.future);
    expect(c.read(adhkarTodayKeyProvider), '2026-11-16');
    await c.read(todayMoodProvider.future);
    await c.read(todayMoodProvider.notifier).set(Mood.anxious);
    expect(c.read(todayMoodProvider).value, Mood.anxious);

    now = DateTime.utc(2026, 11, 16, 11, 30); // 00:30 on the 17th
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.read(adhkarTodayKeyProvider), '2026-11-17');
    expect(await c.read(todayMoodProvider.future), isNull);
    c.dispose(); // cancels the midnight timer
  });
}
