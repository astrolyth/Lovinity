import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as sig;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../storage/signal_db.dart';
import 'key_counters.dart';
import 'key_vault.dart';
import 'signal_keys.dart';
import 'stores/drift_signal_store.dart';

abstract class DeviceRegistrar {
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  });

  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  });

  Future<int> unconsumedPrekeyCount(int deviceNum);
}

class SupabaseDeviceRegistrar implements DeviceRegistrar {
  SupabaseDeviceRegistrar(this._client);

  final SupabaseClient _client;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    final res = await _client.rpc('register_device_bundle', params: {
      'p_device_id': deviceId,
      'p_registration_id': registrationId,
      'p_identity_pub': _hex(identityPub),
      'p_signed_prekey_id': signedPrekeyId,
      'p_signed_prekey_pub': _hex(signedPrekeyPub),
      'p_signed_prekey_sig': _hex(signedPrekeySig),
    });
    return res as int;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('signal_one_time_prekeys').upsert([
      for (final e in prekeys.entries)
        {
          'user_id': uid,
          'device_num': deviceNum,
          'prekey_id': e.key,
          'pub': _hex(e.value),
        }
    ]);
  }

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('signal_one_time_prekeys')
        .select('prekey_id')
        .eq('user_id', uid)
        .eq('device_num', deviceNum)
        .isFilter('consumed_at', null);
    return (rows as List).length;
  }
}

const _hexDigits = '0123456789abcdef';

/// Encodes bytes as the `\x`-prefixed lowercase hex string PostgREST expects
/// for `bytea` columns/params. Mirrors the decode side, [DeviceBundle._bytes]
/// in prekey_bundle_source.dart.
///
/// WHY: PostgREST JSON-encodes a raw [Uint8List] as an int array
/// (`[10,11,12,...]`), which Postgres rejects for `bytea` with
/// "invalid input syntax for type bytea". The wire format bytea actually
/// accepts over PostgREST is the `\x`-prefixed hex string produced here.
String _hex(Uint8List bytes) {
  final out = StringBuffer(r'\x');
  for (final b in bytes) {
    out.write(_hexDigits[(b >> 4) & 0xf]);
    out.write(_hexDigits[b & 0xf]);
  }
  return out.toString();
}

/// Generate + publish this device's identity once. Idempotent: an existing
/// identity is never regenerated, because that would break every session.
///
/// There are three possible states on entry:
///  1. Identity + device_num both present → already fully registered;
///     short-circuit and return the stored device_num.
///  2. No identity at all → first-ever registration; generate everything.
///  3. Identity present but device_num absent → a PARTIAL prior attempt:
///     [savePrivate] succeeded but the app died or the network dropped
///     before [saveDeviceNum] ran (there is a network round-trip via
///     [DeviceRegistrar.register] between the two). This is a RESUME, not
///     a fresh registration: the stored identity keypair and registration
///     id must be reused as-is (sessions and TOFU pins bind to them), while
///     the signed prekey and one-time prekeys are regenerated fresh, which
///     is normal and safe.
Future<int> ensureRegistered({
  required SignalDb db,
  required KeyVault vault,
  required DeviceRegistrar registrar,
  int oneTimePrekeyCount = 20,
}) async {
  final existingNum = await vault.readDeviceNum();
  final hasIdentity = await vault.hasIdentity();
  if (hasIdentity && existingNum != null) {
    // App start of an already-registered device: this is the steady-state
    // path taken on every launch, so it's the only reliable place to top up
    // a prekey pool that consumption has drained since last time. Non-fatal:
    // a failed top-up degrades handshakes, it doesn't break the device.
    try {
      await replenishPrekeysIfLow(db: db, vault: vault, registrar: registrar);
    } catch (_) {}
    return existingNum;
  }

  var deviceId = await vault.deviceId();
  deviceId ??= const Uuid().v4();
  await vault.saveDeviceId(deviceId);

  sig.IdentityKeyPair? existingIdentity;
  int? existingRegistrationId;
  if (hasIdentity) {
    // State 3: resume — reuse the identity, do not regenerate it.
    final identityBytes = await vault.readIdentity();
    existingIdentity = sig.IdentityKeyPair.fromSerialized(identityBytes!);
    existingRegistrationId = await vault.readRegistrationId();
  }

  // Allocate ids from the persisted counters rather than hardcoding them.
  // A re-registration (the resume path above) must never reissue an id that
  // a spouse's device may already hold key material for — see KeyCounters.
  final counters = KeyCounters(db);
  final firstPrekeyId = await counters.nextPrekeyId(oneTimePrekeyCount);
  final signedPrekeyId = await counters.nextSignedPrekeyId();

  final generated = generateBundle(
    deviceId: deviceId,
    oneTimePrekeyCount: oneTimePrekeyCount,
    existingIdentity: existingIdentity,
    existingRegistrationId: existingRegistrationId,
    firstPrekeyId: firstPrekeyId,
    signedPrekeyId: signedPrekeyId,
  );
  await vault.savePrivate(generated.private);

  // Seed the local Drift stores with this device's own prekeys BEFORE any
  // network call. SessionCipher/SessionBuilder read prekeys from these
  // tables (not the KeyVault) when resolving an incoming PreKeySignalMessage,
  // so without this, this device can never establish a session with anyone —
  // it references prekey ids that were only ever written to the KeyVault and
  // published to Supabase. Seeding first also means a network failure below
  // still leaves a locally-consistent device (its own store already has the
  // prekeys it just generated).
  //
  // storeSignedPreKey upserts by id, and because signedPrekeyId now advances
  // via KeyCounters instead of being hardcoded, a rotation on resume writes a
  // NEW row rather than clobbering the previous one. Retaining old signed
  // prekeys is deliberate, not an oversight: an in-flight PreKeySignalMessage
  // names the spk id it was built against, and libsignal resolves it by that
  // id, so deleting the old row would make such a message permanently
  // undecryptable.
  final store = DriftSignalStore(db, vault);
  final private = generated.private;
  for (final entry in private.oneTimePrekeysSerialized.entries) {
    await store.storePreKey(
        entry.key, sig.PreKeyRecord.fromBuffer(entry.value));
  }
  await store.storeSignedPreKey(
    generated.public.signedPrekeyId,
    sig.SignedPreKeyRecord.fromSerialized(private.signedPrekeySerialized),
  );

  final pub = generated.public;
  final deviceNum = await registrar.register(
    deviceId: deviceId,
    registrationId: pub.registrationId,
    identityPub: pub.identityPub,
    signedPrekeyId: pub.signedPrekeyId,
    signedPrekeyPub: pub.signedPrekeyPub,
    signedPrekeySig: pub.signedPrekeySig,
  );

  // Upload one-time prekeys BEFORE persisting the device number. If this
  // upload fails, saveDeviceNum below never runs, so the
  // `hasIdentity && existingNum != null` short-circuit stays closed and the
  // next call retries the whole tail end — including this upload.
  // register_device_bundle upserts on (user_id, device_id) and reuses the
  // existing device_num server-side, so re-running register() here is safe.
  await registrar.uploadOneTimePrekeys(
    deviceNum: deviceNum,
    prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
  );
  await vault.saveDeviceNum(deviceNum);

  // Non-fatal: a failed top-up degrades handshakes, it doesn't break the device.
  try {
    await replenishPrekeysIfLow(db: db, vault: vault, registrar: registrar);
  } catch (_) {}

  return deviceNum;
}

/// Top up this device's one-time prekeys when the server pool runs low.
///
/// Ids come from the persisted counter, so a top-up can never reissue an id the
/// spouse already holds under different key material.
///
/// Failure is non-fatal: the device still works, its handshakes just degrade to
/// signed-prekey-only until the next attempt.
Future<void> replenishPrekeysIfLow({
  required SignalDb db,
  required KeyVault vault,
  required DeviceRegistrar registrar,
  int threshold = 10,
  int topUpTo = 20,
}) async {
  final deviceNum = await vault.readDeviceNum();
  if (deviceNum == null) return; // not registered yet

  final remaining = await registrar.unconsumedPrekeyCount(deviceNum);
  if (remaining >= threshold) return;

  final need = topUpTo - remaining;
  if (need <= 0) return;

  final firstId = await KeyCounters(db).nextPrekeyId(need);
  final batch = generatePrekeyBatch(firstPrekeyId: firstId, count: need);

  final store = DriftSignalStore(db, vault);
  for (final e in batch.privateSerialized.entries) {
    await store.storePreKey(e.key, sig.PreKeyRecord.fromBuffer(e.value));
  }

  await registrar.uploadOneTimePrekeys(
    deviceNum: deviceNum,
    prekeys: {for (final p in batch.publics) p.id: p.pub},
  );
}
