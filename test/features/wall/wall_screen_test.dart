import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/motion/motion.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/features/wall/presentation/add_to_wall_sheet.dart';
import 'package:lovinity/features/wall/presentation/wall_screen.dart';
import 'package:lovinity/shared/models/couple.dart';

import 'fakes.dart';

WallItem _item(String id, String title,
        {WallCollection? collection, bool pinned = false, String by = 'sp'}) =>
    WallItem(
      id: id, coupleId: 'c1', addedBy: by, url: 'https://example.com/$id',
      title: title, source: WallSource.article, collection: collection,
      isPinned: pinned, createdAt: DateTime.now(),
    );

Future<void> pumpWall(
  WidgetTester tester,
  Stream<List<WallItem>> items, {
  SecureStore? store,
  ValueNotifier<bool>? visible,
  Stream<List<WallItem>> Function()? itemsBuilder,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  await tester.pumpWidget(ProviderScope(
    // No automatic retry: the error state must be observable and the retry
    // button is what reloads.
    retry: (_, _) => null,
    overrides: [
      wallItemsProvider.overrideWith((ref) => itemsBuilder?.call() ?? items),
      wallReactionsProvider.overrideWith((ref) => Stream.value(const <WallReaction>[])),
      wallCommentsProvider.overrideWith((ref) => Stream.value(const <WallComment>[])),
      wallSelfIdProvider.overrideWithValue('me'),
      ownProfileProvider.overrideWith((ref) async => null),
      spouseProfileProvider.overrideWith((ref) async => null),
      secureStoreProvider.overrideWithValue(store ?? InMemorySecureStore()),
      currentCoupleProvider.overrideWith((ref) => Stream.value(const Couple(
          id: 'c1', memberA: 'me', memberB: 'sp', status: 'active', longDistance: false))),
      wallRepositoryProvider.overrideWithValue(FakeWallRepository()),
      linkPreviewServiceProvider.overrideWithValue(FakeLinkPreviewService()),
    ],
    child: MaterialApp(
      theme: LovTheme.dark(),
      home: visible == null
          ? const WallScreen()
          : ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) => show ? const WallScreen() : const SizedBox(),
            ),
    ),
  ));
}

void main() {
  testWidgets('shows skeletons while loading', (tester) async {
    await pumpWall(tester, const Stream<List<WallItem>>.empty());
    await tester.pump();
    expect(find.byKey(const Key('wall-skeleton')), findsWidgets);
  });

  testWidgets('empty Wall invites the first share', (tester) async {
    await pumpWall(tester, Stream.value(const <WallItem>[]));
    await tester.pumpAndSettle();
    expect(find.text('Share your first find'), findsOneWidget);
  });

  testWidgets('renders cards, pinned row and filters by collection', (tester) async {
    await pumpWall(tester, Stream.value([
      _item('a', 'Lamb biryani', collection: WallCollection.recipes, pinned: true),
      _item('b', 'Lake cabin', collection: WallCollection.places),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Our Wall'), findsOneWidget);
    expect(find.text('2 things shared this week'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('Lake cabin'), findsOneWidget);

    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Lake cabin'), findsNothing);
    // 'Lamb biryani' remains in the feed (and in the unfiltered pinned row).
    expect(find.text('Lamb biryani'), findsWidgets);
  });

  testWidgets('the + button opens the add sheet', (tester) async {
    await pumpWall(tester, Stream.value(const <WallItem>[]));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to our Wall'));
    await tester.pumpAndSettle();
    expect(find.byType(AddToWallSheet), findsOneWidget);
  });

  testWidgets('a live arrival animates only the new card', (tester) async {
    final controller = StreamController<List<WallItem>>.broadcast();
    addTearDown(controller.close);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = _item('a', 'Alpha');
    final b = _item('b', 'Bravo');
    final c = _item('c', 'Charlie');

    await pumpWall(tester, controller.stream);
    controller.add([a, b]);
    await tester.pumpAndSettle();

    double opacityOf(String title) {
      final enter = find.ancestor(of: find.text(title), matching: find.byType(LovEnter));
      final opacity = find.descendant(of: enter, matching: find.byType(Opacity)).first;
      return tester.widget<Opacity>(opacity).opacity;
    }

    expect(opacityOf('Alpha'), 1.0);
    expect(opacityOf('Bravo'), 1.0);

    controller.add([c, a, b]);
    await tester.pump(); // build the new list
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Charlie'), findsOneWidget);
    expect(opacityOf('Alpha'), 1.0, reason: 'shifted card must not re-animate');
    expect(opacityOf('Bravo'), 1.0, reason: 'shifted card must not re-animate');
    expect(opacityOf('Charlie'), lessThan(1.0), reason: 'new card is entering');
    await tester.pumpAndSettle();
    expect(opacityOf('Charlie'), 1.0);
  });

  testWidgets('leaving the Wall marks this account\'s visit', (tester) async {
    final store = InMemorySecureStore();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await pumpWall(tester, Stream.value(const <WallItem>[]),
        store: store, visible: visible);
    await tester.pumpAndSettle();
    expect(await store.read('wall.last_visit.me'), isNull);

    visible.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await store.read('wall.last_visit.me'), isNotNull);
  });

  testWidgets('a load error offers a retry that reloads', (tester) async {
    var calls = 0;
    await pumpWall(
      tester,
      const Stream<List<WallItem>>.empty(),
      itemsBuilder: () {
        calls++;
        return calls == 1
            ? Stream<List<WallItem>>.error(Exception('x'))
            : Stream.value(const <WallItem>[]);
      },
    );
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't load the Wall"), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text("Couldn't load the Wall"), findsNothing);
    expect(find.text('Share your first find'), findsOneWidget);
  });
}
