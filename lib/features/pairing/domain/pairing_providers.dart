import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/models/couple.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/pairing_repository.dart';

final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  return PairingRepository(ref.read(supabaseClientProvider));
});

/// The current user's couple (null when unpaired). Live via realtime.
///
/// Emits null immediately when there is no session, so downstream consumers
/// (router redirect, home screen) see a resolved value rather than staying
/// in a permanent loading state after sign-out.
///
/// Narrowed to the scalar user id, not the whole Session -- watching the
/// Session object directly would rebuild this provider (emitting an
/// intermediate AsyncLoading with a null `.asData`) on every token refresh
/// (~hourly), which re-baselines every downstream notification pump that
/// diffs this provider's output and swallows partner activity that happened
/// while backgrounded.
final currentCoupleProvider = StreamProvider<Couple?>((ref) {
  final userId = ref.watch(
    authSessionProvider.select((s) => s.asData?.value?.user.id),
  );
  if (userId == null) return Stream.value(null);
  return ref.read(pairingRepositoryProvider).watchCurrentCouple(userId);
});

/// Writes a "You're connected" notification the moment pairing becomes
/// active. Mirrors the `inboxPumpProvider`/`receiptPumpProvider` shape in
/// chat_providers.dart: a `Provider<void>` that owns a raw stream
/// subscription rather than composing StreamProviders, so it can track the
/// previous emission itself. Watched once from HomeScreen.
final pairingNotificationPumpProvider = Provider<void>((ref) {
  // Narrowed to the scalar id, not the whole Session -- watching the
  // Session object directly would rebuild (and re-baseline `previousStatus`
  // below to null) on every token refresh (~hourly), silently swallowing a
  // pairing-activation that lands in that same refreshed snapshot.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (selfId == null) return;
  final store = ref.read(notificationStoreProvider);

  String? previousStatus;
  final sub = ref
      .read(pairingRepositoryProvider)
      .watchCurrentCouple(selfId)
      .listen((couple) {
    if (pairingJustActivated(previousStatus, couple?.status)) {
      unawaited(store.insertBestEffort(
        kind: 'pairing',
        title: "You're connected",
        body: 'You and your partner are now paired 💛',
        route: '/home',
      ));
    }
    previousStatus = couple?.status;
  });
  ref.onDispose(sub.cancel);
});
