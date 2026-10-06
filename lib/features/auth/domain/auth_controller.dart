import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/key_vault.dart';
import '../../../core/crypto/secure_store.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/auth_repository.dart';

/// The device's secure storage (Keychain / Keystore). Overridable so tests can
/// share one in-memory store between several accounts.
final secureStoreProvider = Provider<SecureStore>((ref) {
  return FlutterSecureStore(ref.read(secureStorageProvider));
});

/// The Signal key vault for ONE account, keyed by user id. Each account's keys
/// are namespaced in secure storage, so accounts sharing a device keep their
/// own identity and device number across sign-out / account switches.
final keyVaultProvider = Provider.family<KeyVault, String>((ref, userId) {
  return KeyVault(ref.read(secureStoreProvider), scope: userId);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(supabaseClientProvider));
});

/// Broadcasts the current [Session] (null when signed out).
///
/// The initial value is emitted via a microtask so this provider never
/// synchronously invalidates downstream subscribers during a subscribe/flush
/// cycle. That protects against "setState during build" cascades when
/// route transitions cause `ConsumerStatefulElement._updateTickerMode` to
/// resume subscriptions.
final authSessionProvider = StreamProvider<Session?>((ref) {
  final repo = ref.read(authRepositoryProvider);
  final controller = StreamController<Session?>();
  scheduleMicrotask(() {
    if (!controller.isClosed) controller.add(repo.currentSession);
  });
  final sub = repo.authStateChanges().listen((state) {
    if (!controller.isClosed) controller.add(state.session);
  });
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
