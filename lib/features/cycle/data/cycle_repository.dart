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
}
