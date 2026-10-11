import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/local_day.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/time/tz_sync.dart';
import '../../../shared/models/prayer_log.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/prayer_log_repository.dart';

final prayerLogRepositoryProvider = Provider<PrayerLogRepository>((ref) {
  return PrayerLogRepository(ref.read(supabaseClientProvider));
});

/// Which day the feature is showing, as an **offset** back from "today":
/// `0` today, `1` yesterday, `n` n days back.
///
/// Deliberately not an absolute date. A couple can sit in two timezones, and a
/// single date cannot describe both of them — at Toronto 3pm Thursday it is
/// already Dhaka 1am Friday. Storing the offset lets each side resolve the
/// *same intent* ("today", "yesterday") against its own zone, so "Yesterday"
/// means her yesterday on her half of the screen and yours on yours. Holding
/// one absolute date here was the root of every falsehood this feature used to
/// tell.
class PrayerLogDayOffset extends Notifier<int> {
  @override
  int build() => 0;

  /// Clamped at 0: there is no honest "tomorrow" to show.
  void set(int value) => state = value < 0 ? 0 : value;

  void goBack() => state = state + 1;

  void goForward() => state = state == 0 ? 0 : state - 1;
}

final prayerLogDayOffsetProvider =
    NotifierProvider<PrayerLogDayOffset, int>(PrayerLogDayOffset.new);

/// Prayers may be logged or corrected for today and yesterday only.
///
/// Evaluated purely on the offset, in the user's own zone — you can only ever
/// write your own rows, so the spouse's zone is irrelevant to this decision.
bool isLoggableOffset(int offset) => offset == 0 || offset == 1;

/// The two spouses' resolved day keys for the currently selected offset.
///
/// Value-equal by design. This is what the realtime subscription keys off, and
/// it is recomputed on every 30-second tick — without `==` two structurally
/// identical instances would compare unequal, tearing down and re-opening the
/// prayer-log stream twice a minute. With it, watchers wake only when a key
/// genuinely changes, i.e. at either spouse's local midnight.
class PrayerDayKeys {
  const PrayerDayKeys({
    required this.ownUserId,
    required this.ownKey,
    required this.spouseUserId,
    required this.spouseKey,
  });

  final String ownUserId;
  final String ownKey;
  final String? spouseUserId;
  final String? spouseKey;

  /// Shaped for [PrayerLogRepository.watchDays]: each user id mapped to the
  /// day being shown for that user.
  Map<String, String> get byUserId => {
        ownUserId: ownKey,
        if (spouseUserId != null && spouseKey != null) spouseUserId!: spouseKey!,
      };

  /// True when the spouses' shown days are the same calendar date — the common
  /// case, and the signal the header uses to collapse the dual clock.
  bool get agree => spouseKey == null || spouseKey == ownKey;

  @override
  bool operator ==(Object other) =>
      other is PrayerDayKeys &&
      other.ownUserId == ownUserId &&
      other.ownKey == ownKey &&
      other.spouseUserId == spouseUserId &&
      other.spouseKey == spouseKey;

  @override
  int get hashCode => Object.hash(ownUserId, ownKey, spouseUserId, spouseKey);
}

/// Resolves the selected offset against each spouse's own timezone.
///
/// Your anchor is the **device** zone, not your profile's: it is correct the
/// moment you land somewhere new, with no network round-trip, so your own log
/// stays truthful even offline. Your spouse's anchor can only come from her
/// profile — that row is the sole channel through which her zone reaches this
/// device (see `core/time/tz_sync.dart`).
final prayerDayKeysProvider = Provider<PrayerDayKeys?>((ref) {
  final offset = ref.watch(prayerLogDayOffsetProvider);
  final session = ref.watch(authSessionProvider).asData?.value;
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value;
  final spouse = ref.watch(spouseProfileProvider).asData?.value;
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();

  if (session == null || deviceTz == null) return null;

  return PrayerDayKeys(
    ownUserId: session.user.id,
    ownKey: dayKey(dayForOffset(tzId: deviceTz, offset: offset, at: now)),
    spouseUserId: spouse?.id,
    spouseKey: spouse == null
        ? null
        : dayKey(
            dayForOffset(tzId: spouse.timezone, offset: offset, at: now),
          ),
  );
});

/// Live stream of prayer logs for the couple, each spouse's rows scoped to
/// that spouse's own day.
final prayerLogsForDayProvider = StreamProvider<List<PrayerLogEntry>>((ref) {
  // Narrowed to the scalar id: `Couple` has no `operator ==`, so watching the
  // object itself would re-subscribe on every realtime reconnect.
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  final keys = ref.watch(prayerDayKeysProvider);
  if (coupleId == null || keys == null) return const Stream.empty();
  return ref
      .read(prayerLogRepositoryProvider)
      .watchDays(coupleId: coupleId, dayKeyByUserId: keys.byUserId);
});

/// A gap between two check-ins is only described as shared time when it is
/// genuinely small. Beyond this, the UI states completion parity and makes no
/// claim about simultaneity — a couple ten hours apart never prays "together"
/// in any literal sense, and saying so would be exactly the kind of false
/// truth this feature exists to avoid.
const kTogethernessWindow = Duration(hours: 1);

/// Summary of the shown day: what each spouse completed, and how honestly the
/// two can be said to have shared it.
class PrayerDaySummary {
  const PrayerDaySummary({
    required this.own,
    required this.spouse,
    required this.closestGap,
  });

  const PrayerDaySummary.empty()
      : own = const {},
        spouse = const {},
        closestGap = null;

  /// Prayers the current user completed on **their** shown day.
  final Set<Prayer> own;

  /// Prayers the spouse completed on **her** shown day.
  final Set<Prayer> spouse;

  /// Smallest real elapsed gap between a prayer both completed, computed on
  /// `time_logged` instants (absolute, so timezone-independent). Null when
  /// nothing matches.
  final Duration? closestGap;

  int get ownCount => own.length;
  int get spouseCount => spouse.length;

  /// Prayers both completed, each within their own day. This is the couple's
  /// real shared signal across timezones: reachable no matter how far apart
  /// they are, unlike the old same-date-key intersection which could never
  /// match once the two devices disagreed about the date.
  Set<Prayer> get matched => own.intersection(spouse);
  int get matchedCount => matched.length;

  /// Whether the closest gap is small enough to describe as shared time.
  bool get sharedInTime =>
      closestGap != null && closestGap! <= kTogethernessWindow;
}

final prayerDaySummaryProvider = Provider<PrayerDaySummary>((ref) {
  final logs = ref.watch(prayerLogsForDayProvider).asData?.value ?? const [];
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return const PrayerDaySummary.empty();

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

  Duration? closest;
  for (final p in own.intersection(spouse)) {
    final delta = syncGap(a: ownTimes[p]!, b: spouseTimes[p]!);
    if (closest == null || delta < closest) closest = delta;
  }

  return PrayerDaySummary(own: own, spouse: spouse, closestGap: closest);
});

/// The spouse's prayer times for the day being shown, in her own zone.
///
/// Lets the UI distinguish "she has not prayed Isha" from "Isha is not due
/// where she is yet" — the single largest source of false impressions once the
/// two sides are on different clocks. Null when she has never set a location,
/// in which case the UI must fall back to making no claim about due-ness.
final spousePrayerTimesProvider = Provider<List<ScheduledPrayer>?>((ref) {
  final offset = ref.watch(prayerLogDayOffsetProvider);
  final spouse = ref.watch(spouseProfileProvider).asData?.value;
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  if (spouse == null || spouse.latitude == null || spouse.longitude == null) {
    return null;
  }
  return prayerTimesForDay(
    date: dayForOffset(tzId: spouse.timezone, offset: offset, at: now),
    loc: PrayerLocation(
      latitude: spouse.latitude!,
      longitude: spouse.longitude!,
      timezone: spouse.timezone,
    ),
    config: PrayerConfig(
      madhab: spouse.madhhab == 'hanafi' ? Madhab.hanafi : Madhab.shafi,
      method: calcMethodFromDb(spouse.calcMethod),
    ),
  );
});

/// Whether [prayer] has come due where the spouse is, at [now].
///
/// Conservative: with no schedule available it returns true, so the UI states
/// only what it can support rather than inventing a "not due yet" excuse.
bool isPrayerDueForSpouse({
  required Prayer prayer,
  required List<ScheduledPrayer>? schedule,
  required DateTime now,
}) {
  if (schedule == null) return true;
  for (final s in schedule) {
    if (s.prayer == prayer) return !s.at.isAfter(now);
  }
  return true;
}

/// Everything the header needs to describe both sides truthfully. Rebuilds on
/// every tick, so only the clock widget should watch it.
class PrayerDayView {
  const PrayerDayView({
    required this.ownTz,
    required this.spouseTz,
    required this.ownDay,
    required this.spouseDay,
    required this.now,
    required this.spouseName,
  });

  final String ownTz;
  final String? spouseTz;
  final DateTime ownDay;
  final DateTime? spouseDay;
  final DateTime now;
  final String? spouseName;

  /// True only when a spouse exists and her shown day differs from yours.
  /// Drives the adaptive header: identical days render one plain date line.
  bool get zonesDiffer =>
      spouseDay != null && dayKey(spouseDay!) != dayKey(ownDay);

  /// Signed offset of the spouse's zone relative to yours, e.g. `+10h`.
  String get offsetLabel => spouseTz == null
      ? ''
      : utcOffsetLabel(ownTz, spouseTz!, now);

  DateTime get ownLocalTime => localTimeAt(ownTz, now);
  DateTime? get spouseLocalTime =>
      spouseTz == null ? null : localTimeAt(spouseTz!, now);
}

final prayerDayViewProvider = Provider<PrayerDayView?>((ref) {
  final offset = ref.watch(prayerLogDayOffsetProvider);
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value;
  final spouse = ref.watch(spouseProfileProvider).asData?.value;
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  if (deviceTz == null) return null;

  return PrayerDayView(
    ownTz: deviceTz,
    spouseTz: spouse?.timezone,
    ownDay: dayForOffset(tzId: deviceTz, offset: offset, at: now),
    spouseDay: spouse == null
        ? null
        : dayForOffset(tzId: spouse.timezone, offset: offset, at: now),
    now: now,
    spouseName: spouse?.displayName,
  );
});

/// "Aisha is 10h ahead" / "Aisha is 5h 30m behind". Empty when the two zones
/// share a UTC offset, since there is then nothing to explain.
String spouseOffsetSentence(PrayerDayView view) {
  final label = view.offsetLabel;
  if (label.isEmpty) return '';
  final name = view.spouseName ?? 'Your spouse';
  final ahead = label.startsWith('+');
  return '$name is ${label.substring(1)} ${ahead ? 'ahead' : 'behind'}';
}

/// How far into her own day the spouse is, as a short human phrase — the piece
/// that stops "0 of 5" from reading as a failure when it is 1am where she is.
///
/// Returns an empty string when the two sides share a day (nothing to explain)
/// or when the shown day is not the current one.
String spouseDayProgressLabel({
  required PrayerDayView view,
  required int offset,
}) {
  if (offset != 0 || !view.zonesDiffer) return '';
  final local = view.spouseLocalTime;
  if (local == null) return '';
  final name = view.spouseName ?? 'Her';
  if (local.hour < 5) return "$name's day has only just begun";
  if (local.hour < 12) return "It's morning where $name is";
  if (local.hour < 17) return "It's afternoon where $name is";
  if (local.hour < 21) return "It's evening where $name is";
  return "$name's day is nearly over";
}

/// Writes a notification when the spouse logs a prayer, on ANY day. Diffs
/// `watchCouple`'s snapshots (keyed by user+prayer+date) so only genuinely
/// new check-ins fire, never the existing history a fresh subscription
/// loads, and never the user's own check-ins. Watched once from HomeScreen.
///
/// Deliberately uses `watchCouple`, not `watchDays`: prayer times are (and
/// should stay) anchored to each partner's own local calendar day, but that
/// means the two devices can legitimately disagree about what "today" is.
/// `watchDays` narrows each row to its owner's *shown* day, which would still
/// drop a check-in the viewer isn't currently looking at. `watchCouple` has no
/// date filter, so it can't drop a cross-timezone check-in.
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
  // That watch existed solely to force a daily re-subscribe, because the old
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
