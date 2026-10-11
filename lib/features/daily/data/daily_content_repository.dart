import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/daily_content.dart';

class DailyContentRepository {
  DailyContentRepository(this._client);

  final SupabaseClient _client;

  /// Fetches (creating if needed) today's verse / hadith for the caller's
  /// couple. Returns null values when the corresponding library is empty on
  /// the server.
  ///
  /// Both partners must be shown the same verse and hadith.
  /// `get_daily_content(p_date)` picks deterministically per
  /// `(couple_id, date)`, so if each device sent its own `DateTime.now()` as
  /// `p_date`, two partners in different timezones (or just past midnight
  /// for one of them) could disagree on the calendar day and be handed
  /// different content. So when no explicit [date] is requested we omit
  /// `p_date` from the RPC params altogether and let the server fall back to
  /// its own `coalesce(p_date, current_date)` -- one clock, shared by both
  /// partners. Callers wanting a specific day may still pass [date].
  ///
  /// The returned `question` is vestigial: the question of the day moved to
  /// a per-couple queue (`QuestionRepository.currentQuestion`) and nothing in
  /// this app reads this field any more. It is still hydrated for older
  /// builds; removing it is a separate follow-up. Since 20260803000001 the
  /// RPC only ever picks an `approved` question here, so the field can no
  /// longer leak an unreviewed or rejected one.
  Future<DailyContent> forDate([DateTime? date]) async {
    final params = <String, dynamic>{};
    if (date != null) {
      params['p_date'] =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    final rows = await _client.rpc('get_daily_content', params: params);
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
