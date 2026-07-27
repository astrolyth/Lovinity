// lib/core/crypto/stores/drift_signal_store.dart
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';
import '../key_vault.dart';
import 'drift_identity_store.dart';
import 'drift_prekey_store.dart';
import 'drift_session_store.dart';

/// The composite libsignal expects (`SessionCipher.fromStore` /
/// `SessionBuilder.fromSignalStore`). Pure delegation — each concern stays in
/// its own store so it can be tested in isolation.
class DriftSignalStore implements SignalProtocolStore {
  DriftSignalStore(SignalDb db, KeyVault vault)
      : _sessions = DriftSessionStore(db),
        _prekeys = DriftPreKeyStore(db),
        _signedPrekeys = DriftSignedPreKeyStore(db),
        _identities = DriftIdentityStore(db, vault);

  final DriftSessionStore _sessions;
  final DriftPreKeyStore _prekeys;
  final DriftSignedPreKeyStore _signedPrekeys;
  final DriftIdentityStore _identities;

  // --- IdentityKeyStore
  @override
  Future<IdentityKeyPair> getIdentityKeyPair() => _identities.getIdentityKeyPair();
  @override
  Future<int> getLocalRegistrationId() => _identities.getLocalRegistrationId();
  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) =>
      _identities.getIdentity(address);
  @override
  Future<bool> saveIdentity(
          SignalProtocolAddress address, IdentityKey? identityKey) =>
      _identities.saveIdentity(address, identityKey);
  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
          IdentityKey? identityKey, Direction direction) =>
      _identities.isTrustedIdentity(address, identityKey, direction);

  // --- SessionStore
  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) =>
      _sessions.loadSession(address);
  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _sessions.getSubDeviceSessions(name);
  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) =>
      _sessions.storeSession(address, record);
  @override
  Future<bool> containsSession(SignalProtocolAddress address) =>
      _sessions.containsSession(address);
  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _sessions.deleteSession(address);
  @override
  Future<void> deleteAllSessions(String name) => _sessions.deleteAllSessions(name);

  // --- PreKeyStore
  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) => _prekeys.loadPreKey(preKeyId);
  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _prekeys.storePreKey(preKeyId, record);
  @override
  Future<bool> containsPreKey(int preKeyId) => _prekeys.containsPreKey(preKeyId);
  @override
  Future<void> removePreKey(int preKeyId) => _prekeys.removePreKey(preKeyId);

  // --- SignedPreKeyStore
  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int id) =>
      _signedPrekeys.loadSignedPreKey(id);
  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() =>
      _signedPrekeys.loadSignedPreKeys();
  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) =>
      _signedPrekeys.storeSignedPreKey(id, record);
  @override
  Future<bool> containsSignedPreKey(int id) =>
      _signedPrekeys.containsSignedPreKey(id);
  @override
  Future<void> removeSignedPreKey(int id) => _signedPrekeys.removeSignedPreKey(id);
}
