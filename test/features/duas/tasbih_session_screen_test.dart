import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/notification_providers.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/duas/data/tasbih_channel.dart';
import 'package:lovinity/features/duas/data/tasbih_repository.dart';
import 'package:lovinity/features/duas/domain/tasbih_providers.dart';
import 'package:lovinity/features/duas/presentation/tasbih_session_screen.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/shared/models/couple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repo extends Fake implements TasbihRepository {
  final saved = <int>[];
  int mine = 10, spouse = 5;
  bool fail = false;
  @override
  Future<CounterTotals> totals(String counterId, {required String selfId}) async =>
      CounterTotals(mine: mine, spouse: spouse);
  @override
  Future<void> addContribution({
    required String counterId,
    required String coupleId,
    required String userId,
    required int count,
  }) async {
    if (fail) throw Exception('offline');
    saved.add(count);
  }
}

class _Chan extends Fake implements TasbihChannel {
  final deltas = StreamController<int>.broadcast();
  final here = StreamController<bool>.broadcast();
  int taps = 0;
  @override
  Stream<int> get spouseDeltas => deltas.stream;
  @override
  Stream<bool> get spouseHere => here.stream;
  @override
  void tap() => taps++;
  @override
  Future<void> dispose() async {}
}

class _Notifs extends Fake implements NotificationStore {
  final kinds = <String>[];
  @override
  Future<void> insertBestEffort({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) async =>
      kinds.add(kind);
}

final _session = Session(
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

Future<(_Repo, _Chan, _Notifs)> _pump(
  WidgetTester tester, {
  int mine = 10,
  int spouse = 5,
}) async {
  final repo = _Repo()
    ..mine = mine
    ..spouse = spouse;
  final chan = _Chan();
  final notifs = _Notifs();
  final counter = DhikrCounter(
    id: 'k1',
    title: 'Salawat',
    arabicText: null,
    target: 20,
    period: 'weekly',
    startsAt: DateTime.utc(2026, 11, 10),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasbihRepositoryProvider.overrideWithValue(repo),
        tasbihChannelProvider('k1').overrideWithValue(chan),
        tasbihCountersProvider
            .overrideWith((ref) => Stream.value([counter])),
        notificationStoreProvider.overrideWithValue(notifs),
        authSessionProvider.overrideWith((ref) => Stream.value(_session)),
        currentCoupleProvider.overrideWith(
          (ref) => Stream.value(const Couple(
            id: 'c1',
            memberA: 'me',
            memberB: 'sp',
            status: 'active',
            longDistance: false,
          )),
        ),
        spouseProfileProvider.overrideWith((ref) async => null),
      ],
      child: Consumer(builder: (_, ref, _) {
        ref.watch(currentCoupleProvider);
        ref.watch(authSessionProvider);
        return MaterialApp(
          theme: LovTheme.dark(),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => const TasbihSessionScreen(counterId: 'k1'),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        );
      }),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (repo, chan, notifs);
}

void main() {
  testWidgets('taps + spouse delta reach goal once', (tester) async {
    final (_, chan, notifs) = await _pump(tester);
    expect(find.text('15 / 20'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    chan.deltas.add(3);
    await tester.pump();
    expect(find.text('20 / 20'), findsOneWidget);
    expect(chan.taps, 2);
    expect(notifs.kinds, ['tasbih']);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.pump();
    expect(notifs.kinds, ['tasbih']);
  });

  testWidgets('already at target on open does not notify', (tester) async {
    final (_, _, notifs) = await _pump(tester, mine: 20, spouse: 0);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.pump();
    expect(notifs.kinds, isEmpty);
  });

  testWidgets('pause flushes pending taps', (tester) async {
    final (repo, _, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(repo.saved, [2]);
  });

  testWidgets('popping saves the pending tap once', (tester) async {
    final (repo, _, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(repo.saved, [1]);
  });

  Future<void> reopen(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void popIt(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator)).pop();

  testWidgets('reopen after saved session shows fresh total, one notification',
      (tester) async {
    final (repo, _, notifs) = await _pump(tester);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('tasbih-tap')));
    }
    await tester.pump();
    expect(notifs.kinds, ['tasbih']);
    popIt(tester);
    await tester.pumpAndSettle();
    expect(repo.saved, [5]);
    repo.mine = 15;
    await reopen(tester);
    expect(find.text('20 / 20'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.pump();
    expect(notifs.kinds, ['tasbih']);
  });

  testWidgets('offline leave retries later; reopen includes pending',
      (tester) async {
    final (repo, _, _) = await _pump(tester);
    repo.fail = true;
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    popIt(tester);
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    // (c) reopen while still unsaved: db 15 + pending 2
    await reopen(tester);
    expect(find.text('17 / 20'), findsOneWidget);
    popIt(tester);
    await tester.pumpAndSettle();
    // (b) connection returns; the 5 s retry saves the pending count
    repo.fail = false;
    await tester.pump(const Duration(seconds: 6));
    expect(repo.saved, [2]);
  });

  testWidgets('waits for the couple: Connecting… then works, survives errors',
      (tester) async {
    final couple = StreamController<Couple>();
    addTearDown(couple.close);
    final repo = _Repo();
    final chan = _Chan();
    final counter = DhikrCounter(
      id: 'k1',
      title: 'Salawat',
      arabicText: null,
      target: 20,
      period: 'weekly',
      startsAt: DateTime.utc(2026, 11, 10),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tasbihRepositoryProvider.overrideWithValue(repo),
        tasbihChannelProvider('k1').overrideWithValue(chan),
        tasbihCountersProvider.overrideWith((ref) => Stream.value([counter])),
        notificationStoreProvider.overrideWithValue(_Notifs()),
        authSessionProvider.overrideWith((ref) => Stream.value(_session)),
        currentCoupleProvider.overrideWith((ref) => couple.stream),
        spouseProfileProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: LovTheme.dark(),
        home: const TasbihSessionScreen(counterId: 'k1'),
      ),
    ));
    await tester.pump();
    // Loading couple: gentle wait, nothing opened.
    expect(find.text('Connecting…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Error with no value yet: still waiting, no throw.
    couple.addError(Exception('ws down'));
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    couple.add(const Couple(
      id: 'c1',
      memberA: 'me',
      memberB: 'sp',
      status: 'active',
      longDistance: false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('15 / 20'), findsOneWidget);

    // Websocket error after a value: keeps the previous couple, keeps working.
    couple.addError(Exception('ws down'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('tasbih-tap')));
    await tester.pump();
    expect(find.text('16 / 20'), findsOneWidget);
    expect(chan.taps, 1);
  });
}
