import 'package:supabase_flutter/supabase_flutter.dart';

enum AdhkarSet {
  morning('morning', 'Morning'),
  evening('evening', 'Evening'),
  afterPrayer('after_prayer', 'After salah');

  const AdhkarSet(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static AdhkarSet? fromDb(String v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return null;
  }
}

class AdhkarCompletion {
  const AdhkarCompletion({
    required this.userId,
    required this.localDate,
    required this.set,
    required this.completedAt,
  });
  final String userId;
  final String localDate;
  final AdhkarSet set;
  final DateTime completedAt;

  static AdhkarCompletion? fromRow(Map<String, dynamic> r) {
    final s = AdhkarSet.fromDb(r['set'] as String? ?? '');
    if (s == null) return null;
    return AdhkarCompletion(
      userId: r['user_id'] as String,
      localDate: r['local_date'] as String,
      set: s,
      completedAt: DateTime.parse(r['completed_at'] as String),
    );
  }
}

class AdhkarRepository {
  AdhkarRepository(this._client);
  final SupabaseClient _client;

  Stream<List<AdhkarCompletion>> watchRecent(String coupleId) {
    return _client
        .from('adhkar_completions')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('completed_at', ascending: false)
        .limit(20)
        .map((rows) => [
              for (final r in rows)
                ?AdhkarCompletion.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<void> complete({
    required String coupleId,
    required String userId,
    required String localDate,
    required AdhkarSet set,
  }) async {
    await _client.from('adhkar_completions').upsert(
      {
        'couple_id': coupleId,
        'user_id': userId,
        'local_date': localDate,
        'set': set.dbValue,
      },
      onConflict: 'user_id,local_date,set',
      ignoreDuplicates: true,
    );
  }
}
