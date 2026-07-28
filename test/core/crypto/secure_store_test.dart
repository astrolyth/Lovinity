import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';

/// Simulates a native Keychain call that never returns -- e.g. macOS
/// blocking on an off-screen SecurityAgent authorization prompt (see the
/// [secureStoreTimeout] doc comment). Every method returns a Future that
/// never completes, so the only way [FlutterSecureStore] can return is via
/// its `.timeout(...)` wrapping.
class _HangingStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Completer<String?>().future;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Completer<void>().future;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Completer<void>().future;

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test');
}

void main() {
  const shortTimeout = Duration(milliseconds: 20);

  test('read throws instead of hanging forever when the platform call never completes', () async {
    final store = FlutterSecureStore(_HangingStorage(), timeout: shortTimeout);

    await expectLater(
      store.read('signal.identity.priv'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('write throws instead of hanging forever when the platform call never completes', () async {
    final store = FlutterSecureStore(_HangingStorage(), timeout: shortTimeout);

    await expectLater(
      store.write('signal.identity.priv', 'value'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
