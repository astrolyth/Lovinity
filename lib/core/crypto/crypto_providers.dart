// lib/core/crypto/crypto_providers.dart
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart'
    show authSessionProvider, authRepositoryProvider, keyVaultProvider;
import '../../shared/providers/supabase_provider.dart';
import '../notifications/notification_providers.dart';
import '../storage/signal_db.dart';
import 'prekey_bundle_source.dart';
import 'signal_registration.dart';
import 'signal_session_service.dart';

/// One SignalDb for the app's lifetime (opens the on-disk `lovinity_signal` db).
final signalDbProvider = Provider<SignalDb>((ref) {
  final db = SignalDb();
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

  final db = ref.read(signalDbProvider);
  final vault = ref.read(keyVaultProvider);

  // Account-switch guard: also runs at sign-in via ensureRegisteredProvider
  // (before navigation), but enforced here too so a restored/rebuilt session
  // can never build a service over another user's local data.
  await guardAccountSwitch(db: db, vault: vault, selfUserId: selfUserId);

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
    db: ref.watch(signalDbProvider),
    vault: vault,
    bundles: ref.read(preKeyBundleSourceProvider),
    selfUserId: selfUserId,
    selfDeviceNum: selfDeviceNum,
  );
});

/// Sign out. Does NOT wipe the device-local data: the SAME user signing back
/// in must keep their chat history and Signal identity/device. A DIFFERENT
/// user signing in is detected and wiped by [ensureRegisteredProvider]'s
/// account-switch guard, so this only needs to clear the auth session.
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

/// Registers this device (idempotent) + tops up prekeys. Call after auth.
///
/// Runs the account-switch guard first: the local DB (chat history + Signal
/// state) is device-global and survives sign-out, so if it belongs to a
/// DIFFERENT user than the one now signed in, wipe it (and the identity)
/// before registering — otherwise the new user would see the previous user's
/// messages and reuse their sessions. The SAME user re-logging keeps
/// everything (steady-state path in ensureRegistered).
final ensureRegisteredProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    final db = ref.read(signalDbProvider);
    final vault = ref.read(keyVaultProvider);
    final selfUserId = ref.read(authRepositoryProvider).currentUser?.id;

    if (selfUserId != null) {
      await guardAccountSwitch(db: db, vault: vault, selfUserId: selfUserId);
    }

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
