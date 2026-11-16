import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/dates/data/date_repository.dart';
import 'package:lovinity/features/dates/domain/date_providers.dart';
import 'package:lovinity/features/learning/data/lesson_repository.dart';
import 'package:lovinity/features/learning/domain/learning_providers.dart';
import 'package:lovinity/features/lovemap/data/lovemap_repository.dart';
import 'package:lovinity/features/lovemap/domain/lovemap_providers.dart';

DateIdea _idea(String id, DateSetting setting) => DateIdea(
      id: id,
      title: 'Idea $id',
      description: 'desc',
      setting: setting,
      effort: 'low',
      costBand: 'free',
    );

DateSave _save(
  String id,
  String ideaId, {
  DateTime? plannedFor,
  DateTime? completedAt,
}) =>
    DateSave(
      id: id,
      ideaId: ideaId,
      savedBy: 'him',
      plannedFor: plannedFor,
      completedAt: completedAt,
    );

void main() {
  group('buildEntries', () {
    final ideas = [
      _idea('a', DateSetting.home),
      _idea('b', DateSetting.out),
      _idea('c', DateSetting.virtual),
    ];

    test('attaches the couple\'s save state to each idea', () {
      final entries =
          buildEntries(ideas: ideas, saves: [_save('s1', 'b')]);
      expect(entries.firstWhere((e) => e.idea.id == 'b').isSaved, isTrue);
      expect(entries.firstWhere((e) => e.idea.id == 'a').isSaved, isFalse);
    });

    test('filters by setting', () {
      final virtual = buildEntries(
          ideas: ideas, saves: const [], filter: DateSetting.virtual);
      expect(virtual.map((e) => e.idea.id), ['c']);
    });

    test('a null filter shows everything', () {
      expect(buildEntries(ideas: ideas, saves: const []).length, 3);
    });

    test('distinguishes planned from done', () {
      final planned = buildEntries(
        ideas: ideas,
        saves: [_save('s1', 'a', plannedFor: DateTime(2026, 9, 1))],
      ).firstWhere((e) => e.idea.id == 'a');
      expect(planned.isPlanned, isTrue);
      expect(planned.isDone, isFalse);

      final done = buildEntries(
        ideas: ideas,
        saves: [
          _save('s1', 'a',
              plannedFor: DateTime(2026, 9, 1),
              completedAt: DateTime(2026, 9, 2)),
        ],
      ).firstWhere((e) => e.idea.id == 'a');
      expect(done.isPlanned, isFalse,
          reason: 'a completed date is no longer upcoming');
      expect(done.isDone, isTrue);
    });

    test('virtual ideas exist, so long-distance couples are served', () {
      final virtual = buildEntries(
          ideas: ideas, saves: const [], filter: DateSetting.virtual);
      expect(virtual, isNotEmpty);
    });
  });

  group('love map rounds', () {
    const quiz = LoveMapQuiz(id: 'q1', question: 'Favourite surah?');

    LoveMapGuess guess({bool? correct}) => LoveMapGuess(
          id: 'g1',
          quizId: 'q1',
          guesserId: 'him',
          subjectId: 'her',
          guess: 'ar-Rahman',
          isCorrect: correct,
        );

    test('nothing revealed before guessing', () {
      final round = buildRounds(
        quizzes: const [quiz],
        truths: const [
          LoveMapTruth(quizId: 'q1', subjectId: 'him', answer: 'al-Kahf'),
        ],
        guesses: const [],
        selfId: 'him',
        spouseId: 'her',
      ).single;
      expect(round.hasAnsweredAboutSelf, isTrue);
      expect(round.hasGuessed, isFalse);
      expect(round.revealed, isFalse);
    });

    test('revealed once guessed and the spouse truth is present', () {
      final round = buildRounds(
        quizzes: const [quiz],
        truths: const [
          LoveMapTruth(quizId: 'q1', subjectId: 'her', answer: 'ad-Duha'),
        ],
        guesses: [guess()],
        selfId: 'him',
        spouseId: 'her',
      ).single;
      expect(round.revealed, isTrue);
      expect(round.needsGrading, isTrue);
      expect(round.spouseTruth!.answer, 'ad-Duha');
    });

    test('guessed but the spouse has not answered reads as waiting', () {
      final round = buildRounds(
        quizzes: const [quiz],
        truths: const [],
        guesses: [guess()],
        selfId: 'him',
        spouseId: 'her',
      ).single;
      expect(round.waitingOnSpouse, isTrue);
      expect(round.revealed, isFalse);
      expect(round.needsGrading, isFalse,
          reason: 'nothing to grade against yet');
    });

    test('graded rounds no longer need grading', () {
      final round = buildRounds(
        quizzes: const [quiz],
        truths: const [
          LoveMapTruth(quizId: 'q1', subjectId: 'her', answer: 'ad-Duha'),
        ],
        guesses: [guess(correct: false)],
        selfId: 'him',
        spouseId: 'her',
      ).single;
      expect(round.needsGrading, isFalse);
    });
  });

  group('love map score', () {
    LoveMapRound round(String id, {bool? correct}) => LoveMapRound(
          quiz: LoveMapQuiz(id: id, question: 'q'),
          myGuess: LoveMapGuess(
            id: 'g$id',
            quizId: id,
            guesserId: 'him',
            subjectId: 'her',
            guess: 'x',
            isCorrect: correct,
          ),
        );

    test('counts only graded guesses', () {
      final score = scoreOf([
        round('1', correct: true),
        round('2', correct: false),
        round('3'), // ungraded
      ]);
      expect(score.graded, 2);
      expect(score.correct, 1);
      expect(score.percent, 50);
    });

    test('is zero, not a division error, with nothing graded', () {
      final score = scoreOf([round('1')]);
      expect(score.graded, 0);
      expect(score.percent, 0);
    });
  });

  group('lesson state', () {
    LessonProgress progress(String userId, {bool complete = true}) =>
        LessonProgress(
          userId: userId,
          lessonId: 'l1',
          answers: const {'0': 'a', '1': 'b'},
          completedAt: complete ? DateTime(2026, 8, 8) : null,
        );

    test('not revealed when only you have answered', () {
      final state = lessonStateFor(
        progress: [progress('him')],
        lessonId: 'l1',
        selfId: 'him',
      );
      expect(state.ownDone, isTrue);
      expect(state.revealed, isFalse);
      expect(state.waitingForSpouse, isTrue);
    });

    test('revealed when both rows are present and complete', () {
      final state = lessonStateFor(
        progress: [progress('him'), progress('her')],
        lessonId: 'l1',
        selfId: 'him',
      );
      expect(state.revealed, isTrue);
      expect(state.waitingForSpouse, isFalse);
    });

    test('ignores other lessons', () {
      final state = lessonStateFor(
        progress: [
          LessonProgress(
            userId: 'him',
            lessonId: 'other',
            answers: const {},
            completedAt: DateTime(2026, 8, 8),
          ),
        ],
        lessonId: 'l1',
        selfId: 'him',
      );
      expect(state.ownDone, isFalse);
    });
  });
}
