// test/core/crypto/crypto_providers_test.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/core/crypto/crypto_providers.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';
import 'package:lovinity/core/crypto/signal_registration.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_session_service.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';

/// No-op stand-in for the real Supabase-backed bundle source. Real
/// [SupabasePreKeyBundleSource] needs a live [SupabaseClient], which
/// `supabaseClientProvider` only supplies once overridden at the app's
/// [ProviderScope] root (see shared/providers/supabase_provider.dart) — not
/// available in a bare unit test, so the tests below override
/// [preKeyBundleSourceProvider] directly instead of standing up a real
/// Supabase client.
class _NoopBundleSource implements PreKeyBundleSource {
  @override
  Future<List<int>> deviceNumsFor(String userId) async => const [];

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async => null;
}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

/// Wraps a mocktail [Session]/[User] pair so tests can drive
/// [authSessionProvider] to a signed-in state — same pattern as
/// test/features/location/location_controller_test.dart.
Session _signedInSession(String userId) {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn(userId);
  when(() => session.user).thenReturn(user);
  return session;
}

SignalDb _memoryDb(Ref ref) {
  final db = SignalDb.memory();
  ref.onDispose(db.close);
  return db;
}

void main() {
  test('signalDbProvider is a singleton within a container', () {
    // Overridden with an in-memory SignalDb, not the bare (default)
    // ProviderContainer the brief sketched: the real signalDbProvider opens
    // an on-disk driftDatabase() that calls path_provider over a platform
    // channel, which needs Flutter binding initialization this plain
    // `flutter_test` run doesn't have (no precedent for mocking that channel
    // anywhere in this suite — every other test uses SignalDb.memory()).
    // The identity check below still exercises the exact same provider
    // machinery; only the underlying db implementation changes.
    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith((ref) {
        final db = SignalDb.memory();
        ref.onDispose(db.close);
        return db;
      }),
    ]);
    addTearDown(c.dispose);
    final a = c.read(signalDbProvider);
    final b = c.read(signalDbProvider);
    expect(identical(a, b), isTrue);
  });

  test(
      'signalSessionServiceProvider builds when signed in and device is registered',
      () async {
    final vault = KeyVault(InMemorySecureStore());
    await vault.saveDeviceNum(1);

    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith(_memoryDb),
      preKeyBundleSourceProvider.overrideWith((ref) => _NoopBundleSource()),
      authSessionProvider
          .overrideWith((ref) => Stream.value(_signedInSession('test-user'))),
      keyVaultProvider.overrideWithValue(vault),
    ]);
    addTearDown(c.dispose);
    // Establish an explicit subscription to authSessionProvider first (same
    // as test/features/location/location_controller_test.dart) — without a
    // listener already attached, a FutureProvider that only reaches the
    // stream transitively via `ref.watch(authSessionProvider.future)` never
    // observes the first emitted value.
    c.listen(authSessionProvider, (_, _) {});
    await c.read(authSessionProvider.future);

    final service = await c.read(signalSessionServiceProvider.future);
    expect(service, isA<SignalSessionService>());
  });

  test('signalSessionServiceProvider is null when signed out', () async {
    final vault = KeyVault(InMemorySecureStore());
    await vault.saveDeviceNum(1);

    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith(_memoryDb),
      preKeyBundleSourceProvider.overrideWith((ref) => _NoopBundleSource()),
      authSessionProvider.overrideWith((ref) => Stream.value(null)),
      keyVaultProvider.overrideWithValue(vault),
    ]);
    addTearDown(c.dispose);
    c.listen(authSessionProvider, (_, _) {});
    await c.read(authSessionProvider.future);

    final service = await c.read(signalSessionServiceProvider.future);
    expect(service, isNull);
  });

  test(
      'signalSessionServiceProvider self-heals: registers the device when not yet registered',
      () async {
    // readDeviceNum() is null (device never registered — e.g. a restored
    // session that skipped the sign-in screen). The provider must run
    // ensureRegistered rather than returning null, so chat isn't stuck on
    // "setting up secure chat" forever.
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith(_memoryDb),
      preKeyBundleSourceProvider.overrideWith((ref) => _NoopBundleSource()),
      deviceRegistrarProvider.overrideWithValue(registrar),
      authSessionProvider
          .overrideWith((ref) => Stream.value(_signedInSession('test-user'))),
      keyVaultProvider.overrideWithValue(vault),
    ]);
    addTearDown(c.dispose);
    c.listen(authSessionProvider, (_, _) {});
    await c.read(authSessionProvider.future);

    final service = await c.read(signalSessionServiceProvider.future);
    expect(service, isA<SignalSessionService>());
    expect(registrar.registerCalls, 1,
        reason: 'self-heal must register the device');
    expect(await vault.readDeviceNum(), isNotNull,
        reason: 'the device number is persisted by the self-heal registration');
  });
}

/// Minimal DeviceRegistrar that lets ensureRegistered complete offline.
class _FakeRegistrar implements DeviceRegistrar {
  int registerCalls = 0;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    registerCalls++;
    return 1;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async {}

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async => 20;
}
