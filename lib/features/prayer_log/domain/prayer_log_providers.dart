import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/prayer_log.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/prayer_log_repository.dart';

final prayerLogRepositoryProvider = Provider<PrayerLogRepository>((ref) {
  return PrayerLogRepository(ref.read(supabaseClientProvider));
});

/// The date this feature is showing. Defaults to today.
class PrayerLogSelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void set(DateTime d) => state = DateTime(d.year, d.month, d.day);
}

final prayerLogSelectedDateProvider =
    NotifierProvider<PrayerLogSelectedDate, DateTime>(
  PrayerLogSelectedDate.new,
);

/// Prayers may be logged/corrected for today and yesterday only.
bool isLoggableDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = today.difference(d).inDays;
  return diff == 0 || diff == 1;
}

/// Live stream of prayer logs for the couple + selected date (both spouses).
final prayerLogsForDayProvider =
    StreamProvider<List<PrayerLogEntry>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final date = ref.watch(prayerLogSelectedDateProvider);
  if (couple == null) return const Stream.empty();
  return ref
      .read(prayerLogRepositoryProvider)
      .watchDay(coupleId: couple.id, date: date);
});

/// Summary counts for today: how many prayers each spouse has logged.
class PrayerDaySummary {
  const PrayerDaySummary({
    required this.own,
    required this.spouse,
    required this.togetherWindowSeconds,
  });

  /// Prayers the current user has logged today.
  final Set<Prayer> own;

  /// Prayers the spouse has logged today.
  final Set<Prayer> spouse;

  /// A rough "togetherness" indicator — minimum absolute time delta (seconds)
  /// between paired check-ins today. Null when no pair overlaps yet.
  final int? togetherWindowSeconds;

  int get ownCount => own.length;
  int get spouseCount => spouse.length;
  Set<Prayer> get both => own.intersection(spouse);
}

final prayerDaySummaryProvider =
    Provider<PrayerDaySummary>((ref) {
  final logs = ref.watch(prayerLogsForDayProvider).asData?.value ?? const [];
  final session = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;

  if (session == null || couple == null) {
    return const PrayerDaySummary(
      own: {},
      spouse: {},
      togetherWindowSeconds: null,
    );
  }
  final myId = session.user.id;
  final own = <Prayer>{};
  final spouse = <Prayer>{};
  final ownTimes = <Prayer, DateTime>{};
  final spouseTimes = <Prayer, DateTime>{};

  for (final l in logs) {
    if (l.status != PrayerStatus.prayed) continue;
    if (l.userId == myId) {
      own.add(l.prayer);
      ownTimes[l.prayer] = l.timeLogged;
    } else {
      spouse.add(l.prayer);
      spouseTimes[l.prayer] = l.timeLogged;
    }
  }

  int? closest;
  for (final p in own.intersection(spouse)) {
    final a = ownTimes[p]!;
    final b = spouseTimes[p]!;
    final delta = a.difference(b).abs().inSeconds;
    if (closest == null || delta < closest) closest = delta;
  }

  return PrayerDaySummary(
    own: own,
    spouse: spouse,
    togetherWindowSeconds: closest,
  );
});

/// Writes a notification when the spouse logs a prayer, on ANY day. Diffs
/// `watchCouple`'s snapshots (keyed by user+prayer+date) so only genuinely
/// new check-ins fire, never the existing history a fresh subscription
/// loads, and never the user's own check-ins. Watched once from HomeScreen.
///
/// Deliberately uses `watchCouple`, not `watchDay`: prayer times are (and
/// should stay) anchored to each partner's own local calendar day, but that
/// means the two devices can legitimately disagree about what "today" is.
/// `watchDay` would filter the partner's row out entirely whenever her local
/// date differs from this device's, silently dropping the very activity
/// this pump exists to surface. `watchCouple` has no date filter, so it
/// can't drop a cross-timezone check-in.
final prayerNotificationPumpProvider = Provider<void>((ref) {
  // Narrowed to scalar ids so a token refresh (~hourly) or a couple-object
  // rebuild (Couple has no operator==, and SupabaseStreamBuilder refetches
  // on every realtime reconnect) doesn't re-baseline the detector below and
  // swallow partner activity that happened while backgrounded.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  // NOTE: no `ref.watch(todayKeyProvider)` here (unlike before this fix).
  // That watch existed solely to force a daily re-subscribe, because
  // `watchDay` baked a client-side date-key filter in at subscribe time and
  // would otherwise keep filtering for yesterday's key forever past
  // midnight. `watchCouple` has no date filter at all, so there's nothing
  // for a day-rollover to invalidate -- the stream just keeps emitting.
  // Watching it now would be actively harmful: every such rebuild resets
  // `newRowDetector`'s baseline, and per its "never fires on the first
  // emission" rule, any partner check-in that happens to land right at the
  // resubscribe would be silently absorbed as baseline instead of firing.
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<PrayerLogEntry>(
    // Date is part of the key: without it, the same prayer logged on two
    // different days would collide on one key, and the second day's
    // check-in would look like a re-emit of the first rather than new
    // activity -- so it would never notify.
    keyOf: (e) => '${e.userId}:${e.dateKey}:${e.prayer.dbName}',
    onNew: (entry) {
      if (entry.userId == selfId) return;
      if (entry.status != PrayerStatus.prayed) return;
      unawaited(store.insertBestEffort(
        kind: 'prayer',
        title: 'Your partner logged ${entry.prayer.displayName}',
        route: '/home/prayer',
      ));
    },
  );

  final sub = ref
      .read(prayerLogRepositoryProvider)
      .watchCouple(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
