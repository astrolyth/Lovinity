import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/hijri_dates.dart';

/// What a calendar entry represents. Drives iconography and, for `islamic`,
/// the expectation that the event is Hijri-anchored.
enum CalendarEventKind { event, anniversary, birthday, islamic }

extension CalendarEventKindX on CalendarEventKind {
  String get dbValue => switch (this) {
        CalendarEventKind.event => 'event',
        CalendarEventKind.anniversary => 'anniversary',
        CalendarEventKind.birthday => 'birthday',
        CalendarEventKind.islamic => 'islamic',
      };

  String get label => switch (this) {
        CalendarEventKind.event => 'Event',
        CalendarEventKind.anniversary => 'Anniversary',
        CalendarEventKind.birthday => 'Birthday',
        CalendarEventKind.islamic => 'Islamic date',
      };

  static CalendarEventKind fromDb(String? value) => switch (value) {
        'anniversary' => CalendarEventKind.anniversary,
        'birthday' => CalendarEventKind.birthday,
        'islamic' => CalendarEventKind.islamic,
        _ => CalendarEventKind.event,
      };
}

/// A shared calendar entry.
///
/// Two anchoring modes, deliberately kept distinct:
///
///   * **Gregorian** — `startsAt` plus an optional `recurrence` RRULE. A civil
///     wedding anniversary lands on the same Gregorian date every year.
///   * **Hijri** — `hijriAnchor` set. The event recurs on its Islamic date and
///     therefore drifts against the Gregorian calendar. Deriving this from a
///     Gregorian date instead would silently re-anchor Eid to a fixed civil
///     day, which is wrong by roughly eleven days a year and compounding.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.createdBy,
    required this.title,
    required this.startsAt,
    required this.allDay,
    required this.kind,
    required this.reminderOffsets,
    this.description,
    this.endsAt,
    this.recurrence,
    this.hijriAnchor,
  });

  final String id;
  final String createdBy;
  final String title;
  final String? description;

  /// Raw stored instant. For all-day events this is UTC midnight and only its
  /// date fields are meaningful — read it through [date], never as a moment.
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String? recurrence;
  final HijriDay? hijriAnchor;
  final CalendarEventKind kind;
  final List<int> reminderOffsets;

  /// The event's calendar date.
  ///
  /// All-day events are read zone-free ([allDayDateFrom]) so an anniversary
  /// shows as the same day for both spouses. Timed events convert to the
  /// viewer's local zone, which is correct: a 7pm dinner really does happen at
  /// a different local time for a spouse in another country.
  DateTime get date => allDay
      ? allDayDateFrom(startsAt)
      : DateTime(
          startsAt.toLocal().year,
          startsAt.toLocal().month,
          startsAt.toLocal().day,
        );

  /// Hijri rendering of [date], for the dual-calendar label.
  HijriDay get hijriDate => hijriFromGregorian(date);

  /// The next calendar date this event falls on, at or after [from].
  ///
  /// Null when it is a one-off already in the past, or when the recurrence
  /// rule isn't one the app can expand.
  DateTime? nextOccurrence({required DateTime from}) {
    final anchor = hijriAnchor;
    if (anchor != null) {
      return nextHijriOccurrence(anchor: anchor, from: from);
    }
    return nextGregorianOccurrence(
      start: date,
      rrule: recurrence,
      from: from,
    );
  }

  bool get repeats => hijriAnchor != null || (recurrence?.isNotEmpty ?? false);

  factory CalendarEvent.fromRow(Map<String, dynamic> row) => CalendarEvent(
        id: row['id'] as String,
        createdBy: row['created_by'] as String,
        title: row['title'] as String,
        description: row['description'] as String?,
        startsAt: DateTime.parse(row['starts_at'] as String),
        endsAt: row['ends_at'] == null
            ? null
            : DateTime.parse(row['ends_at'] as String),
        allDay: row['all_day'] as bool? ?? false,
        recurrence: row['recurrence'] as String?,
        hijriAnchor: HijriDay.parse(row['hijri_anchor'] as String?),
        kind: CalendarEventKindX.fromDb(row['kind'] as String?),
        reminderOffsets: [
          for (final o in (row['reminder_offsets'] as List? ?? const []))
            (o as num).toInt(),
        ],
      );
}

class CalendarRepository {
  CalendarRepository(this._client);

  final SupabaseClient _client;

  /// Live stream of the couple's events, earliest stored date first.
  ///
  /// Streams the whole calendar rather than a date window: `.stream()` in this
  /// package version supports only a single equality-style filter, so a range
  /// cannot be expressed server-side, and recurring events would be wrongly
  /// excluded by one anyway — a yearly anniversary stored in 2019 still occurs
  /// next month. A couple's calendar is small enough that this is cheap.
  Stream<List<CalendarEvent>> watchAll({required String coupleId}) {
    return _client
        .from('calendar_events')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('starts_at')
        .map((rows) => [
              for (final r in rows)
                CalendarEvent.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<void> create({
    required String coupleId,
    required String userId,
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    bool allDay = false,
    String? recurrence,
    HijriDay? hijriAnchor,
    CalendarEventKind kind = CalendarEventKind.event,
    List<int> reminderOffsets = const [],
  }) async {
    await _client.from('calendar_events').insert({
      'couple_id': coupleId,
      'created_by': userId,
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'starts_at': _encodeStart(startsAt, allDay),
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      'all_day': allDay,
      if (recurrence != null && recurrence.isNotEmpty) 'recurrence': recurrence,
      if (hijriAnchor != null) 'hijri_anchor': hijriAnchor.key,
      'kind': kind.dbValue,
      'reminder_offsets': reminderOffsets,
    });
  }

  Future<void> update({
    required String id,
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    bool allDay = false,
    String? recurrence,
    HijriDay? hijriAnchor,
    CalendarEventKind kind = CalendarEventKind.event,
    List<int> reminderOffsets = const [],
  }) async {
    await _client.from('calendar_events').update({
      'title': title,
      'description': description,
      'starts_at': _encodeStart(startsAt, allDay),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'all_day': allDay,
      'recurrence': recurrence,
      'hijri_anchor': hijriAnchor?.key,
      'kind': kind.dbValue,
      'reminder_offsets': reminderOffsets,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('calendar_events').delete().eq('id', id);
  }

  /// All-day events are pinned to UTC midnight so both spouses read the same
  /// calendar day back out; timed events keep their real instant.
  String _encodeStart(DateTime startsAt, bool allDay) => allDay
      ? allDayInstant(startsAt).toIso8601String()
      : startsAt.toUtc().toIso8601String();
}
