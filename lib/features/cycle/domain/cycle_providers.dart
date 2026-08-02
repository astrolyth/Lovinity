import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/cycle_repository.dart';
import 'cycle_prediction.dart';

final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  return CycleRepository(ref.read(supabaseClientProvider));
});

final isWifeProvider = Provider<bool>((ref) {
  final profile = ref.watch(ownProfileProvider).asData?.value;
  return profile?.gender == 'female';
});

final ownCycleHistoryProvider = StreamProvider<List<CycleRecord>>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return Stream.value(const []);
  return ref.read(cycleRepositoryProvider).watchOwn(userId: session.user.id);
});

final activeCycleProvider = Provider<CycleRecord?>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  final today = DateTime.now();
  for (final r in history) {
    if (r.isActiveOn(today)) return r;
  }
  return null;
});

final cyclePredictionProvider = Provider<CyclePrediction>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  return predictCycle(history);
});

/// Writes a notification when the spouse shares a cycle update. Diffs
/// `watchCoupleShared`'s snapshots by record id. Client-side filters to
/// `visibility == 'shared' && userId != self` as defense in depth even
/// though RLS already guarantees a private spouse record never reaches this
/// stream at all. Deliberately non-clinical wording. Watched once from
/// HomeScreen.
final cycleNotificationPumpProvider = Provider<void>((ref) {
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

  final detector = newRowDetector<CycleRecord>(
    keyOf: (r) => r.id,
    onNew: (record) {
      if (record.userId == selfId) return;
      if (record.visibility != 'shared') return;
      unawaited(store.insertBestEffort(
        kind: 'cycle',
        title: 'Your partner shared a cycle update',
        route: '/home/cycle',
      ));
    },
  );

  final sub = ref
      .read(cycleRepositoryProvider)
      .watchCoupleShared(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
