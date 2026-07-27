// test/core/crypto/stores/drift_session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:lovinity/core/crypto/stores/drift_session_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late DriftSessionStore store;

  setUp(() {
    db = SignalDb.memory();
    store = DriftSessionStore(db);
  });
  tearDown(() => db.close());

  test('loadSession returns a fresh record for an unknown address', () async {
    final rec = await store.loadSession(SignalProtocolAddress('bob', 1));
    expect(rec, isA<SessionRecord>());
    expect(await store.containsSession(SignalProtocolAddress('bob', 1)), isFalse);
  });

  test('stored session round-trips and is reported as present', () async {
    final addr = SignalProtocolAddress('bob', 1);
    final record = SessionRecord();
    await store.storeSession(addr, record);

    expect(await store.containsSession(addr), isTrue);
    final loaded = await store.loadSession(addr);
    expect(loaded.serialize(), record.serialize());
  });

  test('getSubDeviceSessions lists other devices, excluding device 1', () async {
    await store.storeSession(SignalProtocolAddress('bob', 1), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 2), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 3), SessionRecord());

    final subs = await store.getSubDeviceSessions('bob');
    expect(subs..sort(), [2, 3]);
  });

  test('deleteSession and deleteAllSessions remove rows', () async {
    await store.storeSession(SignalProtocolAddress('bob', 1), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 2), SessionRecord());

    await store.deleteSession(SignalProtocolAddress('bob', 1));
    expect(await store.containsSession(SignalProtocolAddress('bob', 1)), isFalse);

    await store.deleteAllSessions('bob');
    expect(await store.containsSession(SignalProtocolAddress('bob', 2)), isFalse);
  });
}
