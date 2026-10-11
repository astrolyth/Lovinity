import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/features/wall/presentation/wall_item_screen.dart';

import 'fakes.dart';

WallItem _video({String by = 'sp'}) => WallItem(
      id: 'i1', coupleId: 'c1', addedBy: by, url: 'https://youtu.be/abc',
      title: 'The 10-minute habit', source: WallSource.youtube,
      note: 'after Fajr?', isPinned: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

Future<StreamController<List<WallItem>>> _pump(
  WidgetTester tester, {
  required FakeWallRepository repo,
  List<WallItem>? items,
  List<WallComment> comments = const [],
}) async {
  // Tall surface so the lazy ListView builds the comments below the fold.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final itemsCtrl = StreamController<List<WallItem>>.broadcast();
  addTearDown(itemsCtrl.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wallItemsProvider.overrideWith((ref) => itemsCtrl.stream),
      wallReactionsProvider.overrideWith((ref) => Stream.value(const <WallReaction>[])),
      wallCommentsProvider.overrideWith((ref) => Stream.value(comments)),
      wallSelfIdProvider.overrideWithValue('me'),
      spouseProfileProvider.overrideWith((ref) async => null),
      wallRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(theme: LovTheme.dark(), home: const WallItemScreen(itemId: 'i1')),
  ));
  itemsCtrl.add(items ?? [_video()]);
  await tester.pump();
  await tester.pump();
  return itemsCtrl;
}

void main() {
  testWidgets('renders the item, open button, reactions and comments', (tester) async {
    await _pump(tester, repo: FakeWallRepository(), comments: [
      WallComment(id: 'm1', itemId: 'i1', authorId: 'sp', body: 'starting tomorrow',
          createdAt: DateTime.now()),
    ]);
    expect(find.text('The 10-minute habit'), findsOneWidget);
    expect(find.text('after Fajr?'), findsOneWidget);
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.byKey(const Key('reaction-heart')), findsOneWidget);
    expect(find.text('starting tomorrow'), findsOneWidget);
  });

  testWidgets('reaction toggles optimistically and calls the repository', (tester) async {
    final repo = FakeWallRepository();
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('reaction-heart')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.reactionCalls, ['add:heart']);
    expect(find.text('1'), findsOneWidget, reason: 'count shows before the stream confirms');
  });

  testWidgets('a failed reaction rolls back and tells the user', (tester) async {
    final repo = FakeWallRepository()..throwOnReact = Exception('offline');
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('reaction-fire')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('1'), findsNothing);
    expect(find.text("Couldn't save your reaction"), findsOneWidget);
  });

  testWidgets('delete is offered only for my own items', (tester) async {
    await _pump(tester, repo: FakeWallRepository());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Change collection'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('author can delete after confirming', (tester) async {
    final repo = FakeWallRepository();
    await _pump(tester, repo: repo, items: [_video(by: 'me')]);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['i1']);
  });

  testWidgets('shows removed state when the item disappears', (tester) async {
    final ctrl = await _pump(tester, repo: FakeWallRepository());
    expect(find.text('The 10-minute habit'), findsOneWidget);
    ctrl.add(const <WallItem>[]); // spouse deleted it
    await tester.pump();
    await tester.pump(); // stream event lands, then the rebuild frame
    expect(find.text('This item was removed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending a comment calls the repository and clears the field', (tester) async {
    final repo = FakeWallRepository();
    await _pump(tester, repo: repo);
    await tester.enterText(find.widgetWithText(TextField, 'Reply…'), 'deal 🤝');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(repo.comments, ['deal 🤝']);
    expect(find.text('deal 🤝'), findsNothing);
  });
}
