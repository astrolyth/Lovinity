import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/duas/data/adhkar_repository.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/domain/adhkar_providers.dart';
import 'package:lovinity/features/duas/domain/dua_library_providers.dart';
import 'package:lovinity/features/duas/presentation/adhkar_tab.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/shared/models/couple.dart';
import 'package:lovinity/shared/models/user_profile.dart';
import 'package:lovinity/shared/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'adhkar_progress_store_test.dart' show MemStorage;

class _CountingStorage extends MemStorage {
  int reads = 0;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #readAll) reads++;
    return super.noSuchMethod(i);
  }
}

class _FakeRepo extends Fake implements AdhkarRepository {
  final calls = <AdhkarSet>[];
  @override
  Future<void> complete({
    required String coupleId,
    required String userId,
    required String localDate,
    required AdhkarSet set,
  }) async =>
      calls.add(set);
}

LibraryDua _d(String id, int n, int order) => LibraryDua(
      id: id,
      title: 'Item $id',
      arabic: 'x',
      translation: 't',
      category: 'morning',
      repeatCount: n,
      tags: const [],
      sortOrder: order,
    );

const _profile = UserProfile(
  id: 'me',
  displayName: 'Me',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'x',
);

Future<_FakeRepo> _pump(
  WidgetTester tester,
  List<LibraryDua> duas, {
  List<AdhkarCompletion> completions = const [],
  DateTime Function()? clock,
  Future<UserProfile?> Function()? profile,
  MemStorage? storage,
}) async {
  final repo = _FakeRepo();
  final session = Session(
    accessToken: 't',
    tokenType: 'bearer',
    user: const User(
      id: 'me',
      appMetadata: {},
      userMetadata: {},
      aud: 'a',
      createdAt: '2020-01-01',
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        duaLibraryProvider.overrideWith((ref) async => duas),
        authSessionProvider.overrideWith((ref) => Stream.value(session)),
        currentCoupleProvider.overrideWith(
          (ref) => Stream.value(const Couple(
            id: 'c1',
            memberA: 'me',
            memberB: 'sp',
            status: 'active',
            longDistance: false,
          )),
        ),
        ownProfileProvider.overrideWith((ref) => (profile ?? () async => _profile)()),
        spouseProfileProvider.overrideWith((ref) async => null),
        adhkarCompletionsProvider
            .overrideWith((ref) => Stream.value(completions)),
        adhkarRepositoryProvider.overrideWithValue(repo),
        secureStorageProvider
            .overrideWithValue((storage ?? MemStorage()) as FlutterSecureStorage),
        nowProvider.overrideWithValue(clock ?? () => DateTime.utc(2026, 11, 16, 12)),
      ],
      child: Consumer(builder: (_, ref, _) {
        ref.watch(currentCoupleProvider);
        ref.watch(authSessionProvider);
        return MaterialApp(
          theme: LovTheme.dark(),
          home: const Scaffold(body: AdhkarTab()),
        );
      }),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(() async => initTimezones());

  testWidgets('completes once after all repeats; extra tap is a no-op', (
    tester,
  ) async {
    final repo = await _pump(tester, [_d('1', 1, 0), _d('2', 3, 1)]);
    await tester.tap(find.text('Morning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item 1'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Item 2'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();
    expect(repo.calls, [AdhkarSet.morning]);
    expect(find.textContaining('Done — may Allah accept'), findsOneWidget);
  });

  testWidgets('spouse completion shows finished', (tester) async {
    await _pump(tester, [_d('1', 1, 0)], completions: [
      AdhkarCompletion(
        userId: 'sp',
        localDate: '2026-11-16',
        set: AdhkarSet.morning,
        completedAt: DateTime.utc(2026, 11, 16),
      ),
    ]);
    expect(find.textContaining('finished'), findsOneWidget);
  });

  testWidgets('empty library', (tester) async {
    await _pump(tester, []);
    expect(find.text('Adhkar are on their way.'), findsOneWidget);
  });

  test('today key follows profile timezone', () {
    final c = ProviderContainer(overrides: [
      ownProfileProvider.overrideWith((ref) async => const UserProfile(
            id: 'me',
            displayName: 'Me',
            timezone: 'Pacific/Auckland',
            madhhab: 's',
            calcMethod: 'x',
          )),
      nowProvider.overrideWithValue(() => DateTime.utc(2026, 11, 16, 12, 30)),
    ]);
    addTearDown(c.dispose);
    return c.read(ownProfileProvider.future).then((_) {
      expect(c.read(adhkarTodayKeyProvider), '2026-11-17');
    });
  });

  testWidgets('null profile: no store load or delete', (tester) async {
    final st = _CountingStorage();
    await _pump(tester, [_d('1', 1, 0)], profile: () async => null, storage: st);
    expect(st.reads, 0);
    expect(find.text('Adhkar are on their way.'), findsOneWidget);
  });

  testWidgets('resume after midnight resets cards under the new key', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 16, 12);
    final st = MemStorage();
    await _pump(tester, [_d('1', 3, 0)], clock: () => now, storage: st);
    await tester.tap(find.text('Morning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(st.data.keys, ['adhkar:2026-11-16:morning']);
    now = DateTime.utc(2026, 11, 17, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning')); // new card state is collapsed
    await tester.pumpAndSettle();
    expect(find.text('0/3'), findsOneWidget);
    expect(st.data.keys, isEmpty);
  });
}
