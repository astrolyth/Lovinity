import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/cycle_record.dart';

class CycleRepository {
  CycleRepository(this._client);
  final SupabaseClient _client;

  String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<CycleRecord> startCycle({
    required String userId,
    required String coupleId,
    required DateTime startedOn,
    String visibility = 'private',
  }) async {
    final row = await _client.from('cycle_records').insert({
      'user_id': userId,
      'couple_id': coupleId,
      'started_on': _d(startedOn),
      'visibility': visibility,
    }).select().single();
    return CycleRecord.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> endCycle({required String recordId, required DateTime endedOn}) async {
    await _client.from('cycle_records')
        .update({'ended_on': _d(endedOn)}).eq('id', recordId);
  }

  Future<void> setVisibility({required String recordId, required String visibility}) async {
    await _client.from('cycle_records')
        .update({'visibility': visibility}).eq('id', recordId);
  }

  Future<List<CycleRecord>> fetchHistory({required String userId}) async {
    final rows = await _client.from('cycle_records')
        .select().eq('user_id', userId).order('started_on', ascending: false);
    return [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Stream<List<CycleRecord>> watchOwn({required String userId}) {
    return _client.from('cycle_records').stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) => [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r))]
          ..sort((a, b) => b.startedOn.compareTo(a.startedOn)));
  }

  /// Both this user's own cycle records AND the spouse's `visibility:
  /// 'shared'` records for [coupleId]. RLS (see
  /// supabase/migrations/20260715000002_cycle_rls.sql) already restricts
  /// what this query can return to exactly that set -- a spouse's private
  /// record is never returned at the database layer.
  Stream<List<CycleRecord>> watchCoupleShared({required String coupleId}) {
    return _client
        .from('cycle_records')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) =>
            [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r))]);
  }

  /// Replaces [userId]'s moods for [day] (her local day key, `YYYY-MM-DD`).
  Future<void> setMoods({
    required String userId,
    required String coupleId,
    required String day,
    required Set<String> moods,
    required bool shared,
  }) => _client.from('cycle_moods').upsert({
    'user_id': userId,
    'couple_id': coupleId,
    'day': day,
    'moods': moods.toList(),
    'shared': shared,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'user_id,day');

  /// Recent mood days: her own, or the shared ones for her husband (RLS).
  Stream<List<CycleMood>> watchMoods({required String coupleId}) => _client
      .from('cycle_moods')
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .order('day')
      .limit(30)
      .map((rows) => [for (final r in rows) CycleMood.fromRow(r)]);
}

/// Mood chips for one day. Values are the db keys in [cycleMoodLabels].
class CycleMood {
  const CycleMood({
    required this.userId,
    required this.day,
    required this.moods,
    required this.shared,
  });
  final String userId;
  final String day;
  final Set<String> moods;
  final bool shared;

  factory CycleMood.fromRow(Map<String, dynamic> r) => CycleMood(
    userId: r['user_id'] as String,
    day: r['day'] as String,
    moods: {for (final m in r['moods'] as List? ?? const []) m as String},
    shared: r['shared'] as bool? ?? false,
  );
}

/// Db key -> chip label, in the design's order.
const cycleMoodLabels = {
  'calm': 'Calm',
  'energetic': 'Energetic',
  'tired': 'Tired',
  'cramps': 'Cramps',
  'headache': 'Headache',
  'low': 'Low mood',
};
