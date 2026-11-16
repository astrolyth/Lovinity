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
  StreamController<List<WallReaction>>? reactions,
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
      wallReactionsProvider.overrideWith((ref) =>
          reactions?.stream ?? Stream.value(const <WallReaction>[])),
      wallCommentsProvider.overrideWith((ref) => Stream.value(comments)),
      wallSelfIdProvider.overrideWithValue('me'),
      spouseProfileProvider.overrideWith((ref) async => null),
      wallRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(theme: LovTheme.dark(), home: const WallItemScreen(itemId: 'i1')),
  ));
  reactions?.add(const <WallReaction>[]);
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

  group('reaction toggles', () {
    const ms200 = Duration(milliseconds: 200);
    const heart = Key('reaction-heart');
    WallReaction mine() =>
        const WallReaction(itemId: 'i1', userId: 'me', kind: WallReactionKind.heart);

    testWidgets('double-tap calls the repository in order, one at a time', (tester) async {
      final repo = FakeWallRepository()..holdReactions = true;
      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(heart));
      await tester.pump(ms200);
      await tester.tap(find.byKey(heart));
      await tester.pump(ms200);
      expect(find.text('1'), findsNothing, reason: 'UI already shows the second tap');
      expect(repo.reactionStarts, ['add:heart'],
          reason: 'remove must wait for the add to finish');

      repo.reactionGates[0].complete();
      await tester.pump();
      await tester.pump();
      expect(repo.reactionStarts, ['add:heart', 'remove:heart']);
      repo.reactionGates[1].complete();
      await tester.pump();
      await tester.pump();
      expect(repo.reactionCalls, ['add:heart', 'remove:heart']);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('a failed earlier tap does not erase a newer tap', (tester) async {
      final repo = FakeWallRepository()..holdReactions = true;
      await _pump(tester, repo: repo);
      // add, remove, add: the UI ends on "mine".
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(heart));
        await tester.pump(ms200);
      }
      expect(find.text('1'), findsOneWidget);

      repo.reactionGates[0].completeError(Exception('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('1'), findsOneWidget, reason: 'newer tap still pending');
      expect(find.text("Couldn't save your reaction"), findsOneWidget);

      repo.reactionGates[1].complete();
      await tester.pump();
      await tester.pump();
      repo.reactionGates[2].complete();
      await tester.pump();
      await tester.pump();
      expect(repo.reactionCalls, ['remove:heart', 'add:heart']);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('pending clears once the stream confirms', (tester) async {
      final reactions = StreamController<List<WallReaction>>.broadcast();
      addTearDown(reactions.close);
      await _pump(tester, repo: FakeWallRepository(), reactions: reactions);
      await tester.tap(find.byKey(heart));
      await tester.pump(ms200);
      expect(find.text('1'), findsOneWidget);

      reactions.add([mine()]);
      await tester.pump();
      await tester.pump();
      expect(find.text('1'), findsOneWidget, reason: 'server count, not 2');
      expect(find.text('2'), findsNothing);

      reactions.add(const <WallReaction>[]); // un-reacted elsewhere
      await tester.pump();
      await tester.pump();
      expect(find.text('1'), findsNothing, reason: 'no stale pending entry');
    });
  });

  testWidgets('leaving mid-send does not throw when the send completes', (tester) async {
    final repo = FakeWallRepository()..commentGate = Completer<void>();
    await _pump(tester, repo: repo);
    await tester.enterText(find.widgetWithText(TextField, 'Reply…'), 'hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox()); // screen disposed mid-send
    repo.commentGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(repo.comments, ['hello']);
  });

  for (final isVideo in [false, true]) {
    testWidgets('${isVideo ? 'video' : 'photo'} detail has no "Open in" and signs the media path',
        (tester) async {
      final requested = <String>[];
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final item = WallItem(
        id: 'i1', coupleId: 'c1', addedBy: 'sp',
        source: isVideo ? WallSource.video : WallSource.photo,
        mediaPath: isVideo ? 'c1/i1/video.mp4' : 'c1/i1/media.jpg',
        mediaMime: isVideo ? 'video/mp4' : 'image/jpeg',
        isPinned: false, createdAt: DateTime.now(),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          wallItemsProvider.overrideWith((ref) => Stream.value([item])),
          wallReactionsProvider.overrideWith((ref) => Stream.value(const <WallReaction>[])),
          wallCommentsProvider.overrideWith((ref) => Stream.value(const <WallComment>[])),
          wallSelfIdProvider.overrideWithValue('me'),
          spouseProfileProvider.overrideWith((ref) async => null),
          wallRepositoryProvider.overrideWithValue(FakeWallRepository()),
          wallSignedUrlProvider.overrideWith((ref, path) {
            requested.add(path);
            // Photo: a failing URL degrades to the placeholder, not a crash.
            // Video: a good URL the (test) platform can't play.
            if (!isVideo) throw Exception('expired');
            return 'http://localhost/fake.mp4';
          }),
        ],
        child: MaterialApp(theme: LovTheme.dark(), home: const WallItemScreen(itemId: 'i1')),
      ));
      await tester.pump();
      await tester.pump();
      expect(requested, [item.mediaPath]);
      expect(find.textContaining('Open in'), findsNothing);
      expect(find.text("Can't play this video"), isVideo ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('photo detail is labelled for screen readers', (tester) async {
    final item = WallItem(
      id: 'i1', coupleId: 'c1', addedBy: 'sp', source: WallSource.photo,
      mediaPath: 'c1/i1/media.jpg', mediaMime: 'image/jpeg',
      isPinned: false, createdAt: DateTime.now(),
    );
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wallItemsProvider.overrideWith((ref) => Stream.value([item])),
        wallReactionsProvider.overrideWith((ref) => Stream.value(const <WallReaction>[])),
        wallCommentsProvider.overrideWith((ref) => Stream.value(const <WallComment>[])),
        wallSelfIdProvider.overrideWithValue('me'),
        spouseProfileProvider.overrideWith((ref) async => null),
        wallRepositoryProvider.overrideWithValue(FakeWallRepository()),
        wallSignedUrlProvider.overrideWith((ref, path) => 'http://localhost/fake'),
      ],
      child: MaterialApp(theme: LovTheme.dark(), home: const WallItemScreen(itemId: 'i1')),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Photo')), findsOneWidget);
    semantics.dispose();
  });
}
