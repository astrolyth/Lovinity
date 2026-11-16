import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/lesson_repository.dart';

final lessonRepositoryProvider = Provider<LessonRepository>((ref) {
  return LessonRepository(ref.read(supabaseClientProvider));
});

final lessonsProvider = FutureProvider<List<Lesson>>((ref) {
  return ref.read(lessonRepositoryProvider).fetchLessons();
});

final lessonProgressProvider =
    StreamProvider<List<LessonProgress>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(lessonRepositoryProvider).watchProgress(coupleId: coupleId);
});

/// Where a couple stands on one lesson.
class LessonState {
  const LessonState({required this.own, required this.spouse});

  final LessonProgress? own;

  /// Null until the reveal. Because the server withholds the spouse's row
  /// until you have completed the lesson, a non-null value here already means
  /// "you have both answered" — the UI never has to decide whether it is
  /// allowed to show this.
  final LessonProgress? spouse;

  bool get ownDone => own?.isComplete ?? false;
  bool get revealed => ownDone && (spouse?.isComplete ?? false);

  /// You are done and your spouse is not — or has not been revealed yet.
  bool get waitingForSpouse => ownDone && !revealed;
}

LessonState lessonStateFor({
  required List<LessonProgress> progress,
  required String lessonId,
  required String selfId,
}) {
  LessonProgress? own;
  LessonProgress? spouse;
  for (final p in progress) {
    if (p.lessonId != lessonId) continue;
    if (p.userId == selfId) {
      own = p;
    } else {
      spouse = p;
    }
  }
  return LessonState(own: own, spouse: spouse);
}

final lessonStateProvider =
    Provider.family<LessonState, String>((ref, lessonId) {
  final progress = ref.watch(lessonProgressProvider).asData?.value ?? const [];
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (selfId == null) {
    return const LessonState(own: null, spouse: null);
  }
  return lessonStateFor(
    progress: progress,
    lessonId: lessonId,
    selfId: selfId,
  );
});

/// Lessons the current user has finished.
final completedLessonCountProvider = Provider<int>((ref) {
  final progress = ref.watch(lessonProgressProvider).asData?.value ?? const [];
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (selfId == null) return 0;
  return progress
      .where((p) => p.userId == selfId && p.isComplete)
      .length;
});

/// Notifies when the spouse's answers become visible.
///
/// A partner row can only reach this device once the reveal condition is met,
/// so a new row here always means "you can now read what they wrote" — never
/// "they answered but you cannot see it", which would be a frustrating thing
/// to be told.
final learningNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<LessonProgress>(
    keyOf: (p) => '${p.userId}:${p.lessonId}',
    onNew: (progress) {
      if (progress.userId == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'learning',
        title: 'Your partner\'s answers are ready to read',
        route: '/home/learn',
      ));
    },
  );

  final sub = ref
      .read(lessonRepositoryProvider)
      .watchProgress(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
