import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/dua_repository.dart';

final duaRepositoryProvider = Provider<DuaRepository>((ref) {
  return DuaRepository(ref.read(supabaseClientProvider));
});

/// All couple's duas. `duas_own`/`duas_spouse_shared_read` RLS on
/// `public.duas` is what actually keeps a partner's `private` dua off the
/// wire -- a partner's client never receives that row at all. The `.where`
/// below is defense in depth on top of that server-side enforcement, not a
/// substitute for it: it also guards against anomalous rows (e.g. a
/// visibility value RLS didn't anticipate) and keeps this stream's contract
/// self-documenting for callers who don't know about the DB policies.
final duasProvider = StreamProvider<List<Dua>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (couple == null || session == null) return const Stream.empty();
  final me = session.user.id;
  return ref.read(duaRepositoryProvider).watch(couple.id).map(
        (rows) => rows
            .where((d) => d.visibility == 'shared' || d.authorId == me)
            .toList(growable: false),
      );
});

/// Open duas (not yet answered). Newest first.
final openDuasProvider = Provider<List<Dua>>((ref) {
  final all = ref.watch(duasProvider).asData?.value ?? const [];
  return all.where((d) => !d.isAnswered).toList();
});

/// Answered duas. Newest first.
final answeredDuasProvider = Provider<List<Dua>>((ref) {
  final all = ref.watch(duasProvider).asData?.value ?? const [];
  return all.where((d) => d.isAnswered).toList();
});

/// Writes a notification when the spouse adds a new SHARED dua. Diffs
/// `DuaRepository.watch`'s snapshots by id -- `watch` itself returns every
/// dua regardless of visibility (the repository already needs that so an
/// author can manage their own private ones), so this pump filters to
/// `visibility == 'shared' && authorId != self` itself in `onNew`, the same
/// division of responsibility the cycle pump already uses for its own
/// visibility filter. Watched once from HomeScreen.
final duaNotificationPumpProvider = Provider<void>((ref) {
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

  final detector = newRowDetector<Dua>(
    keyOf: (d) => d.id,
    onNew: (dua) {
      if (dua.authorId == selfId) return;
      if (!dua.isShared) return;
      unawaited(store.insertBestEffort(
        kind: 'dua',
        title: 'Your partner added a dua',
        body: dua.title,
        route: '/home/duas',
      ));
    },
  );

  final sub =
      ref.read(duaRepositoryProvider).watch(coupleId).listen(detector);
  ref.onDispose(sub.cancel);
});
