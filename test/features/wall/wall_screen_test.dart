import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
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

Future<void> pumpWall(WidgetTester tester, Stream<List<WallItem>> items) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wallItemsProvider.overrideWith((ref) => items),
      wallReactionsProvider.overrideWith((ref) => Stream.value(const <WallReaction>[])),
      wallCommentsProvider.overrideWith((ref) => Stream.value(const <WallComment>[])),
      wallSelfIdProvider.overrideWithValue('me'),
      ownProfileProvider.overrideWith((ref) async => null),
      spouseProfileProvider.overrideWith((ref) async => null),
      secureStoreProvider.overrideWithValue(InMemorySecureStore()),
      currentCoupleProvider.overrideWith((ref) => Stream.value(const Couple(
          id: 'c1', memberA: 'me', memberB: 'sp', status: 'active', longDistance: false))),
      wallRepositoryProvider.overrideWithValue(FakeWallRepository()),
      linkPreviewServiceProvider.overrideWithValue(FakeLinkPreviewService()),
    ],
    child: MaterialApp(theme: LovTheme.dark(), home: const WallScreen()),
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
}
