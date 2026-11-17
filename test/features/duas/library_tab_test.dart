import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/chat/domain/chat_service.dart';
import 'package:lovinity/features/chat/domain/chat_providers.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/data/dua_repository.dart';
import 'package:lovinity/features/duas/domain/dua_library_providers.dart';
import 'package:lovinity/features/duas/domain/dua_providers.dart';
import 'package:lovinity/features/duas/domain/dua_share.dart';
import 'package:lovinity/features/duas/presentation/dua_list_screen.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/shared/models/couple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeChat extends Fake implements ChatService {
  final sent = <String>[];
  Completer<void>? gate;
  @override
  Future<void> sendText(String body, {String? replyToMessageId}) async {
    sent.add(body);
    await gate?.future;
  }
}

class _FakeRepo extends Fake implements DuaRepository {
  final calls = <Map<String, Object?>>[];
  bool fail = false;
  @override
  Future<void> add({
    required String coupleId,
    required String userId,
    required String title,
    String? body,
    String visibility = 'shared',
  }) async {
    if (fail) throw Exception('boom');
    calls.add({'title': title, 'body': body, 'visibility': visibility});
  }
}

const _eat = LibraryDua(
  id: '1',
  title: 'Before eating',
  arabic: 'بسم الله',
  translation: 'In the name of Allah',
  category: 'food',
  repeatCount: 1,
  tags: ['eating'],
  sortOrder: 0,
);
const _trip = LibraryDua(
  id: '2',
  title: 'Travel dua',
  arabic: 'سبحان',
  translation: 'Glory to Him',
  category: 'travel',
  repeatCount: 1,
  tags: [],
  sortOrder: 1,
);
const _morning = LibraryDua(
  id: '3',
  title: 'Morning',
  arabic: 'أصبحنا',
  translation: 'We have reached morning',
  category: 'morning',
  repeatCount: 1,
  tags: [],
  sortOrder: 2,
);

Future<void> _pump(
  WidgetTester tester,
  List<LibraryDua> duas, {
  _FakeChat? chat,
  _FakeRepo? repo,
}) async {
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
        duasProvider.overrideWith((ref) => Stream.value(const <Dua>[])),
        authSessionProvider.overrideWith((ref) => Stream.value(session)),
        currentCoupleProvider.overrideWith(
          (ref) => Stream.value(
            const Couple(
              id: 'c1',
              memberA: 'me',
              memberB: 'sp',
              status: 'active',
              longDistance: false,
            ),
          ),
        ),
        chatServiceProvider.overrideWith((ref) async => chat),
        duaRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
      ],
      child: Consumer(
        builder: (_, ref, _) {
          // Keep alive, as duasProvider does in the real app.
          ref.watch(currentCoupleProvider);
          ref.watch(authSessionProvider);
          return MaterialApp(
            theme: LovTheme.dark(),
            home: const DuaListScreen(),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Library'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search filters rows', (tester) async {
    await _pump(tester, [_eat, _trip]);
    await tester.enterText(find.byType(TextField), 'eating');
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Before eating'), findsOneWidget);
  });

  testWidgets('category chip filters, adhkar categories excluded', (
    tester,
  ) async {
    await _pump(tester, [_eat, _trip, _morning]);
    expect(find.widgetWithText(ChoiceChip, 'morning'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'travel'));
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Travel dua'), findsOneWidget);
  });

  testWidgets('no match and empty states', (tester) async {
    await _pump(tester, [_eat]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No duas match "zzz".'), findsOneWidget);
  });

  testWidgets('empty library', (tester) async {
    await _pump(tester, []);
    expect(find.text('Duas are on their way.'), findsOneWidget);
  });

  testWidgets('send to spouse', (tester) async {
    final chat = _FakeChat();
    await _pump(tester, [_eat], chat: chat);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to spouse'));
    await tester.pumpAndSettle();
    expect(chat.sent, [formatDuaForChat(_eat)]);
    expect(find.text('Sent to your spouse'), findsOneWidget);
  });

  testWidgets('send fails when chat null', (tester) async {
    await _pump(tester, [_eat]);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to spouse'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't send — try again from chat"), findsOneWidget);
  });

  testWidgets('add to our list', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, [_eat], repo: repo);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to our list'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repo.calls.single['visibility'], 'shared');
    expect(repo.calls.single['body'], duaListBody(_eat));
    expect(find.text('Added to your shared list'), findsOneWidget);
  });

  testWidgets('double tap send sends once; success pops sheet and toasts', (
    tester,
  ) async {
    final chat = _FakeChat();
    await _pump(tester, [_eat], chat: chat);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    final btn = find.text('Send to spouse');
    await tester.tap(btn);
    await tester.tap(btn, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(chat.sent, hasLength(1));
    expect(find.text('Send to spouse'), findsNothing);
    expect(find.text('Sent to your spouse'), findsOneWidget);
  });

  testWidgets('add failure keeps sheet open with message', (tester) async {
    final repo = _FakeRepo()..fail = true;
    await _pump(tester, [_eat], repo: repo);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to our list'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't add — try again"), findsOneWidget);
    expect(find.text('Add to our list'), findsOneWidget);
  });

  testWidgets('sheet dismissed mid-send: success does not pop the screen', (
    tester,
  ) async {
    final chat = _FakeChat()..gate = Completer<void>();
    await _pump(tester, [_eat], chat: chat);
    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to spouse'));
    await tester.pump();
    Navigator.of(tester.element(find.text('Send to spouse'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Send to spouse'), findsNothing);
    chat.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Our duas'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Sent to your spouse'), findsOneWidget);
  });
}
