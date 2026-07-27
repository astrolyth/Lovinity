// lib/core/crypto/stores/drift_session_store.dart
import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';

/// SessionStore backed by Drift. Holds the Double Ratchet state, so every write
/// must land before the next message is processed — hence no caching here.
class DriftSessionStore implements SessionStore {
  DriftSessionStore(this._db);

  final SignalDb _db;

  Future<SignalSession?> _row(SignalProtocolAddress address) {
    return (_db.select(_db.signalSessions)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .getSingleOrNull();
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final row = await _row(address);
    // libsignal expects a fresh record (not an error) for an unknown address.
    if (row == null) return SessionRecord();
    return SessionRecord.fromSerialized(row.record);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = await (_db.select(_db.signalSessions)
          ..where((t) => t.name.equals(name) & t.deviceNum.equals(1).not()))
        .get();
    return rows.map((r) => r.deviceNum).toList();
  }

  @override
  Future<void> storeSession(
      SignalProtocolAddress address, SessionRecord record) async {
    await _db.into(_db.signalSessions).insertOnConflictUpdate(
          SignalSessionsCompanion.insert(
            name: address.getName(),
            deviceNum: address.getDeviceId(),
            record: record.serialize(),
          ),
        );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _row(address) != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await (_db.delete(_db.signalSessions)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .go();
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await (_db.delete(_db.signalSessions)..where((t) => t.name.equals(name)))
        .go();
  }
}
