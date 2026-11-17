import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../core/time/local_day.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../data/dua_library_repository.dart';
import 'dua_search.dart';

enum Mood {
  grateful('Grateful'),
  anxious('Anxious'),
  sad('Sad'),
  tired('Tired'),
  unwell('Unwell');

  const Mood(this.label);
  final String label;
}

class DuaSuggestion {
  const DuaSuggestion(this.dua, this.reason);
  final LibraryDua dua;
  final String reason;
}

/// 32-bit FNV-1a over UTF-8, so picks match on every platform.
int fnv1a32(String s) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(s)) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

final _travel = RegExp(r'travel|trip|flight|journey', caseSensitive: false);

List<DuaSuggestion> suggestDuas({
  Mood? mood,
  required DateTime today,
  required List<UpcomingEvent> events,
  required bool spouseAway,
  required List<LibraryDua> library,
  required String seed,
}) {
  final pool = library.where((d) => !adhkarCategories.contains(d.category));
  final todayKey = dayKey(today);
  final tomorrowKey = dayKey(DateTime(today.year, today.month, today.day + 1));

  final triggers = <(List<String>, String)>[];
  for (final e in events) {
    final k = dayKey(e.date);
    if (k != todayKey && k != tomorrowKey) continue;
    final title = e.event.title;
    if (_travel.hasMatch(title)) {
      triggers.add((['travel'], 'For the journey on ${DateFormat('EEEE').format(e.date)}'));
    } else if (e.event.kind == CalendarEventKind.anniversary) {
      triggers.add((['marriage'], 'For your anniversary'));
    } else if (e.event.kind == CalendarEventKind.birthday) {
      triggers.add((['gratitude'], 'For $title'));
    }
  }
  if (spouseAway) triggers.add((['protection', 'travel'], "While you're apart"));
  if (mood != null) {
    final tags = switch (mood) {
      Mood.anxious => ['distress', 'protection'],
      Mood.sad => ['grief', 'distress'],
      Mood.grateful => ['gratitude'],
      Mood.unwell => ['illness', 'distress'],
      Mood.tired => ['sleep', 'dhikr'],
    };
    triggers.add((tags, "Because you're feeling ${mood.label.toLowerCase()}"));
  }
  if (today.weekday == DateTime.friday) {
    triggers.add((['dhikr'], "It's Jumu'ah — read Surah Al-Kahf and send salawat"));
  } else if (today.weekday == DateTime.monday || today.weekday == DateTime.thursday) {
    triggers.add((['fasting'], 'Monday & Thursday are Sunnah fasting days'));
  }
  triggers.add((['dhikr'], 'A dua for today'));

  final out = <DuaSuggestion>[];
  for (final (tags, reason) in triggers) {
    if (out.length == 3) break;
    final cands = pool
        .where((d) => d.tags.any(tags.contains) && !out.any((o) => o.dua.id == d.id))
        .toList();
    if (cands.isEmpty) continue;
    final i = fnv1a32('$seed|$todayKey|${tags.join(",")}') % cands.length;
    out.add(DuaSuggestion(cands[i], reason));
  }
  return out;
}
