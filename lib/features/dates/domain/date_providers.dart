import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/date_repository.dart';

final dateRepositoryProvider = Provider<DateRepository>((ref) {
  return DateRepository(ref.read(supabaseClientProvider));
});

final dateIdeasProvider = FutureProvider<List<DateIdea>>((ref) {
  return ref.read(dateRepositoryProvider).fetchIdeas();
});

final dateSavesProvider = StreamProvider<List<DateSave>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(dateRepositoryProvider).watchSaves(coupleId: coupleId);
});

/// Which setting the browser is filtered to. Null shows everything.
class DateSettingFilter extends Notifier<DateSetting?> {
  @override
  DateSetting? build() => null;

  void toggle(DateSetting setting) =>
      state = state == setting ? null : setting;
}

final dateSettingFilterProvider =
    NotifierProvider<DateSettingFilter, DateSetting?>(DateSettingFilter.new);

/// An idea with the couple's save state attached.
class DateIdeaEntry {
  const DateIdeaEntry({required this.idea, this.save});

  final DateIdea idea;
  final DateSave? save;

  bool get isSaved => save != null;
  bool get isPlanned => save?.isPlanned ?? false;
  bool get isDone => save?.isDone ?? false;
}

List<DateIdeaEntry> buildEntries({
  required List<DateIdea> ideas,
  required List<DateSave> saves,
  DateSetting? filter,
}) {
  final byIdea = {for (final s in saves) s.ideaId: s};
  return [
    for (final idea in ideas)
      if (filter == null || idea.setting == filter)
        DateIdeaEntry(idea: idea, save: byIdea[idea.id]),
  ];
}

final dateEntriesProvider = Provider<List<DateIdeaEntry>>((ref) {
  final ideas = ref.watch(dateIdeasProvider).asData?.value ?? const [];
  final saves = ref.watch(dateSavesProvider).asData?.value ?? const [];
  final filter = ref.watch(dateSettingFilterProvider);
  return buildEntries(ideas: ideas, saves: saves, filter: filter);
});

/// Saved ideas that have a date set and have not happened yet.
final plannedDatesProvider = Provider<List<DateIdeaEntry>>((ref) {
  final entries = buildEntries(
    ideas: ref.watch(dateIdeasProvider).asData?.value ?? const [],
    saves: ref.watch(dateSavesProvider).asData?.value ?? const [],
  );
  final planned = [
    for (final e in entries)
      if (e.isPlanned) e,
  ];
  planned.sort((a, b) => a.save!.plannedFor!.compareTo(b.save!.plannedFor!));
  return planned;
});

/// Notifies when the spouse saves an idea — the "shall we do this?" signal.
final dateNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<DateSave>(
    keyOf: (s) => s.id,
    onNew: (save) {
      if (save.savedBy == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'date',
        title: 'Your partner saved a date idea',
        route: '/home/dates',
      ));
    },
  );

  final sub = ref
      .read(dateRepositoryProvider)
      .watchSaves(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
