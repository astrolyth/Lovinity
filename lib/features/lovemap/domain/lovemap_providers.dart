import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/lovemap_repository.dart';

final loveMapRepositoryProvider = Provider<LoveMapRepository>((ref) {
  return LoveMapRepository(ref.read(supabaseClientProvider));
});

final loveMapQuizzesProvider = FutureProvider<List<LoveMapQuiz>>((ref) {
  return ref.read(loveMapRepositoryProvider).fetchQuizzes();
});

final loveMapTruthsProvider = StreamProvider<List<LoveMapTruth>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(loveMapRepositoryProvider).watchTruths(coupleId: coupleId);
});

final loveMapGuessesProvider = StreamProvider<List<LoveMapGuess>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(loveMapRepositoryProvider).watchGuesses(coupleId: coupleId);
});

/// Where one question stands for this couple.
class LoveMapRound {
  const LoveMapRound({
    required this.quiz,
    this.ownTruth,
    this.myGuess,
    this.spouseTruth,
  });

  final LoveMapQuiz quiz;

  /// What you have said about yourself, for your spouse to guess.
  final LoveMapTruth? ownTruth;

  /// Your guess at your spouse's answer.
  final LoveMapGuess? myGuess;

  /// Your spouse's actual answer. Present only after you have guessed —
  /// the server will not return it before that.
  final LoveMapTruth? spouseTruth;

  bool get hasAnsweredAboutSelf => ownTruth != null;
  bool get hasGuessed => myGuess != null;

  /// You guessed, and their answer is available to compare against.
  bool get revealed => hasGuessed && spouseTruth != null;

  /// You guessed, but they have not recorded their own answer yet.
  ///
  /// Indistinguishable at the API level from "hidden", which is fine: both
  /// mean there is nothing to show, and the UI says so plainly rather than
  /// implying they answered and you are being kept out.
  bool get waitingOnSpouse => hasGuessed && spouseTruth == null;

  bool get needsGrading => revealed && !(myGuess?.isGraded ?? false);
}

List<LoveMapRound> buildRounds({
  required List<LoveMapQuiz> quizzes,
  required List<LoveMapTruth> truths,
  required List<LoveMapGuess> guesses,
  required String selfId,
  required String? spouseId,
}) {
  return [
    for (final quiz in quizzes)
      LoveMapRound(
        quiz: quiz,
        ownTruth: truths
            .where((t) => t.quizId == quiz.id && t.subjectId == selfId)
            .firstOrNull,
        spouseTruth: spouseId == null
            ? null
            : truths
                .where((t) => t.quizId == quiz.id && t.subjectId == spouseId)
                .firstOrNull,
        myGuess: guesses
            .where((g) => g.quizId == quiz.id && g.guesserId == selfId)
            .firstOrNull,
      ),
  ];
}

final loveMapRoundsProvider = Provider<List<LoveMapRound>>((ref) {
  final quizzes = ref.watch(loveMapQuizzesProvider).asData?.value ?? const [];
  final truths = ref.watch(loveMapTruthsProvider).asData?.value ?? const [];
  final guesses = ref.watch(loveMapGuessesProvider).asData?.value ?? const [];
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (selfId == null) return const [];
  return buildRounds(
    quizzes: quizzes,
    truths: truths,
    guesses: guesses,
    selfId: selfId,
    spouseId: couple?.spouseOf(selfId),
  );
});

/// How many graded guesses you got right, out of how many you have graded.
class LoveMapScore {
  const LoveMapScore({required this.correct, required this.graded});

  final int correct;
  final int graded;

  int get percent => graded == 0 ? 0 : ((correct / graded) * 100).round();
}

LoveMapScore scoreOf(List<LoveMapRound> rounds) {
  var correct = 0;
  var graded = 0;
  for (final r in rounds) {
    final guess = r.myGuess;
    if (guess == null || !guess.isGraded) continue;
    graded++;
    if (guess.isCorrect == true) correct++;
  }
  return LoveMapScore(correct: correct, graded: graded);
}

final loveMapScoreProvider = Provider<LoveMapScore>((ref) {
  return scoreOf(ref.watch(loveMapRoundsProvider));
});

/// Notifies when the spouse guesses one of your answers.
final loveMapNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<LoveMapGuess>(
    keyOf: (g) => g.id,
    onNew: (guess) {
      if (guess.guesserId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'lovemap',
        title: 'Your partner made a guess about you',
        route: '/home/lovemap',
      ));
    },
  );

  final sub = ref
      .read(loveMapRepositoryProvider)
      .watchGuesses(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
