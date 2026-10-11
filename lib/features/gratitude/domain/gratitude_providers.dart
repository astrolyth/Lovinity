import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/gratitude_repository.dart';

final gratitudeRepositoryProvider = Provider<GratitudeRepository>((ref) {
  return GratitudeRepository(ref.read(supabaseClientProvider));
});

/// All notes for the couple, newest first.
final gratitudeNotesProvider =
    StreamProvider<List<GratitudeNote>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (couple == null || session == null) return const Stream.empty();
  return ref.read(gratitudeRepositoryProvider).watchAll(
        coupleId: couple.id,
        selfUserId: session.user.id,
      );
});

/// Whether the current user already wrote a note today.
final wroteGratitudeTodayProvider = Provider<bool>((ref) {
  final notes = ref.watch(gratitudeNotesProvider).asData?.value ?? const [];
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return false;
  final today = DateTime.now();
  return notes.any((n) =>
      n.authorId == session.user.id &&
      n.createdAt.year == today.year &&
      n.createdAt.month == today.month &&
      n.createdAt.day == today.day);
});

/// Writes a notification the moment a partner's gratitude note becomes
/// visible to you. Diffs `GratitudeRepository.watchAll`'s (fixed, above)
/// snapshots by id -- since the query fix guarantees a partner row only
/// ever appears here once it's genuinely visible (created-and-revealed
/// immediately, or revealed later), a plain new-row diff already means
/// "revealed," with no separate reveal-transition tracking needed. Watched
/// once from HomeScreen.
final gratitudeNotificationPumpProvider = Provider<void>((ref) {
  // Narrowed to scalar ids so a token refresh (~hourly) or a couple-object
  // rebuild (Couple has no operator==, and SupabaseStreamBuilder refetches
  // on every realtime reconnect) doesn't re-baseline the detector below and
  // swallow partner activity that happened while backgrounded.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<GratitudeNote>(
    keyOf: (n) => n.id,
    onNew: (note) {
      if (note.authorId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'gratitude',
        title: 'Your partner shared something they\'re grateful for',
        route: '/home/gratitude',
      ));
    },
  );

  final sub = ref
      .read(gratitudeRepositoryProvider)
      .watchAll(coupleId: coupleId, selfUserId: selfId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
