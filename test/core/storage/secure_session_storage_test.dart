import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/storage/secure_session_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MapLocalStorage extends LocalStorage {
  String? value;
  _MapLocalStorage([this.value]);
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<void> removePersistedSession() async => value = null;
  @override
  Future<void> persistSession(String s) async => value = s;
}

class _ThrowingStore extends InMemorySecureStore {
  @override
  Future<String?> read(String key) => throw Exception('keychain locked');
}

void main() {
  const key = 'sb-test-auth-token';

  test('persists, reads and removes the session in the secure store', () async {
    final store = InMemorySecureStore();
    final s = SecureSessionStorage(store, key: key);
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);

    await s.persistSession('{"access_token":"a"}');
    expect(await store.read(key), '{"access_token":"a"}');
    expect(await s.accessToken(), '{"access_token":"a"}');

    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });

  test('moves a legacy SharedPreferences session and wipes the old copy', () async {
    final store = InMemorySecureStore();
    final legacy = _MapLocalStorage('{"access_token":"old"}');
    await SecureSessionStorage(store, key: key, legacy: legacy).initialize();

    expect(await store.read(key), '{"access_token":"old"}');
    expect(legacy.value, isNull);
  });

  test('a newer secure session wins over a stale legacy one', () async {
    final store = InMemorySecureStore();
    await store.write(key, 'new');
    final legacy = _MapLocalStorage('old');
    await SecureSessionStorage(store, key: key, legacy: legacy).initialize();

    expect(await store.read(key), 'new');
    expect(legacy.value, isNull);
  });

  test('a failing keychain read reads as signed out', () async {
    final s = SecureSessionStorage(_ThrowingStore(), key: key);
    expect(await s.hasAccessToken(), isFalse);
    expect(await s.accessToken(), isNull);
  });
}
