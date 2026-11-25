import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/features/wall/presentation/wall_item_card.dart';
import 'package:lovinity/features/wall/presentation/wall_reaction_bar.dart';
import 'package:lovinity/features/wall/presentation/wall_visuals.dart';

WallItem _link({
  String title = 'A video',
  String? note = 'after Fajr?',
  bool pinned = false,
}) => WallItem(
  id: 'i1',
  coupleId: 'c',
  addedBy: 'sp',
  url: 'https://youtu.be/abc',
  title: title,
  source: WallSource.youtube,
  note: note,
  isPinned: pinned,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
);

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? LovTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'card shows title, domain, note, sharer, reactions and comments',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _host(
          WallItemCard(
            item: _link(),
            sharerName: 'Aisha',
            reactions: const [
              ReactionCount(kind: WallReactionKind.heart, count: 2, mine: true),
            ],
            commentCount: 3,
            isUnseen: true,
            onOpen: () => opened = true,
            onOpenLink: () {},
          ),
        ),
      );
      expect(find.text('A video'), findsOneWidget);
      expect(find.text('youtu.be'), findsOneWidget);
      expect(find.text('after Fajr?'), findsOneWidget);
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.textContaining('shared from YouTube · 2h'), findsOneWidget);
      expect(find.text('🤍 2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // comment count
      expect(find.byKey(const Key('wall-unseen-dot')), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget); // source pill
      await tester.tap(find.text('after Fajr?'));
      expect(opened, isTrue);
    },
  );

  testWidgets('note-only card has no preview area', (tester) async {
    await tester.pumpWidget(
      _host(
        WallItemCard(
          item: WallItem(
            id: 'n',
            coupleId: 'c',
            addedBy: 'me',
            source: WallSource.note,
            note: 'call your mum Friday',
            isPinned: false,
            createdAt: DateTime.now(),
          ),
          sharerName: 'You',
          reactions: const [],
          commentCount: 0,
          isUnseen: false,
          onOpen: () {},
        ),
      ),
    );
    expect(find.byType(WallThumbnail), findsNothing);
    expect(find.text('call your mum Friday'), findsOneWidget);
    expect(find.byKey(const Key('wall-unseen-dot')), findsNothing);
  });

  testWidgets('long content does not overflow at 320px', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.all(16),
          child: WallItemCard(
            item: _link(title: 'T' * 300, note: 'N ' * 500),
            sharerName: 'A very long display name that keeps going and going',
            reactions: const [
              ReactionCount(
                kind: WallReactionKind.heart,
                count: 12,
                mine: true,
              ),
              ReactionCount(
                kind: WallReactionKind.laugh,
                count: 10,
                mine: false,
              ),
              ReactionCount(
                kind: WallReactionKind.fire,
                count: 99,
                mine: false,
              ),
              ReactionCount(kind: WallReactionKind.star, count: 5, mine: false),
            ],
            commentCount: 120,
            isUnseen: true,
            onOpen: () {},
            onOpenLink: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('works in light theme too', (tester) async {
    await tester.pumpWidget(
      _host(
        WallItemCard(
          item: _link(),
          sharerName: 'Aisha',
          reactions: const [],
          commentCount: 0,
          isUnseen: false,
          onOpen: () {},
          onOpenLink: () {},
        ),
        theme: LovTheme.light(),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reaction bar shows all six and reports taps', (tester) async {
    final toggled = <WallReactionKind>[];
    await tester.pumpWidget(
      _host(
        WallReactionBar(
          summary: const [
            ReactionCount(kind: WallReactionKind.dua, count: 1, mine: true),
          ],
          onToggle: toggled.add,
        ),
      ),
    );
    for (final k in WallReactionKind.values) {
      expect(find.byKey(Key('reaction-${k.key}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('reaction-fire')));
    await tester.pump(const Duration(milliseconds: 200)); // bounce timer
    expect(toggled, [WallReactionKind.fire]);
    expect(find.text('1'), findsOneWidget); // dua count
  });

  group('media items', () {
    WallItem media(WallSource source, String path) => WallItem(
      id: 'm1',
      coupleId: 'c',
      addedBy: 'sp',
      source: source,
      mediaPath: path,
      mediaMime: source == WallSource.video ? 'video/mp4' : 'image/jpeg',
      isPinned: false,
      createdAt: DateTime.now(),
    );

    Future<List<String>> pumpCard(
      WidgetTester tester,
      WallItem item,
      VoidCallback onOpen,
      VoidCallback onOpenLink,
    ) async {
      final requested = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wallSignedUrlProvider.overrideWith((ref, path) {
              requested.add(path);
              return 'http://localhost/fake';
            }),
          ],
          child: _host(
            WallItemCard(
              item: item,
              sharerName: 'Aisha',
              reactions: const [],
              commentCount: 0,
              isUnseen: false,
              onOpen: onOpen,
              onOpenLink: onOpenLink,
            ),
          ),
        ),
      );
      await tester.pump();
      return requested;
    }

    testWidgets('video card shows pill, play glyph and requests the poster', (
      tester,
    ) async {
      var opened = 0, linked = 0;
      final requested = await pumpCard(
        tester,
        media(WallSource.video, 'c/m1/video.mp4'),
        () => opened++,
        () => linked++,
      );
      expect(requested, ['c/m1/thumb.jpg']);
      expect(find.text('Video'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byType(WallThumbnail));
      // The preview also takes a double-tap (heart), so a tap lands after it.
      await tester.pump(kDoubleTapTimeout);
      expect([opened, linked], [1, 0]);
    });

    testWidgets('photo card requests the photo itself', (tester) async {
      final requested = await pumpCard(
        tester,
        media(WallSource.photo, 'c/m1/media.jpg'),
        () {},
        () {},
      );
      expect(requested, ['c/m1/media.jpg']);
      expect(find.text('Photo'), findsOneWidget);
    });
  });
}
