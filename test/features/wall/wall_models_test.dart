import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

void main() {
  test('WallItem.fromRow maps every column', () {
    final item = WallItem.fromRow({
      'id': 'i1',
      'couple_id': 'c1',
      'added_by': 'u1',
      'url': 'https://www.youtube.com/watch?v=abc',
      'title': 'A video',
      'description': 'desc',
      'image_url': 'https://i.ytimg.com/x.jpg',
      'source': 'youtube',
      'collection': 'deen',
      'note': 'after Fajr?',
      'is_pinned': true,
      'created_at': '2026-10-08T10:00:00+00:00',
    });
    expect(item.id, 'i1');
    expect(item.coupleId, 'c1');
    expect(item.addedBy, 'u1');
    expect(item.source, WallSource.youtube);
    expect(item.collection, WallCollection.deen);
    expect(item.isPinned, isTrue);
    expect(item.createdAt.toUtc(), DateTime.utc(2026, 10, 8, 10));
    expect(item.domain, 'youtube.com');
    expect(item.displayTitle, 'A video');
  });

  test('WallItem.fromRow infers source and tolerates nulls', () {
    final note = WallItem.fromRow({
      'id': 'i2', 'couple_id': 'c1', 'added_by': 'u1',
      'note': 'call your mum Friday', 'created_at': '2026-10-08T10:00:00Z',
    });
    expect(note.source, WallSource.note);
    expect(note.isPinned, isFalse);
    expect(note.domain, isNull);
    expect(note.displayTitle, 'call your mum Friday');

    final article = WallItem.fromRow({
      'id': 'i3', 'couple_id': 'c1', 'added_by': 'u1',
      'url': 'https://example.com/a', 'source': 'unknown-value',
      'created_at': '2026-10-08T10:00:00Z',
    });
    expect(article.source, WallSource.article);
    expect(article.displayTitle, 'example.com');
  });

  test('enum keys round-trip and unknown keys are null', () {
    for (final c in WallCollection.values) {
      expect(WallCollection.fromKey(c.key), c);
    }
    for (final s in WallSource.values) {
      expect(WallSource.fromKey(s.key), s);
    }
    for (final r in WallReactionKind.values) {
      expect(WallReactionKind.fromKey(r.key), r);
    }
    expect(WallCollection.fromKey('bogus'), isNull);
    expect(WallReactionKind.fromKey(null), isNull);
    expect(WallReactionKind.values.map((r) => r.emoji).join(), '🤍😂🔥🤲😮⭐');
  });

  test('WallReaction.tryFromRow skips unknown reaction kinds', () {
    expect(
      WallReaction.tryFromRow(
          {'item_id': 'i1', 'user_id': 'u1', 'reaction': 'heart'})?.kind,
      WallReactionKind.heart,
    );
    expect(
      WallReaction.tryFromRow(
          {'item_id': 'i1', 'user_id': 'u1', 'reaction': 'thumbs'}),
      isNull,
    );
  });

  test('WallComment.fromRow maps columns', () {
    final c = WallComment.fromRow({
      'id': 'm1', 'item_id': 'i1', 'author_id': 'u2', 'body': 'deal',
      'created_at': '2026-10-08T10:00:00Z',
    });
    expect(c.itemId, 'i1');
    expect(c.authorId, 'u2');
    expect(c.body, 'deal');
  });

  test('domainOf strips www and handles junk', () {
    expect(domainOf('https://www.nytimes.com/x'), 'nytimes.com');
    expect(domainOf('https://m.youtube.com/watch'), 'm.youtube.com');
    expect(domainOf('not a url'), isNull);
  });
}
