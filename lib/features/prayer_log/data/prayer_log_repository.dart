import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/prayer_log.dart';

class PrayerLogRepository {
  PrayerLogRepository(this._client);

  final SupabaseClient _client;

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fetch all prayer logs for [coupleId] on [date] (both spouses).
  Future<List<PrayerLogEntry>> fetchDay({
    required String coupleId,
    required DateTime date,
  }) async {
    final rows = await _client
        .from('prayer_logs')
        .select()
        .eq('couple_id', coupleId)
        .eq('date', _dateKey(date));
    return [
      for (final r in rows)
        PrayerLogEntry.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Live stream of prayer logs for [coupleId] on [date] — realtime updates
  /// when either spouse checks in.
  Stream<List<PrayerLogEntry>> watchDay({
    required String coupleId,
    required DateTime date,
  }) {
    final key = _dateKey(date);
    return _client
        .from('prayer_logs')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                if (r['date'] == key)
                  PrayerLogEntry.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Live stream of ALL of [coupleId]'s prayer logs, with no client-side
  /// date filter.
  ///
  /// Prayer times are anchored to each partner's own local calendar day (by
  /// product design, that's correct and unrelated to this method) -- but
  /// that means the two partners' devices can legitimately disagree about
  /// what "today" is (different timezones, or one device past midnight).
  /// `watchDay` filters rows down to one caller-supplied date key, so a
  /// partner's row written under a different date key is silently dropped
  /// and never reaches listeners. That's fine for the UI (which is showing
  /// one specific day), but wrong for anything that needs to observe the
  /// couple's activity regardless of which day either device thinks it is --
  /// e.g. the cross-device notification pump. Use this method for those
  /// cases; keep using `watchDay` for date-scoped UI.
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
        'date': _dateKey(date),
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
        .eq('date', _dateKey(date))
        .eq('prayer', prayer.dbName);
  }
}
