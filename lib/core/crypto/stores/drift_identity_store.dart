// lib/core/crypto/stores/drift_identity_store.dart
import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';
import '../key_vault.dart';

/// IdentityKeyStore backed by Drift, with the local identity pair read from the
/// Keychain.
///
/// Trust policy: trust-on-first-use, and accept a changed identity but record it
/// so chat can surface "their security code changed". A changed key is far more
/// often a reinstall than an attack; blocking would break the common case.
class DriftIdentityStore implements IdentityKeyStore {
  DriftIdentityStore(this._db, this._vault);

  final SignalDb _db;
  final KeyVault _vault;

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final serialized = await _vault.readIdentity();
    if (serialized == null) {
      throw StateError('No local Signal identity — call ensureRegistered first');
    }
    return IdentityKeyPair.fromSerialized(serialized);
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final id = await _vault.readRegistrationId();
    if (id == null) {
      throw StateError('No local registration id — call ensureRegistered first');
    }
    return id;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final row = await (_db.select(_db.signalIdentities)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .getSingleOrNull();
    if (row == null) return null;
    return IdentityKey.fromBytes(row.identityKey, 0);
  }

  /// Returns true when this REPLACED a different existing key (libsignal's
  /// contract), and records a change event in that case.
  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;

    final existing = await getIdentity(address);
    final changed =
        existing != null && !_sameKey(existing, identityKey);

    await _db.into(_db.signalIdentities).insertOnConflictUpdate(
          SignalIdentitiesCompanion.insert(
            name: address.getName(),
            deviceNum: address.getDeviceId(),
            identityKey: identityKey.serialize(),
          ),
        );

    if (changed) {
      await _db.into(_db.signalIdentityChanges).insert(
            SignalIdentityChangesCompanion.insert(
              name: address.getName(),
              deviceNum: address.getDeviceId(),
            ),
          );
    }
    return changed;
  }

  /// Accept-but-warn: never block. The change is recorded in [saveIdentity].
  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
          IdentityKey? identityKey, Direction direction) async =>
      true;

  bool _sameKey(IdentityKey a, IdentityKey b) {
    final x = a.serialize();
    final y = b.serialize();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
