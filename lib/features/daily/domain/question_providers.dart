import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/question_repository.dart';
import 'daily_content_providers.dart';

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(ref.read(supabaseClientProvider));
});

/// Live stream of answers for today's question in this couple. Empty when
/// no couple / no question yet.
final questionAnswersProvider =
    StreamProvider<List<QuestionAnswer>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final content = ref.watch(dailyContentProvider).asData?.value;
  if (couple == null || content?.question == null) {
    return const Stream.empty();
  }
  return ref.read(questionRepositoryProvider).watchAnswers(
        coupleId: couple.id,
        questionId: content!.question!.id,
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
  final questionId = ref
      .watch(dailyContentProvider.select((c) => c.asData?.value?.question?.id));
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
