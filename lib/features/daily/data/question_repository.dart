import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/daily_content.dart';

class QuestionAnswer {
  const QuestionAnswer({
    required this.id,
    required this.questionId,
    required this.authorId,
    required this.answer,
    required this.createdAt,
  });

  final String id;
  final String questionId;
  final String authorId;
  final String answer;
  final DateTime createdAt;

  factory QuestionAnswer.fromRow(Map<String, dynamic> row) => QuestionAnswer(
        id: row['id'] as String,
        questionId: row['question_id'] as String,
        authorId: row['author_id'] as String,
        answer: row['answer'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class QuestionRepository {
  QuestionRepository(this._client);
  final SupabaseClient _client;

  Future<List<QuestionAnswer>> answersFor({
    required String coupleId,
    required String questionId,
  }) async {
    final rows = await _client
        .from('question_answers')
        .select()
        .eq('couple_id', coupleId)
        .eq('question_id', questionId);
    return [
      for (final r in rows)
        QuestionAnswer.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Live stream of the couple's answers to one specific question. For UI
  /// that is showing that question; see [watchCoupleAnswers] for anything
  /// that must observe activity across a queue advance.
  Stream<List<QuestionAnswer>> watchAnswers({
    required String coupleId,
    required String questionId,
  }) {
    return watchCoupleAnswers(coupleId: coupleId)
        .map((answers) => [
              for (final a in answers)
                if (a.questionId == questionId) a,
            ]);
  }

  /// Live stream of ALL of [coupleId]'s question answers, with no
  /// question filter.
  ///
  /// The queue advances server-side the instant both partners have answered,
  /// but a client only re-reads which question is current on an explicit
  /// "Next question" tap. A subscription keyed on one question id therefore
  /// has to be torn down and re-opened whenever the client notices the
  /// advance -- and a fresh subscription's first emission is existing state,
  /// which `newRowDetector` deliberately absorbs as baseline. Any partner
  /// answer that landed in that window is swallowed permanently. The window
  /// is user-driven and unbounded: the partner can answer Q1, tap Next and
  /// answer Q2 hours before this device ever re-reads the queue.
  ///
  /// This stream is question-agnostic, so it never restarts on a queue
  /// advance and there is no re-baselining to lose an answer to. Use it for
  /// the notification pump; keep using [watchAnswers] for question-scoped UI.
  /// (Same shape as PrayerLogRepository.watchCouple vs watchDay.)
  Stream<List<QuestionAnswer>> watchCoupleAnswers({required String coupleId}) {
    return _client
        .from('question_answers')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                QuestionAnswer.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// The couple's current queue question — the first approved question they
  /// have not both answered. Null when they've answered every approved
  /// question (the generator in supabase/functions/generate-questions is
  /// what normally keeps that from happening).
  Future<QuestionOfDay?> currentQuestion() async {
    final rows = await _client.rpc('get_current_question');
    final list = (rows is List) ? rows : [rows];
    if (list.isEmpty || list.first == null) return null;
    return QuestionOfDay.fromRow(Map<String, dynamic>.from(list.first as Map));
  }

  Future<void> submit({
    required String coupleId,
    required String userId,
    required String questionId,
    required String answer,
  }) async {
    await _client.from('question_answers').upsert(
      {
        'couple_id': coupleId,
        'author_id': userId,
        'question_id': questionId,
        'answer': answer,
      },
      onConflict: 'couple_id,question_id,author_id',
    );
  }
}
