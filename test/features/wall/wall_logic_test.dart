import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/wall/domain/wall_logic.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

WallItem _item(String id, String by, DateTime at) => WallItem(
  id: id,
  coupleId: 'c',
  addedBy: by,
  source: WallSource.note,
  note: 'n',
  isPinned: false,
  createdAt: at,
);

void main() {
  final now = DateTime(2026, 10, 8, 12);

  test('formatWallTime buckets', () {
    expect(
      formatWallTime(now.subtract(const Duration(seconds: 20)), now: now),
      'now',
    );
    expect(
      formatWallTime(now.subtract(const Duration(minutes: 5)), now: now),
      '5m',
    );
    expect(
      formatWallTime(now.subtract(const Duration(hours: 3)), now: now),
      '3h',
    );
    expect(
      formatWallTime(now.subtract(const Duration(days: 2)), now: now),
      '2d',
    );
    expect(formatWallTime(DateTime(2026, 9, 1), now: now), '1 Sep');
  });

  test(
    'summarizeReactions counts per kind in canonical order and marks mine',
    () {
      final reactions = [
        const WallReaction(
          itemId: 'i1',
          userId: 'me',
          kind: WallReactionKind.laugh,
        ),
        const WallReaction(
          itemId: 'i1',
          userId: 'me',
          kind: WallReactionKind.heart,
        ),
        const WallReaction(
          itemId: 'i1',
          userId: 'sp',
          kind: WallReactionKind.heart,
        ),
        const WallReaction(
          itemId: 'other',
          userId: 'sp',
          kind: WallReactionKind.fire,
        ),
      ];
      expect(summarizeReactions(reactions, itemId: 'i1', selfId: 'me'), [
        const ReactionCount(kind: WallReactionKind.heart, count: 2, mine: true),
        const ReactionCount(kind: WallReactionKind.laugh, count: 1, mine: true),
      ]);
    },
  );

  test(
    'applyPendingReactions adds, removes and is a no-op when already applied',
    () {
      const server = [
        ReactionCount(kind: WallReactionKind.heart, count: 1, mine: false),
        ReactionCount(kind: WallReactionKind.fire, count: 1, mine: true),
      ];
      expect(
        applyPendingReactions(server, {
          WallReactionKind.heart: true, // add mine
          WallReactionKind.fire: false, // remove mine -> disappears
          WallReactionKind.star: true, // brand new
        }),
        const [
          ReactionCount(kind: WallReactionKind.heart, count: 2, mine: true),
          ReactionCount(kind: WallReactionKind.star, count: 1, mine: true),
        ],
      );
      // Pending that the server already reflects changes nothing.
      expect(
        applyPendingReactions(server, {WallReactionKind.fire: true}),
        server,
      );
      expect(applyPendingReactions(server, const {}), server);
    },
  );

  test(
    'unseenItemIds: spouse items after last visit; all spouse items if never visited',
    () {
      final items = [
        _item('old', 'sp', DateTime(2026, 10, 1)),
        _item('new', 'sp', DateTime(2026, 10, 7)),
        _item('mine', 'me', DateTime(2026, 10, 7)),
      ];
      expect(
        unseenItemIds(items, selfId: 'me', lastVisit: DateTime(2026, 10, 5)),
        {'new'},
      );
      expect(unseenItemIds(items, selfId: 'me', lastVisit: null), {
        'old',
        'new',
      });
      expect(unseenItemIds(items, selfId: null, lastVisit: null), isEmpty);
    },
  );

  test('itemsThisWeek counts the last 7 days', () {
    final items = [
      _item('a', 'me', now.subtract(const Duration(days: 1))),
      _item('b', 'sp', now.subtract(const Duration(days: 6, hours: 23))),
      _item('c', 'sp', now.subtract(const Duration(days: 8))),
    ];
    expect(itemsThisWeek(items, now: now), 2);
  });
}
