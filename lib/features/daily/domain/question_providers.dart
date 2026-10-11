import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/models/daily_content.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/question_repository.dart';

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(ref.read(supabaseClientProvider));
});

/// The couple's current queue question. Null when the queue is exhausted.
///
/// Deliberately NOT derived from `dailyContentProvider`: the question is a
/// joint activity that advances when both partners answer, not when the
/// calendar rolls over. Verse and hadith stay on dailyContentProvider.
///
/// Narrowed to the scalar couple id so a token refresh or a realtime
/// reconnect (which produces a new Couple object -- Couple has no
/// operator==) doesn't refetch and flicker the screen.
final currentQuestionProvider = FutureProvider<QuestionOfDay?>((ref) async {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return null;
  return ref.read(questionRepositoryProvider).currentQuestion();
});

/// Live stream of answers for the couple's current queue question. Empty when
/// no couple / no question yet.
final questionAnswersProvider =
    StreamProvider<List<QuestionAnswer>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  final questionId =
      ref.watch(currentQuestionProvider.select((q) => q.asData?.value?.id));
  if (coupleId == null || questionId == null) return const Stream.empty();
  return ref.read(questionRepositoryProvider).watchAnswers(
        coupleId: coupleId,
        questionId: questionId,
      );
});

/// Writes a notification when the spouse answers a queue question.
///
/// Opens its OWN subscription (`watchCoupleAnswers`) -- it does not share
/// `questionAnswersProvider`'s -- and diffs that subscription's snapshots by
/// question+author, so it fires only for a genuinely new partner answer:
/// never the user's own, and never on the first emission, which is existing
/// history the stream loads on subscribe.
///
/// Watched once from HomeScreen.
///
/// Deliberately question-AGNOSTIC, and deliberately NOT dependent on
/// `currentQuestionProvider`. The queue advances server-side the moment both
/// partners answer, but a client only re-reads it on an explicit "Next
/// question" tap. A pump keyed on the current question id would therefore
/// tear down and re-open its subscription whenever this device finally
/// noticed the advance -- and per `newRowDetector`'s "never fires on the
/// first emission" rule, any partner answer already present in the new
/// subscription's first snapshot is silently absorbed as baseline. That
/// window is user-driven and unbounded (answer Q1 in the morning; partner
/// answers Q1 at night, taps Next and answers Q2 immediately -- their Q2
/// answer is baselined away and never notifies), and it lands squarely on
/// the "one partner is more engaged" pattern. Dropping the question id from
/// the dependencies means the subscription never restarts on a queue
/// advance at all, which removes the re-baselining rather than narrowing it.
/// Same shape as prayerNotificationPumpProvider's watchCouple/watchDay split.
final questionNotificationPumpProvider = Provider<void>((ref) {
  // Narrowed to scalar ids so a token refresh (~hourly) or a couple-object
  // rebuild (Couple has no operator==, and SupabaseStreamBuilder refetches
  // on every realtime reconnect) doesn't re-baseline the detector below and
  // swallow partner activity that happened while backgrounded.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<QuestionAnswer>(
    // The question id is part of the key: this stream spans every question
    // the couple has ever answered, so keying on author alone would collide
    // all of one partner's answers onto a single key and only ever notify
    // for their first one.
    keyOf: (a) => '${a.questionId}:${a.authorId}',
    onNew: (answer) {
      if (answer.authorId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'question',
        title: 'Your partner answered your question',
        route: '/home/question',
      ));
    },
  );

  final sub = ref
      .read(questionRepositoryProvider)
      .watchCoupleAnswers(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
