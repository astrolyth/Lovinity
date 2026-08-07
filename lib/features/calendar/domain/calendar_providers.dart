import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/local_day.dart';
import '../../../core/time/tz_sync.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(ref.read(supabaseClientProvider));
});

/// Every event on the couple's calendar.
final calendarEventsProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(calendarRepositoryProvider).watchAll(coupleId: coupleId);
});

/// "Today" for the calendar, resolved in the viewer's own timezone.
///
/// A `Provider<String>` keyed on the day string rather than a raw `DateTime`:
/// it recomputes on the 30-second ticker but only notifies watchers when the
/// day actually rolls over, so the calendar doesn't rebuild twice a minute.
final calendarTodayKeyProvider = Provider<String>((ref) {
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value ?? 'UTC';
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  return dayKey(localDayAt(deviceTz, now));
});

/// An event paired with the specific date it next falls on.
class UpcomingEvent {
  const UpcomingEvent({required this.event, required this.date});

  final CalendarEvent event;

  /// The resolved next occurrence — for a recurring or Hijri-anchored event
  /// this is NOT `event.date`, which is only where the series started.
  final DateTime date;

  int daysFrom(DateTime today) =>
      DateTime(date.year, date.month, date.day)
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
}

/// Resolves every event to its next occurrence and sorts by that date.
///
/// One-off events already past drop out; recurring and Hijri-anchored events
/// resolve forward. Sorting on the stored `starts_at` instead would bury a
/// yearly anniversary created in 2019 at the bottom of the list forever.
List<UpcomingEvent> resolveUpcoming({
  required List<CalendarEvent> events,
  required DateTime today,
  int? limit,
}) {
  final resolved = <UpcomingEvent>[];
  for (final e in events) {
    final next = e.nextOccurrence(from: today);
    if (next == null) continue;
    resolved.add(UpcomingEvent(event: e, date: next));
  }
  resolved.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.event.title.compareTo(b.event.title);
  });
  if (limit != null && resolved.length > limit) {
    return resolved.sublist(0, limit);
  }
  return resolved;
}

/// Upcoming events, next occurrence first.
final upcomingEventsProvider = Provider<List<UpcomingEvent>>((ref) {
  final events = ref.watch(calendarEventsProvider).asData?.value ?? const [];
  final todayKey = ref.watch(calendarTodayKeyProvider);
  final today = DateTime.parse(todayKey);
  return resolveUpcoming(events: events, today: today);
});

/// Events occurring on a specific date, for the month grid and day sheet.
List<UpcomingEvent> eventsOnDate({
  required List<CalendarEvent> events,
  required DateTime date,
}) {
  final wanted = dayKey(date);
  return [
    for (final e in events)
      if (dayKey(e.nextOccurrence(from: date) ?? DateTime(1900)) == wanted)
        UpcomingEvent(event: e, date: date),
  ];
}

/// Notifies when the spouse adds an event. Watched once from HomeScreen.
final calendarNotificationPumpProvider = Provider<void>((ref) {
  // Scalar ids only: a token refresh or realtime reconnect rebuilding the
  // Couple object would otherwise re-baseline the detector and swallow the
  // partner activity this exists to surface.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<CalendarEvent>(
    keyOf: (e) => e.id,
    onNew: (event) {
      if (event.createdBy == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'calendar',
        title: 'Your partner added "${event.title}"',
        route: '/home/calendar',
      ));
    },
  );

  final sub = ref
      .read(calendarRepositoryProvider)
      .watchAll(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
