import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/daily_content.dart';

class DailyContentRepository {
  DailyContentRepository(this._client);

  final SupabaseClient _client;

  /// Fetches (creating if needed) today's verse / hadith / question for the
  /// caller's couple. Returns null values when the corresponding library is
  /// empty on the server.
  Future<DailyContent> forDate([DateTime? date]) async {
    final d = date ?? DateTime.now();
    final rows = await _client.rpc(
      'get_daily_content',
      params: {
        'p_date':
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      },
    );
    final row = (rows is List) ? rows.first : rows;
    final map = Map<String, dynamic>.from(row as Map);

    VerseOfDay? verse;
    HadithOfDay? hadith;
    QuestionOfDay? question;

    final vId = map['verse_id'] as String?;
    final hId = map['hadith_id'] as String?;
    final qId = map['question_id'] as String?;

    if (vId != null) {
      final v = await _client.from('verses').select().eq('id', vId).maybeSingle();
      if (v != null) verse = VerseOfDay.fromRow(Map<String, dynamic>.from(v));
    }
    if (hId != null) {
      final h =
          await _client.from('hadiths').select().eq('id', hId).maybeSingle();
      if (h != null) hadith = HadithOfDay.fromRow(Map<String, dynamic>.from(h));
    }
    if (qId != null) {
      final q = await _client
          .from('daily_questions')
          .select()
          .eq('id', qId)
          .maybeSingle();
      if (q != null) {
        question = QuestionOfDay.fromRow(Map<String, dynamic>.from(q));
      }
    }

    return DailyContent(
      date: DateTime.parse(map['the_date'] as String),
      verse: verse,
      hadith: hadith,
      question: question,
    );
  }
}
