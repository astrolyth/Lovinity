import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/secure_store.dart';

/// Keeps the Supabase session (access + refresh token) in the OS
/// keychain/keystore instead of supabase_flutter's default SharedPreferences,
/// which is a plaintext file on disk.
///
/// [legacy] is the old SharedPreferences store: a session found there is
/// moved here once and wiped, so upgrading doesn't sign anyone out.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this._store, {required this.key, this.legacy});

  final SecureStore _store;
  final String key;
  final LocalStorage? legacy;

  @override
  Future<void> initialize() async {
    final old = legacy;
    if (old == null) return;
    await old.initialize();
    final session = await old.accessToken();
    if (session == null) return;
    if (await _read() == null) await _store.write(key, session);
    await old.removePersistedSession();
  }

  // A keychain read that fails or times out (see secureStoreTimeout) means
  // "signed out", not a crashed boot.
  Future<String?> _read() async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasAccessToken() async => await _read() != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> removePersistedSession() => _store.delete(key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(key, persistSessionString);
}
