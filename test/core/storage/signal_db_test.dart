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
}
