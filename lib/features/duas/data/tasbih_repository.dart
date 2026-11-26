import 'package:supabase_flutter/supabase_flutter.dart';

class DhikrCounter {
  const DhikrCounter({
    required this.id,
    required this.title,
    required this.arabicText,
    required this.target,
    required this.period,
    required this.startsAt,
  });

  final String id;
  final String title;
  final String? arabicText;
  final int target;
  final String period;
  final DateTime startsAt;

  factory DhikrCounter.fromRow(Map<String, dynamic> r) => DhikrCounter(
        id: r['id'] as String,
        title: r['title'] as String,
        arabicText: r['arabic_text'] as String?,
        target: r['target'] as int,
        period: r['period'] as String,
        startsAt: DateTime.parse(r['starts_at'] as String),
      );
}

class CounterTotals {
  const CounterTotals({required this.mine, required this.spouse});
  final int mine;
  final int spouse;
  int get total => mine + spouse;
}

class TasbihRepository {
  TasbihRepository(this._client);
  final SupabaseClient _client;

  Stream<List<DhikrCounter>> watchCounters(String coupleId) {
    return _client
        .from('dhikr_counters')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .map((rows) => [
              for (final r in rows)
                DhikrCounter.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<void> create({
    required String coupleId,
    required String title,
    String? arabicText,
    required int target,
    required String period,
  }) async {
    await _client.from('dhikr_counters').insert({
      'couple_id': coupleId,
      'title': title,
      if (arabicText != null && arabicText.isNotEmpty) 'arabic_text': arabicText,
      'target': target,
      'period': period,
    });
  }

  Future<void> addContribution({
    required String counterId,
    required String coupleId,
    required String userId,
    required int count,
  }) async {
    await _client.from('dhikr_contributions').insert({
      'counter_id': counterId,
      'couple_id': coupleId,
      'user_id': userId,
      'count': count,
    });
  }

  Future<CounterTotals> totals(String counterId, {required String selfId}) async {
    final rows = await _client
        .rpc('dhikr_counter_totals', params: {'p_counter_id': counterId}) as List;
    var mine = 0;
    var spouse = 0;
    for (final r in rows) {
      final n = (r['total'] as num).toInt();
      if (r['user_id'] == selfId) {
        mine += n;
      } else {
        spouse += n;
      }
    }
    return CounterTotals(mine: mine, spouse: spouse);
  }
}
