import 'package:supabase_flutter/supabase_flutter.dart';

/// A short study piece with a two-question check-in.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.body,
    required this.questions,
    this.category,
    this.arabicBody,
    this.reference,
  });

  final String id;
  final String title;
  final String? category;
  final String body;
  final String? arabicBody;

  /// Where the claim comes from. Present on every seeded lesson by design —
  /// these make religious claims, and an uncited one should be visible as such.
  final String? reference;

  /// Exactly two prompts, or none. Enforced by a check constraint in
  /// `20260808000001_lessons_checkin.sql`.
  final List<String> questions;

  bool get hasCheckIn => questions.length == 2;

  String get categoryLabel => switch (category) {
        'fiqh_marriage' => 'Fiqh of marriage',
        'seerah' => 'Seerah',
        'names_of_allah' => 'Names of Allah',
        _ => 'Lesson',
      };

  factory Lesson.fromRow(Map<String, dynamic> row) => Lesson(
        id: row['id'] as String,
        title: row['title'] as String,
        category: row['category'] as String?,
        body: row['body'] as String,
        arabicBody: row['arabic_body'] as String?,
        reference: row['reference'] as String?,
        questions: [
          for (final q in (row['questions'] as List? ?? const []))
            q.toString(),
        ],
      );
}

/// One spouse's answers to a lesson's check-in.
class LessonProgress {
  const LessonProgress({
    required this.userId,
    required this.lessonId,
    required this.answers,
    this.completedAt,
  });

  final String userId;
  final String lessonId;

  /// Keyed by question index as a string: `{"0": "...", "1": "..."}`.
  final Map<String, String> answers;
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;

  String? answerFor(int index) => answers['$index'];

  factory LessonProgress.fromRow(Map<String, dynamic> row) => LessonProgress(
        userId: row['user_id'] as String,
        lessonId: row['lesson_id'] as String,
        answers: {
          for (final e in (row['answers'] as Map? ?? const {}).entries)
            e.key.toString(): e.value?.toString() ?? '',
        },
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(row['completed_at'] as String),
      );
}

class LessonRepository {
  LessonRepository(this._client);

  final SupabaseClient _client;

  /// The lesson library.
  ///
  /// Only approved lessons are returned, and that is enforced by RLS
  /// (`learning_lessons_read`), not by this query — an unreviewed lesson making
  /// a religious claim must not be reachable even from a modified client.
  Future<List<Lesson>> fetchLessons() async {
    final rows = await _client
        .from('learning_lessons')
        .select()
        .order('category');
    return [
      for (final r in rows) Lesson.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Both spouses' progress.
  ///
  /// What arrives is already filtered server-side: your own rows always, your
  /// spouse's only once you have completed that same lesson. So a partner row
  /// appearing here IS the reveal — there is no client-side hiding to get
  /// wrong, and none that could be bypassed.
  Stream<List<LessonProgress>> watchProgress({required String coupleId}) {
    return _client
        .from('learning_progress')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                LessonProgress.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Records this user's answers and marks the lesson done for them.
  Future<void> submit({
    required String coupleId,
    required String userId,
    required String lessonId,
    required Map<String, String> answers,
  }) async {
    await _client.from('learning_progress').upsert(
      {
        'couple_id': coupleId,
        'user_id': userId,
        'lesson_id': lessonId,
        'answers': answers,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'couple_id,user_id,lesson_id',
    );
  }
}
