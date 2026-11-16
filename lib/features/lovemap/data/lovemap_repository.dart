import 'package:supabase_flutter/supabase_flutter.dart';

/// A prompt in the "how well do you know your spouse?" library.
class LoveMapQuiz {
  const LoveMapQuiz({required this.id, required this.question, this.category});

  final String id;
  final String question;
  final String? category;

  String get categoryLabel => switch (category) {
        'deen' => 'Deen',
        'dreams' => 'Dreams',
        'history' => 'History',
        'preferences' => 'Preferences',
        _ => 'About you',
      };

  factory LoveMapQuiz.fromRow(Map<String, dynamic> row) => LoveMapQuiz(
        id: row['id'] as String,
        question: row['question'] as String,
        category: row['category'] as String?,
      );
}

/// What someone says about themselves — the answer a guess is measured against.
class LoveMapTruth {
  const LoveMapTruth({
    required this.quizId,
    required this.subjectId,
    required this.answer,
  });

  final String quizId;
  final String subjectId;
  final String answer;

  factory LoveMapTruth.fromRow(Map<String, dynamic> row) => LoveMapTruth(
        quizId: row['quiz_id'] as String,
        subjectId: row['subject_id'] as String,
        answer: row['answer'] as String,
      );
}

/// One player's guess at their spouse's answer.
class LoveMapGuess {
  const LoveMapGuess({
    required this.id,
    required this.quizId,
    required this.guesserId,
    required this.subjectId,
    required this.guess,
    this.isCorrect,
  });

  final String id;
  final String quizId;
  final String guesserId;
  final String? subjectId;
  final String guess;

  /// Null until the guesser grades it after the reveal.
  final bool? isCorrect;

  bool get isGraded => isCorrect != null;

  factory LoveMapGuess.fromRow(Map<String, dynamic> row) => LoveMapGuess(
        id: row['id'] as String,
        quizId: row['quiz_id'] as String,
        guesserId: row['guesser_id'] as String,
        subjectId: row['subject_id'] as String?,
        guess: row['guess'] as String,
        isCorrect: row['is_correct'] as bool?,
      );
}

class LoveMapRepository {
  LoveMapRepository(this._client);

  final SupabaseClient _client;

  /// The question library. Only approved rows come back — enforced by RLS
  /// (`love_map_quizzes_read`), so an unreviewed generated prompt cannot reach
  /// a couple.
  Future<List<LoveMapQuiz>> fetchQuizzes() async {
    final rows = await _client.from('love_map_quizzes').select();
    return [
      for (final r in rows)
        LoveMapQuiz.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Truths visible to this user.
  ///
  /// Your own always; your spouse's only once you have committed a guess for
  /// that question. That gate is in RLS (`love_map_truths_read`), not here —
  /// hiding the answer in the widget would leave it sitting on the device,
  /// readable by anyone willing to call the API, and the game would be
  /// pointless for exactly the person motivated to look.
  Stream<List<LoveMapTruth>> watchTruths({required String coupleId}) {
    return _client
        .from('love_map_truths')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                LoveMapTruth.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Stream<List<LoveMapGuess>> watchGuesses({required String coupleId}) {
    return _client
        .from('love_map_answers')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                LoveMapGuess.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Records what you say about yourself.
  Future<void> setTruth({
    required String coupleId,
    required String quizId,
    required String subjectId,
    required String answer,
  }) async {
    await _client.from('love_map_truths').upsert(
      {
        'couple_id': coupleId,
        'quiz_id': quizId,
        'subject_id': subjectId,
        'answer': answer,
      },
      onConflict: 'couple_id,quiz_id,subject_id',
    );
  }

  /// Commits a guess. This is what unlocks the spouse's truth for you, so it is
  /// deliberately one-way — there is no "edit my guess" once it is in.
  Future<void> submitGuess({
    required String coupleId,
    required String quizId,
    required String guesserId,
    required String subjectId,
    required String guess,
  }) async {
    await _client.from('love_map_answers').insert({
      'couple_id': coupleId,
      'quiz_id': quizId,
      'guesser_id': guesserId,
      'subject_id': subjectId,
      'guess': guess,
    });
  }

  /// The guesser marks their own guess right or wrong after the reveal.
  ///
  /// Self-graded rather than string-compared on purpose: "which surah does she
  /// turn to" has many correct spellings and transliterations, and an exact
  /// match would call a right answer wrong — which is worse than no score.
  Future<void> grade({required String guessId, required bool isCorrect}) async {
    await _client
        .from('love_map_answers')
        .update({'is_correct': isCorrect}).eq('id', guessId);
  }
}
