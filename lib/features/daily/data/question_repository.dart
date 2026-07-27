import 'package:supabase_flutter/supabase_flutter.dart';

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

  Stream<List<QuestionAnswer>> watchAnswers({
    required String coupleId,
    required String questionId,
  }) {
    return _client
        .from('question_answers')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                if (r['question_id'] == questionId)
                  QuestionAnswer.fromRow(Map<String, dynamic>.from(r)),
            ]);
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
