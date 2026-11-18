import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/moments/domain/moment.dart';

Moment _m(String id, String sender, DateTime at, {bool seen = false}) => Moment(
  id: id,
  coupleId: 'c',
  senderId: sender,
  mediaPath: 'c/$id/media.jpg',
  mediaMime: 'image/jpeg',
  createdAt: at,
  viewedAt: seen ? at : null,
);

void main() {
  test('fromRow parses a video row and picks the thumbnail as preview', () {
    final m = Moment.fromRow({
      'id': '1',
      'couple_id': 'c',
      'sender_id': 'u',
      'media_path': 'c/1/media.mp4',
      'media_mime': 'video/mp4',
      'thumb_path': 'c/1/thumb.jpg',
      'caption': 'hi',
      'viewed_at': null,
      'created_at': '2026-11-18T12:00:00Z',
    });
    expect(m.isVideo, isTrue);
    expect(m.previewPath, 'c/1/thumb.jpg');
    expect(m.viewedAt, isNull);
    expect(m.createdAt.isUtc, isFalse);
  });

  test('groupByDay keeps newest-first order and splits on local day', () {
    final list = [
      _m('a', 'u', DateTime(2026, 11, 18, 15)),
      _m('b', 'u', DateTime(2026, 11, 18, 9)),
      _m('c', 'u', DateTime(2026, 11, 17, 22)),
    ];
    final g = groupByDay(list);
    expect(g.map((e) => e.$1), [
      DateTime(2026, 11, 18),
      DateTime(2026, 11, 17),
    ]);
    expect(g.first.$2.map((m) => m.id), ['a', 'b']);
    expect(g.last.$2.map((m) => m.id), ['c']);
  });

  group('partnerStoryStart', () {
    test('opens the oldest unseen partner moment', () {
      final list = [
        _m('new', 'p', DateTime(2026, 11, 18, 15)),
        _m('mine', 'me', DateTime(2026, 11, 18, 14)),
        _m('older', 'p', DateTime(2026, 11, 18, 12)),
        _m('seen', 'p', DateTime(2026, 11, 18, 9), seen: true),
      ];
      expect(partnerStoryStart(list, 'me')?.id, 'older');
    });

    test('falls back to the newest partner moment when all are seen', () {
      final list = [
        _m('mine', 'me', DateTime(2026, 11, 18, 16)),
        _m('a', 'p', DateTime(2026, 11, 18, 15), seen: true),
        _m('b', 'p', DateTime(2026, 11, 18, 12), seen: true),
      ];
      expect(partnerStoryStart(list, 'me')?.id, 'a');
    });

    test('is null when the partner has none', () {
      expect(partnerStoryStart([_m('x', 'me', DateTime(2026))], 'me'), isNull);
    });
  });

  test('vlogDay closes the day at 4am local', () {
    expect(vlogDay(DateTime(2026, 11, 18, 3, 59)), DateTime(2026, 11, 17));
    expect(vlogDay(DateTime(2026, 11, 18, 4)), DateTime(2026, 11, 18));
    // A 1am moment groups with the evening before it.
    final g = groupByDay([
      _m('late', 'u', DateTime(2026, 11, 18, 1)),
      _m('eve', 'u', DateTime(2026, 11, 17, 21)),
    ]);
    expect(g.single.$1, DateTime(2026, 11, 17));
  });

  test('vlogSlots pairs each hour oldest-first without dropping extras', () {
    final slots = vlogSlots([
      _m('p3', 'p', DateTime(2026, 11, 18, 15, 40)),
      _m('me3', 'me', DateTime(2026, 11, 18, 15, 10)),
      _m('p3b', 'p', DateTime(2026, 11, 18, 15, 50)),
      _m('me9', 'me', DateTime(2026, 11, 18, 9, 5)),
    ], 'me');
    expect(slots.map((s) => (s.hour.hour, s.partner?.id, s.mine?.id)), [
      (9, null, 'me9'),
      (15, 'p3', 'me3'),
      (15, 'p3b', null),
    ]);
  });

  test('MomentReply.fromRow reads an emoji reaction', () {
    final r = MomentReply.fromRow({
      'id': 'r',
      'moment_id': 'm',
      'author_id': 'u',
      'emoji': '❤️',
      'body': null,
      'created_at': '2026-11-18T12:00:00Z',
    });
    expect(r.emoji, '❤️');
    expect(r.body, isNull);
  });
}
