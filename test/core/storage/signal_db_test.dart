import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  test('stores and reads a session row', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);

    await db.into(db.signalSessions).insert(SignalSessionsCompanion.insert(
          name: 'user-a',
          deviceNum: 1,
          record: Uint8List.fromList([1, 2, 3]),
        ));

    final rows = await db.select(db.signalSessions).get();
    expect(rows.single.name, 'user-a');
    expect(rows.single.deviceNum, 1);
    expect(rows.single.record, [1, 2, 3]);
  });

  test('wipeAll clears appNotifications along with chat/signal tables', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);

    await db.into(db.appNotifications).insert(
          AppNotificationsCompanion.insert(
            id: 'n1',
            kind: 'pairing',
            title: "You're connected",
            route: '/home',
            createdAt: DateTime(2026),
          ),
        );
    expect(await db.select(db.appNotifications).get(), hasLength(1));

    await db.wipeAll();

    expect(await db.select(db.appNotifications).get(), isEmpty);
  });
}
