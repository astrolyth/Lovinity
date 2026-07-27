import 'package:drift/drift.dart';

import '../storage/signal_db.dart';

/// Monotonic key-id counters, persisted in `signal_meta`.
///
/// These MUST be persisted counters, not `max(id) + 1`: consumed one-time
/// prekeys are deleted from the local store, so `max()` walks backwards and
/// would reissue an id with DIFFERENT key material. The spouse's stored bundle
/// and ours would then disagree, producing messages that fail to decrypt with
/// no error anywhere.
class KeyCounters {
  KeyCounters(this._db);

  static const _prekeyKey = 'next_prekey_id';
  static const _signedPrekeyKey = 'next_signed_prekey_id';

  final SignalDb _db;

  /// Reserves a block of [count] prekey ids and returns the FIRST one.
  Future<int> nextPrekeyId(int count) => _reserve(_prekeyKey, count);

  /// Reserves one signed-prekey id.
  Future<int> nextSignedPrekeyId() => _reserve(_signedPrekeyKey, 1);

  Future<int> _reserve(String key, int count) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.signalMeta)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      final start = row == null ? 1 : int.parse(row.value);
      await _db.into(_db.signalMeta).insertOnConflictUpdate(
            SignalMetaCompanion(
              key: Value(key),
              value: Value('${start + count}'),
            ),
          );
      return start;
    });
  }
}
