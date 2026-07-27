import 'package:flutter_riverpod/flutter_riverpod.dart';

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
