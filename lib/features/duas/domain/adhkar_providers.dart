import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/local_day.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/adhkar_progress_store.dart';
import '../data/adhkar_repository.dart';
import 'dua_library_providers.dart';

final nowProvider = Provider<DateTime Function()>((_) => DateTime.now);

final adhkarRepositoryProvider = Provider<AdhkarRepository>(
  (ref) => AdhkarRepository(ref.read(supabaseClientProvider)),
);

final adhkarProgressStoreProvider = Provider<AdhkarProgressStore>(
  (ref) => AdhkarProgressStore(ref.read(secureStorageProvider)),
);

/// Bumped on app resume and at the next local midnight (own profile zone) so
/// [adhkarTodayKeyProvider] re-reads the clock. Session-lifetime: HomeScreen
/// keeps it alive, so the day rolls over whichever screen is open.
class DayTick extends Notifier<int> {
  Timer? _midnight;

  @override
  int build() {
    final observer = _ResumeObserver(() {
      bump();
      // An offline first open leaves the cached library errored; retry it.
      if (ref.read(duaLibraryProvider).hasError) {
        ref.invalidate(duaLibraryProvider);
      }
    });
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(observer);
      _midnight?.cancel();
    });
    ref.listen(
      ownProfileProvider.select((p) => p.value?.timezone),
      (_, _) => _schedule(),
    );
    _schedule();
    return 0;
  }

  void bump() {
    state++;
    _schedule();
  }

  void _schedule() {
    _midnight?.cancel();
    final tzId = ref.read(ownProfileProvider).value?.timezone;
    if (tzId == null || tzId.isEmpty) return;
    final now = localTimeAt(tzId, ref.read(nowProvider)());
    final next = tz.TZDateTime(now.location, now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), bump);
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final void Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

final dayTickProvider = NotifierProvider<DayTick, int>(DayTick.new);

/// Today's local day key, or null while the own profile timezone is unknown
/// (loading, error, null or empty): callers must treat null as "not ready".
final adhkarTodayKeyProvider = Provider<String?>((ref) {
  ref.watch(dayTickProvider);
  final tzId =
      ref.watch(ownProfileProvider.select((p) => p.asData?.value?.timezone));
  if (tzId == null || tzId.isEmpty) return null;
  return dayKey(localDayAt(tzId, ref.read(nowProvider)()));
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
