import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value secret storage. Exists so KeyVault can be constructed with
/// an isolated fake per simulated device in tests — FlutterSecureStorage's mock
/// is a single global map and would let devices clobber each other.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// How long a single platform-channel call to the OS keychain/keystore may
/// take before [FlutterSecureStore] gives up and throws.
///
/// WHY THIS EXISTS: on macOS, a Keychain item created under one code
/// signature (e.g. a prior ad-hoc-signed debug build — `flutter run -d
/// macos` defaults to `CODE_SIGN_IDENTITY = "-"`, which re-derives on every
/// rebuild) becomes access-controlled against that signature. A later build
/// with a different signature reading/writing the same item makes macOS
/// show a native "<app> wants to use your confidential information stored
/// in Keychain" authorization prompt via SecurityAgent — which can render
/// off-screen or behind the app window. Without a timeout, the underlying
/// `SecItem*` call just blocks forever waiting on that prompt, so
/// `ensureRegistered`/`guardAccountSwitch` never resolve OR throw and the
/// chat screen spins on "setting up secure chat" indefinitely with no error
/// and nothing in the console. Timing out turns that silent hang into a
/// thrown exception, which `signalSessionServiceProvider` (a FutureProvider)
/// already surfaces as an error the chat screen displays and lets the user
/// retry from.
const secureStoreTimeout = Duration(seconds: 10);

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore(this._storage, {@visibleForTesting Duration? timeout})
      : _timeout = timeout ?? secureStoreTimeout;

  final FlutterSecureStorage _storage;
  final Duration _timeout;

  @override
  Future<String?> read(String key) => _storage.read(key: key).timeout(_timeout);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value).timeout(_timeout);

  @override
  Future<void> delete(String key) => _storage.delete(key: key).timeout(_timeout);

  @override
  Future<void> deleteAll() => _storage.deleteAll().timeout(_timeout);
}

/// Test double with per-instance state.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}
