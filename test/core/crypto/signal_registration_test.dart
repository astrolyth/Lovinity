import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_keys.dart';
import 'package:lovinity/core/crypto/signal_registration.dart';
import 'package:lovinity/core/crypto/stores/drift_signal_store.dart';
import 'package:lovinity/core/storage/media_cache.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';

/// No-op MediaCache that records whether [clear] ran, so the account-switch
/// tests can prove the decrypted-media wipe is actually wired up. Mirrors
/// `_FakeMediaCache` in test/features/chat/chat_service_test.dart (test files
/// can't import each other's private classes, so it's redefined here).
class _FakeMediaCache implements MediaCache {
  final Map<String, Uint8List> written = {};
  bool cleared = false;

  @override
  Future<String> write(String key, Uint8List bytes) async {
    written[key] = bytes;
    return 'fake-cache/$key';
  }

  @override
  Future<void> clear() async {
    cleared = true;
    written.clear();
  }
}

class _FakeRegistrar implements DeviceRegistrar {
  int? registeredDeviceNum;
  Map<int, Uint8List> uploaded = {};
  int remaining = 0;

  /// When true, [uploadOneTimePrekeys] throws instead of succeeding, to
  /// simulate a network drop after [register] already returned a device_num.
  bool failUpload = false;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    registeredDeviceNum = 1;
    return 1;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async {
    if (failUpload) {
      throw Exception('simulated network drop');
    }
    uploaded.addAll(prekeys);
  }

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async => remaining;
}

void main() {
  test('ensureRegistered generates, registers and persists the device number',
      () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    final deviceNum =
        await ensureRegistered(db: db, vault: vault, registrar: registrar);

    expect(deviceNum, 1);
    expect(await vault.readDeviceNum(), 1);
    expect(await vault.hasIdentity(), isTrue);
    expect(await vault.readRegistrationId(), isNotNull);
    expect(registrar.uploaded, isNotEmpty);
  });

  test(
      'ensureRegistered seeds the local prekey stores so incoming prekey '
      'messages can resolve', () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);

    // Read straight from the Drift store — the same path SessionCipher uses
    // during decrypt — rather than the KeyVault, since the whole point of
    // this fix is that the two must not diverge.
    final store = DriftSignalStore(db, vault);
    expect(await store.containsSignedPreKey(1), isTrue,
        reason: 'the signed prekey must be readable from the store SignalDb '
            'decrypt reads from, not just the KeyVault');
    for (final id in registrar.uploaded.keys) {
      expect(await store.containsPreKey(id), isTrue,
          reason: 'every uploaded one-time prekey id must also be present '
              'in the local store');
    }
  });

  test('ensureRegistered is idempotent — a second call keeps the identity',
      () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final firstIdentity = await vault.readIdentity();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);

    expect(await vault.readIdentity(), firstIdentity,
        reason: 'regenerating the identity would break every session');
  });

  test(
      'resumes without regenerating the identity when device_num was never persisted',
      () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());

    // Seed the exact partial state: savePrivate + saveDeviceId succeeded
    // (as ensureRegistered does before the network round-trip), but
    // saveDeviceNum never ran — simulating the app dying or the network
    // dropping between the two.
    final seed = generateBundle(deviceId: 'd');
    await vault.savePrivate(seed.private);
    await vault.saveDeviceId('d');

    final before = await vault.readIdentity();
    final registrationIdBefore = await vault.readRegistrationId();
    expect(await vault.readDeviceNum(), isNull);

    final deviceNum = await ensureRegistered(
        db: db, vault: vault, registrar: _FakeRegistrar());

    expect(await vault.readIdentity(), before,
        reason:
            'resuming a partial registration must preserve the existing identity');
    expect(await vault.readRegistrationId(), registrationIdBefore);
    expect(await vault.readDeviceNum(), deviceNum);
    expect(await vault.readDeviceNum(), isNotNull);
  });

  test(
      'a failed one-time prekey upload does not persist device_num, so the '
      'next call retries instead of leaving the server starved forever',
      () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final failing = _FakeRegistrar()..failUpload = true;

    await expectLater(
      ensureRegistered(db: db, vault: vault, registrar: failing),
      throwsException,
    );

    // The upload never completed, so device_num must NOT have been saved —
    // otherwise the `hasIdentity && existingNum != null` short-circuit would
    // permanently skip retrying the upload.
    expect(await vault.readDeviceNum(), isNull,
        reason: 'a failed upload must leave the retry guard open');
    expect(failing.uploaded, isEmpty);

    // Retry with a healthy registrar: it must actually retry the upload,
    // not short-circuit, and must succeed this time.
    final healthy = _FakeRegistrar();
    final deviceNum =
        await ensureRegistered(db: db, vault: vault, registrar: healthy);

    expect(deviceNum, 1);
    expect(await vault.readDeviceNum(), 1);
    expect(healthy.uploaded, isNotEmpty);
  });

  test('re-registration rotates ids forward and RETAINS the old signed prekey',
      () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final firstSpkIds = await _signedPrekeyIds(db);
    final firstPrekeyIds = registrar.uploaded.keys.toList()..sort();

    // Force the resume path: identity kept, device number cleared.
    await vault.clearDeviceNum();
    registrar.uploaded.clear();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);

    final secondSpkIds = await _signedPrekeyIds(db);
    final secondPrekeyIds = registrar.uploaded.keys.toList()..sort();

    expect(secondSpkIds.length, greaterThan(firstSpkIds.length),
        reason: 'the previous signed prekey must be RETAINED, not overwritten '
            '- an in-flight message naming the old id must still decrypt');
    expect(secondPrekeyIds.first, greaterThan(firstPrekeyIds.last),
        reason: 'prekey ids must never be reissued with different key material');
  });

  test('replenish tops up to topUpTo using fresh, never-reused ids', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final initialIds = registrar.uploaded.keys.toList()..sort();
    registrar.uploaded.clear();
    registrar.remaining = 3; // server says only 3 unconsumed left

    await replenishPrekeysIfLow(
        db: db, vault: vault, registrar: registrar, threshold: 10, topUpTo: 20);

    final topUpIds = registrar.uploaded.keys.toList()..sort();
    expect(topUpIds.length, 17, reason: 'tops up 3 -> 20');
    expect(topUpIds.first, greaterThan(initialIds.last),
        reason: 'must never reissue an id that was already published');
  });

  test(
      'ensureRegistered replenishes prekeys on the already-registered '
      'restart path (app start), not just on fresh registration', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final initialIds = registrar.uploaded.keys.toList()..sort();

    // Simulate the server pool having drained since registration, and
    // clear the upload record so we can tell whether THIS call uploads.
    registrar.remaining = 3;
    registrar.uploaded.clear();

    // Device is already fully registered, so this hits the
    // `hasIdentity && existingNum != null` short-circuit.
    final deviceNum =
        await ensureRegistered(db: db, vault: vault, registrar: registrar);

    expect(deviceNum, await vault.readDeviceNum());
    expect(registrar.uploaded, isNotEmpty,
        reason: 'app start of an already-registered device must top up a '
            'low prekey pool, not just return early and skip replenish');
    final topUpIds = registrar.uploaded.keys.toList()..sort();
    expect(topUpIds.first, greaterThan(initialIds.last),
        reason: 'the restart-path top-up must never reissue an id already '
            'published');
  });

  test('replenish does nothing when above threshold', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    registrar.uploaded.clear();
    registrar.remaining = 15;

    await replenishPrekeysIfLow(
        db: db, vault: vault, registrar: registrar, threshold: 10, topUpTo: 20);

    expect(registrar.uploaded, isEmpty);
  });

  test('guardAccountSwitch WIPES when a different user signs in', () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final store = ChatStore(db);
    final cache = _FakeMediaCache();
    // Account A owns the device, has chat history, and has decrypted media
    // sitting in the local attachment cache.
    await guardAccountSwitch(
        db: db, vault: vault, cache: cache, selfUserId: 'user-A');
    await store.upsertMessage(id: 'old', senderId: 'A-spouse', body: 'secret',
        createdAt: DateTime(2026), status: 'delivered');
    await vault.savePrivate(
        generateBundle(deviceId: 'd', oneTimePrekeyCount: 1).private);
    await cache.write('old', Uint8List.fromList([1, 2, 3]));

    // A DIFFERENT user signs in on the same device.
    await guardAccountSwitch(
        db: db, vault: vault, cache: cache, selfUserId: 'user-B');

    expect(await store.watchConversation().first, isEmpty,
        reason: 'a different account must not see the previous user\'s chat');
    expect(await vault.hasIdentity(), isFalse,
        reason: 'the previous identity must be wiped too');
    expect(cache.cleared, isTrue,
        reason: 'the previous user\'s DECRYPTED photos/videos must be deleted '
            'too, not left readable on a shared device');
    expect(cache.written, isEmpty);
    expect(await db.readOwnerUserId(), 'user-B');
  });

  test('guardAccountSwitch PRESERVES history when the same user re-logs in',
      () async {
    final db = SignalDb.memory();
    final vault = KeyVault(InMemorySecureStore());
    final store = ChatStore(db);
    final cache = _FakeMediaCache();
    await guardAccountSwitch(
        db: db, vault: vault, cache: cache, selfUserId: 'user-A');
    await store.upsertMessage(id: 'mine', senderId: 'A-spouse', body: 'hi',
        createdAt: DateTime(2026), status: 'delivered');
    await vault.savePrivate(
        generateBundle(deviceId: 'd', oneTimePrekeyCount: 1).private);
    await cache.write('mine', Uint8List.fromList([1, 2, 3]));

    // Same user signs out and back in — sign-out no longer wipes anything.
    await guardAccountSwitch(
        db: db, vault: vault, cache: cache, selfUserId: 'user-A');

    expect((await store.watchConversation().first).length, 1,
        reason: 'the same user keeps their chat history across re-login');
    expect(await vault.hasIdentity(), isTrue,
        reason: 'the same user keeps their identity/device');
    expect(cache.cleared, isFalse,
        reason: 'the same user keeps their own cached media');
    expect(cache.written, isNotEmpty);
  });
}

Future<List<int>> _signedPrekeyIds(SignalDb db) async {
  final rows = await db.select(db.signalSignedPrekeys).get();
  return rows.map((r) => r.signedPrekeyId).toList()..sort();
}
