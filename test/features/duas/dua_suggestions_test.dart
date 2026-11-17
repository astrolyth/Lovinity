import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/calendar/data/calendar_repository.dart';
import 'package:lovinity/features/calendar/domain/calendar_providers.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/domain/dua_suggestions.dart';

LibraryDua _d(String id, List<String> tags, {String? category}) => LibraryDua(
      id: id,
      title: id,
      arabic: 'x',
      translation: 't',
      category: category,
      repeatCount: 1,
      tags: tags,
      sortOrder: 0,
    );

final _lib = [
  for (final t in [
    'distress', 'protection', 'grief', 'gratitude', 'sleep', 'dhikr',
    'fasting', 'travel', 'marriage',
  ])
    _d(t, [t]),
  _d('morning-dhikr', ['dhikr'], category: 'morning'),
];

UpcomingEvent _ev(String title, CalendarEventKind kind, DateTime date) =>
    UpcomingEvent(
      event: CalendarEvent(
        id: 'e',
        createdBy: 'me',
        title: title,
        startsAt: date,
        allDay: true,
        kind: kind,
        reminderOffsets: const [],
      ),
      date: date,
    );

List<DuaSuggestion> _s({
  Mood? mood,
  DateTime? today,
  List<UpcomingEvent> events = const [],
  bool away = false,
  List<LibraryDua>? lib,
}) =>
    suggestDuas(
      mood: mood,
      today: today ?? DateTime(2026, 11, 17), // Tuesday
      events: events,
      spouseAway: away,
      library: lib ?? _lib,
      seed: 'me',
    );

void main() {
  test('anxious mood', () {
    final r = _s(mood: Mood.anxious);
    expect(r.first.reason, "Because you're feeling anxious");
    expect(r.first.dua.tags.any(['distress', 'protection'].contains), isTrue);
  });

  test('Friday, Monday', () {
    expect(_s(today: DateTime(2026, 11, 20)).first.reason,
        startsWith("It's Jumu'ah"));
    expect(_s(today: DateTime(2026, 11, 16)).first.dua.tags, ['fasting']);
  });

  test('travel event tomorrow then mood sad', () {
    final r = _s(
      mood: Mood.sad,
      events: [_ev('Flight to Dubai', CalendarEventKind.event, DateTime(2026, 11, 18))],
    );
    expect(r.first.dua.tags, ['travel']);
    expect(r.first.reason, 'For the journey on Wednesday');
    expect(['grief', 'distress'], contains(r[1].dua.tags.first));
  });

  test('anniversary, birthday, far event', () {
    final t = DateTime(2026, 11, 17);
    expect(_s(events: [_ev('A', CalendarEventKind.anniversary, t)]).first.dua.tags,
        ['marriage']);
    expect(_s(events: [_ev('Sam', CalendarEventKind.birthday, t)]).first.reason,
        'For Sam');
    expect(
        _s(events: [_ev('A', CalendarEventKind.anniversary, DateTime(2026, 11, 25))])
            .first
            .reason,
        'A dua for today');
  });

  test('spouse away', () {
    expect(_s(away: true).first.reason, "While you're apart");
  });

  test('stable; empty; unwell fallback; no adhkar; max 3', () {
    expect(_s(mood: Mood.tired).map((e) => e.dua.id).toList(),
        _s(mood: Mood.tired).map((e) => e.dua.id).toList());
    expect(_s(lib: const []), isEmpty);
    final u = _s(mood: Mood.unwell, lib: [_d('d', ['distress'])]);
    expect(u.single.dua.id, 'd');
    expect(u.single.reason, "Because you're feeling unwell");
    final r = _s(
        mood: Mood.tired,
        away: true,
        events: [_ev('A', CalendarEventKind.anniversary, DateTime(2026, 11, 17))]);
    expect(r.length, 3);
    expect(r.every((e) => e.dua.category == null), isTrue);
  });

  test('fnv1a32', () => expect(fnv1a32('a'), 0xE40C292C));
}
