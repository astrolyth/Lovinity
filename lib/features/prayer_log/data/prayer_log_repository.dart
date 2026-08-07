import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/local_day.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/prayer_log.dart';

class PrayerLogRepository {
  PrayerLogRepository(this._client);

  final SupabaseClient _client;

  /// Live stream of the couple's prayer logs, filtered **per owner**.
  ///
  /// [dayKeyByUserId] maps each user id to the `YYYY-MM-DD` key of the day
  /// being shown *for that user*. A row survives only if it matches its own
  /// owner's key, so one snapshot can carry two different calendar days at
  /// once — which is the whole point.
  ///
  /// This replaced a `watchDay(date)` that applied ONE caller-supplied key to
  /// both spouses. Ṣalāt is anchored to the worshipper's own local day, so
  /// whenever the two devices sat in different zones (Toronto 3pm Thursday is
  /// Dhaka 1am Friday) the partner's rows carried a different key and were
  /// silently discarded. The UI then rendered a confident "Not yet" for
  /// prayers she had already completed, and `own ∩ spouse` could never
  /// intersect, so "Both prayed" was unreachable. Dropping a row is
  /// indistinguishable from her not having prayed — the failure was a false
  /// statement, not a missing one.
  ///
  /// Rows whose owner is absent from [dayKeyByUserId] are dropped: with no
  /// anchor for that user there is no honest day to file them under.
  Stream<List<PrayerLogEntry>> watchDays({
    required String coupleId,
    required Map<String, String> dayKeyByUserId,
  }) {
    return watchCouple(coupleId: coupleId).map((entries) => [
          for (final e in entries)
            if (dayKeyByUserId[e.userId] == e.dateKey) e,
        ]);
  }

  /// Live stream of ALL of [coupleId]'s prayer logs, with no client-side
  /// date filter.
  ///
  /// Prayer times are anchored to each partner's own local calendar day (by
  /// product design, that's correct and unrelated to this method) -- but
  /// that means the two partners' devices can legitimately disagree about
  /// what "today" is (different timezones, or one device past midnight).
  /// [watchDays] narrows each row to its own owner's day, which is right for
  /// date-scoped UI but still excludes anything outside the shown days. Use
  /// this method for anything that must observe the couple's activity
  /// regardless of which day either device thinks it is -- e.g. the
  /// cross-device notification pump.
  ///
  /// [watchDays] is layered on top of this stream rather than opening its own
  /// subscription, so the date-scoped UI and the pump share one socket.
  Stream<List<PrayerLogEntry>> watchCouple({required String coupleId}) {
    return _client
        .from('prayer_logs')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                PrayerLogEntry.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Writes a check-in under [date], which MUST be the logging user's own
  /// local calendar day — resolved from the device zone, not from a partner's
  /// or a shared anchor. That day is the key the spouse's device will use to
  /// find this row (see `core/time/local_day.dart`); filing it under anyone
  /// else's day makes the row unfindable and the log silently wrong.
  Future<void> logPrayer({
    required String coupleId,
    required String userId,
    required DateTime date,
    required Prayer prayer,
    PrayerStatus status = PrayerStatus.prayed,
  }) async {
    await _client.from('prayer_logs').upsert(
      {
        'couple_id': coupleId,
        'user_id': userId,
        'date': dayKey(date),
        'prayer': prayer.dbName,
        'status': status.dbValue,
        'time_logged': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'couple_id,user_id,date,prayer',
    );
  }

  Future<void> unlogPrayer({
    required String coupleId,
    required String userId,
    required DateTime date,
    required Prayer prayer,
  }) async {
    await _client
        .from('prayer_logs')
        .delete()
        .eq('couple_id', coupleId)
        .eq('user_id', userId)
        .eq('date', dayKey(date))
        .eq('prayer', prayer.dbName);
  }
}
