// Resolving calendar events to their NEXT occurrence.
//
// The failure this guards against: sorting or filtering on the stored
// `starts_at` instead of the resolved occurrence. A yearly anniversary created
// in 2019 has a `starts_at` seven years in the past, so a naive sort buries it
// permanently at the bottom of "upcoming" and a naive date filter never shows
// it again at all — the event silently disappears from the couple's calendar.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/hijri_dates.dart';
import 'package:lovinity/features/calendar/data/calendar_repository.dart';
import 'package:lovinity/features/calendar/domain/calendar_providers.dart';

CalendarEvent _event({
  required String id,
  required String title,
  required DateTime startsAt,
  bool allDay = true,
  String? recurrence,
  HijriDay? hijriAnchor,
  CalendarEventKind kind = CalendarEventKind.event,
  String createdBy = 'him',
}) =>
    CalendarEvent(
      id: id,
      createdBy: createdBy,
      title: title,
      startsAt: allDay ? allDayInstant(startsAt) : startsAt,
      allDay: allDay,
      kind: kind,
      reminderOffsets: const [],
      recurrence: recurrence,
      hijriAnchor: hijriAnchor,
    );

void main() {
  final today = DateTime(2026, 8, 7);

  group('CalendarEvent.nextOccurrence', () {
    test('a past one-off has no next occurrence', () {
      final e = _event(
          id: '1', title: 'Dinner', startsAt: DateTime(2026, 1, 1));
      expect(e.nextOccurrence(from: today), isNull);
    });

    test('a future one-off resolves to its own date', () {
      final e = _event(
          id: '1', title: 'Dinner', startsAt: DateTime(2026, 9, 1));
      expect(e.nextOccurrence(from: today), DateTime(2026, 9, 1));
    });

    test('a yearly anniversary from years ago resolves forward', () {
      final e = _event(
        id: '1',
        title: 'Wedding',
        startsAt: DateTime(2019, 3, 14),
        recurrence: 'FREQ=YEARLY',
        kind: CalendarEventKind.anniversary,
      );
      expect(e.nextOccurrence(from: today), DateTime(2027, 3, 14));
    });

    test('a Hijri-anchored event ignores its stored Gregorian date', () {
      final e = _event(
        id: '1',
        title: 'Eid al-Fitr',
        startsAt: DateTime(2019, 6, 4),
        hijriAnchor: const HijriDay(1440, 10, 1),
        kind: CalendarEventKind.islamic,
      );
      final next = e.nextOccurrence(from: today);
      expect(next, isNotNull);
      expect(next!.isBefore(today), isFalse);
      // Resolved on the Islamic calendar, so it lands on 1 Shawwal.
      final h = hijriFromGregorian(next);
      expect(h.month, 10);
      expect(h.day, 1);
    });

    test('reports whether it repeats', () {
      expect(
        _event(id: '1', title: 'x', startsAt: today).repeats,
        isFalse,
      );
      expect(
        _event(
                id: '1',
                title: 'x',
                startsAt: today,
                recurrence: 'FREQ=YEARLY')
            .repeats,
        isTrue,
      );
      expect(
        _event(
                id: '1',
                title: 'x',
                startsAt: today,
                hijriAnchor: const HijriDay(1447, 10, 1))
            .repeats,
        isTrue,
      );
    });
  });

  group('CalendarEvent.date', () {
    test('an all-day event reads back the same calendar day', () {
      final e = _event(
          id: '1', title: 'Anniversary', startsAt: DateTime(2026, 3, 14));
      expect(e.date, DateTime(2026, 3, 14));
    });
  });

  group('resolveUpcoming', () {
    test('sorts by resolved occurrence, not by stored start', () {
      final events = [
        // Stored oldest, but recurs soonest.
        _event(
          id: 'anniversary',
          title: 'Wedding',
          startsAt: DateTime(2019, 8, 20),
          recurrence: 'FREQ=YEARLY',
        ),
        // Stored newest, but happens later.
        _event(id: 'trip', title: 'Trip', startsAt: DateTime(2026, 12, 1)),
        _event(id: 'dinner', title: 'Dinner', startsAt: DateTime(2026, 9, 5)),
      ];
      final upcoming = resolveUpcoming(events: events, today: today);
      expect(
        upcoming.map((u) => u.event.id),
        ['anniversary', 'dinner', 'trip'],
      );
    });

    test('drops past one-offs but keeps past recurring events', () {
      final events = [
        _event(id: 'gone', title: 'Old dinner', startsAt: DateTime(2020, 1, 1)),
        _event(
          id: 'kept',
          title: 'Birthday',
          startsAt: DateTime(2020, 1, 1),
          recurrence: 'FREQ=YEARLY',
        ),
      ];
      final upcoming = resolveUpcoming(events: events, today: today);
      expect(upcoming.map((u) => u.event.id), ['kept']);
    });

    test('includes an event occurring today', () {
      final events = [_event(id: 'now', title: 'Today', startsAt: today)];
      final upcoming = resolveUpcoming(events: events, today: today);
      expect(upcoming.single.date, today);
      expect(upcoming.single.daysFrom(today), 0);
    });

    test('honours a limit', () {
      final events = [
        for (var i = 1; i <= 5; i++)
          _event(
              id: '$i', title: 'E$i', startsAt: DateTime(2026, 9, i)),
      ];
      expect(resolveUpcoming(events: events, today: today, limit: 3).length, 3);
    });

    test('breaks date ties deterministically by title', () {
      final events = [
        _event(id: 'b', title: 'Beta', startsAt: DateTime(2026, 9, 1)),
        _event(id: 'a', title: 'Alpha', startsAt: DateTime(2026, 9, 1)),
      ];
      expect(
        resolveUpcoming(events: events, today: today).map((u) => u.event.title),
        ['Alpha', 'Beta'],
      );
    });
  });

  group('eventsOnDate', () {
    test('matches a recurring event on its resolved date', () {
      final events = [
        _event(
          id: 'anniversary',
          title: 'Wedding',
          startsAt: DateTime(2019, 3, 14),
          recurrence: 'FREQ=YEARLY',
        ),
      ];
      expect(
        eventsOnDate(events: events, date: DateTime(2027, 3, 14)).length,
        1,
      );
      expect(
        eventsOnDate(events: events, date: DateTime(2027, 3, 15)),
        isEmpty,
      );
    });

    test('does not surface a past one-off on an unrelated day', () {
      final events = [
        _event(id: 'gone', title: 'Old', startsAt: DateTime(2020, 1, 1)),
      ];
      expect(eventsOnDate(events: events, date: today), isEmpty);
    });
  });

  group('UpcomingEvent.daysFrom', () {
    test('counts whole days ahead', () {
      final e = _event(id: '1', title: 'x', startsAt: DateTime(2026, 8, 17));
      final u = UpcomingEvent(event: e, date: DateTime(2026, 8, 17));
      expect(u.daysFrom(today), 10);
    });
  });
}
