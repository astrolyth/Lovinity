import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/local_day.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/adhkar_progress_store.dart';
import '../data/adhkar_repository.dart';

final nowProvider = Provider<DateTime Function()>((_) => DateTime.now);

final adhkarRepositoryProvider = Provider<AdhkarRepository>(
  (ref) => AdhkarRepository(ref.read(supabaseClientProvider)),
);

final adhkarProgressStoreProvider = Provider<AdhkarProgressStore>(
  (ref) => AdhkarProgressStore(ref.read(secureStorageProvider)),
);

final adhkarTodayKeyProvider = Provider<String>((ref) {
  final tzId =
      ref.watch(ownProfileProvider.select((p) => p.asData?.value?.timezone)) ??
          'UTC';
  return dayKey(localDayAt(tzId, ref.watch(nowProvider)()));
});

final adhkarCompletionsProvider =
    StreamProvider<List<AdhkarCompletion>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(adhkarRepositoryProvider).watchRecent(coupleId);
});

/// Notifies when the spouse finishes an adhkar set. Same shape as
/// `duaNotificationPumpProvider`. Watched once from HomeScreen.
final adhkarNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<AdhkarCompletion>(
    keyOf: (c) => '${c.userId}|${c.localDate}|${c.set.dbValue}',
    onNew: (c) {
      if (c.userId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'adhkar',
        title: 'Your partner finished ${c.set.label.toLowerCase()} adhkar',
        body: null,
        route: '/home/duas',
      ));
    },
  );

  final sub =
      ref.read(adhkarRepositoryProvider).watchRecent(coupleId).listen(detector);
  ref.onDispose(sub.cancel);
});
