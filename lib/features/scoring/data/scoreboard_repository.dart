import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/models/prayer_log.dart';
import '../domain/score_engine.dart';

class ScoreboardRepository {
  ScoreboardRepository(this._client);
  final SupabaseClient _client;

  String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<DayLog>> fetchDayLogs({
    required String coupleId,
    required String userId,
    required DateTime from,
    required DateTime toInclusive,
  }) async {
    final rows = await _client
        .from('prayer_logs')
        .select()
        .eq('couple_id', coupleId)
        .eq('user_id', userId)
        .gte('date', _d(from))
        .lte('date', _d(toInclusive));
    final byDate = <String, Set<Prayer>>{};
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      if ((m['status'] as String) != 'prayed') continue;
      final entry = PrayerLogEntry.fromRow(m);
      final key = _d(entry.date);
      (byDate[key] ??= <Prayer>{}).add(entry.prayer);
    }
    return [
      for (final e in byDate.entries)
        DayLog(date: DateTime.parse(e.key), prayed: e.value),
    ];
  }

  Future<List<CycleRecord>> fetchCycles({
    required String userId,
    required DateTime from,
    required DateTime toInclusive,
  }) async {
    final rows = await _client
        .from('cycle_records')
        .select()
        .eq('user_id', userId)
        .lte('started_on', _d(toInclusive));
    return [
      for (final r in rows)
        CycleRecord.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
