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

/// Writes a notification when the spouse answers today's question. Diffs
/// the existing `questionAnswersProvider`'s snapshots (already scoped to
/// today's question for this couple) by author id, so it fires only for a
/// genuinely new partner answer -- never the user's own, never on the
/// first emission (existing history). Watched once from HomeScreen.
final questionNotificationPumpProvider = Provider<void>((ref) {
  // Narrowed to scalar ids/values so a token refresh (~hourly), a
  // couple-object rebuild (Couple has no operator==, and
  // SupabaseStreamBuilder refetches on every realtime reconnect), or a
  // DailyContent rebuild carrying the same question don't re-baseline the
  // detector below and swallow partner activity that happened while
  // backgrounded.
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  final questionId =
      ref.watch(currentQuestionProvider.select((q) => q.asData?.value?.id));
  if (selfId == null || coupleId == null || questionId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<QuestionAnswer>(
    keyOf: (a) => a.authorId,
    onNew: (answer) {
      if (answer.authorId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'question',
        title: "Your partner answered today's question",
        route: '/home/question',
      ));
    },
  );

  final sub = ref
      .read(questionRepositoryProvider)
      .watchAnswers(
        coupleId: coupleId,
        questionId: questionId,
      )
      .listen(detector);
  ref.onDispose(sub.cancel);
});
