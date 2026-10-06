// lib/core/crypto/crypto_providers.dart
import 'dart:developer' as developer;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart'
    show authSessionProvider, authRepositoryProvider, keyVaultProvider;
import '../../shared/providers/supabase_provider.dart';
import '../notifications/notification_providers.dart';
import '../storage/signal_db.dart';
import 'prekey_bundle_source.dart';
import 'signal_registration.dart';
import 'signal_session_service.dart';

/// The local database for ONE account, keyed by user id (its own on-disk
/// file — see [SignalDb.forUser]). Kept alive for the app's lifetime, so an
/// account that signs out and back in reopens nothing and loses nothing.
final signalDbProvider = Provider.family<SignalDb, String>((ref, userId) {
  // Drift warns when a database class is instantiated more than once, because
  // two instances over the SAME file race. Here every instance is a different
  // file (one per account) and the family never builds two for the same
  // user, so the warning doesn't apply.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = SignalDb.forUser(userId);
  ref.onDispose(db.close);
  return db;
});

final deviceRegistrarProvider = Provider<DeviceRegistrar>((ref) {
  return SupabaseDeviceRegistrar(ref.read(supabaseClientProvider));
});

final preKeyBundleSourceProvider = Provider<PreKeyBundleSource>((ref) {
  return SupabasePreKeyBundleSource(ref.read(supabaseClientProvider));
});

/// Builds the crypto session service from PERSISTED / LIVE self-identity
/// rather than an ephemeral cache:
///  - `selfUserId` comes from [authSessionProvider], the live auth session,
///    so it tracks sign-in/out instead of being read once and cached forever.
///  - `selfDeviceNum` comes from `KeyVault.readDeviceNum()`, which is
///    persisted in secure storage and survives restarts — a returning user
///    who is already signed in gets their real device number without
///    depending on [ensureRegisteredProvider] having run this session.
///
/// Resolves to `null` when there is no signed-in user, or when this device
/// hasn't completed registration yet (`readDeviceNum()` is still null). A
/// `null` service means "crypto not ready"; callers are expected to handle
/// that rather than assume a service is always available.
final signalSessionServiceProvider =
    FutureProvider<SignalSessionService?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  final selfUserId = session?.user.id;
  if (selfUserId == null) return null;

  final db = ref.watch(signalDbProvider(selfUserId));
  final vault = ref.read(keyVaultProvider(selfUserId));

  // If this device isn't registered yet, register it now. That happens for a
  // session restored on launch or if the first registration failed.
  // ensureRegistered is idempotent and returns this device's number, so the
  // crypto layer self-heals instead of leaving chat stuck on "setting up secure
  // chat" forever. If it throws (network/RPC), the error propagates so callers
  // can surface it rather than silently masking it as "not ready".
  final selfDeviceNum = await vault.readDeviceNum() ??
      await ensureRegistered(
        db: db,
        vault: vault,
        registrar: ref.read(deviceRegistrarProvider),
      );

  return SignalSessionService(
    db: db,
    vault: vault,
    bundles: ref.read(preKeyBundleSourceProvider),
    selfUserId: selfUserId,
    selfDeviceNum: selfDeviceNum,
  );
});

/// Sign out. Wipes nothing: each account's local data lives in its own
/// database file and key namespace, so signing back in (as the same or a
/// different account) needs no cleanup and loses no history.
final signOutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    // Unregister the push token BEFORE clearing the session: it needs the
    // still-live session to call `unregister_push_token`. Best-effort --
    // PushService already no-ops/swallows when push is unavailable, but this
    // guard is kept too so a misbehaving fake/future PushService can never
    // block sign-out.
    try {
      await ref
          .read(pushServiceProvider)
          .unregisterToken(ref.read(supabaseClientProvider));
    } catch (e, st) {
      developer.log(
        'push token unregistration failed (sign-out proceeds anyway)',
        name: 'signOutProvider',
        error: e,
        stackTrace: st,
      );
    }

    await ref.read(authRepositoryProvider).signOut();
  };
});

/// Registers this device for the signed-in account (idempotent) + tops up
/// prekeys. Call after auth.
///
/// Uses the account's OWN database and key namespace, so an account that was
/// already registered on this device keeps its device number — messages
/// addressed to it while another account was signed in still arrive.
final ensureRegisteredProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    // Read the user straight from the auth client, not the session stream:
    // this runs immediately after sign-in, possibly before the stream has
    // emitted the new session.
    final selfUserId = ref.read(authRepositoryProvider).currentUser?.id;
    if (selfUserId == null) {
      throw StateError('ensureRegistered called with no signed-in user');
    }
    final db = ref.read(signalDbProvider(selfUserId));
    final vault = ref.read(keyVaultProvider(selfUserId));

    final deviceNum = await ensureRegistered(
      db: db,
      vault: vault,
      registrar: ref.read(deviceRegistrarProvider),
    );

    // Best-effort push token registration, after device registration has
    // already succeeded. PushService already no-ops/swallows internally when
    // push is unavailable, but this guard is kept too so a misbehaving
    // fake/future PushService can never turn a successful device
    // registration into a failed one.
    try {
      await ref
          .read(pushServiceProvider)
          .registerToken(ref.read(supabaseClientProvider));
    } catch (e, st) {
      developer.log(
        'push token registration failed (device registration still succeeded)',
        name: 'ensureRegisteredProvider',
        error: e,
        stackTrace: st,
      );
    }

    return deviceNum;
  };
});
