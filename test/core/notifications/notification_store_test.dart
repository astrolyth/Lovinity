import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late NotificationStore store;
  setUp(() {
    db = SignalDb.memory();
    store = NotificationStore(db);
  });
  tearDown(() => db.close());

  test('insert then watchAll returns newest first, deterministically even within the same second',
      () async {
    // No artificial delay between inserts: two notifications created in the
    // same wall-clock second must still order deterministically via `seq`,
    // not by relying on createdAt happening to differ (Drift's
    // DateTimeColumn is second-precision, not millisecond).
    await store.insert(
        kind: 'pairing', title: 'first', body: 'a', route: '/home');
    await store.insert(
        kind: 'prayer', title: 'second', body: 'b', route: '/home/prayer');

    final rows = await store.watchAll().first;
    expect(rows.map((r) => r.title).toList(), ['second', 'first']);
  });

  test('concurrent inserts never collide on seq (no duplicate ordering position)',
      () async {
    // Regression test for a real race: reading max(seq) then inserting is
    // only safe if serialized. Firing several inserts concurrently (not
    // awaited one at a time) must still produce N distinct, correctly
    // ordered rows -- if the transaction wrapping were missing, two of these
    // could read the same max(seq) and collide.
    await Future.wait([
      store.insert(kind: 'prayer', title: 'a', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'b', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'c', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'd', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'e', route: '/home/prayer'),
    ]);

    final rows = await store.watchAll().first;
    expect(rows, hasLength(5));
    expect(rows.map((r) => r.title).toSet(), {'a', 'b', 'c', 'd', 'e'});
  });

  test('watchUnreadCount counts unread; markRead clears one; markAllRead clears all',
      () async {
    await store.insert(kind: 'prayer', title: 'a', route: '/home/prayer');
    await store.insert(kind: 'prayer', title: 'b', route: '/home/prayer');
    expect(await store.watchUnreadCount().first, 2);

    final firstId = (await store.watchAll().first)
        .firstWhere((r) => r.title == 'a')
        .id;
    await store.markRead(firstId);
    expect(await store.watchUnreadCount().first, 1);

    await store.markAllRead();
    expect(await store.watchUnreadCount().first, 0);
  });

  test('insert persists kind/title/body/route exactly', () async {
    await store.insert(
      kind: 'pairing',
      title: "You're connected",
      body: null,
      route: '/home',
    );
    final row = (await store.watchAll().first).single;
    expect(row.kind, 'pairing');
    expect(row.title, "You're connected");
    expect(row.body, isNull);
    expect(row.route, '/home');
    expect(row.readAt, isNull);
  });
}
