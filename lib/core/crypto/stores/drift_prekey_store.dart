import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';

class DriftPreKeyStore implements PreKeyStore {
  DriftPreKeyStore(this._db);

  final SignalDb _db;

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final row = await (_db.select(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No prekey with id $preKeyId');
    }
    return PreKeyRecord.fromBuffer(row.record);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _db.into(_db.signalPrekeys).insertOnConflictUpdate(
          SignalPrekeysCompanion(
            prekeyId: Value(preKeyId),
            record: Value(record.serialize()),
          ),
        );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final row = await (_db.select(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await (_db.delete(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .go();
  }
}

class DriftSignedPreKeyStore implements SignedPreKeyStore {
  DriftSignedPreKeyStore(this._db);

  final SignalDb _db;

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No signed prekey with id $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(row.record);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final rows = await _db.select(_db.signalSignedPrekeys).get();
    return rows
        .map((r) => SignedPreKeyRecord.fromSerialized(r.record))
        .toList();
  }

  @override
  Future<void> storeSignedPreKey(
      int signedPreKeyId, SignedPreKeyRecord record) async {
    await _db.into(_db.signalSignedPrekeys).insertOnConflictUpdate(
          SignalSignedPrekeysCompanion(
            signedPrekeyId: Value(signedPreKeyId),
            record: Value(record.serialize()),
          ),
        );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await (_db.delete(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .go();
  }
}
