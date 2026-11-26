import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/ameen_repository.dart';
import '../data/mood_store.dart';
import 'adhkar_providers.dart';
import 'dua_library_providers.dart';
import 'dua_suggestions.dart';

final ameenRepositoryProvider = Provider<AmeenRepository>(
  (ref) => AmeenRepository(ref.read(supabaseClientProvider)),
);

/// Who said Ameen today (this device's local day), keyed by user id.
final todayAmeensProvider = StreamProvider<Map<String, DateTime>>((ref) {
  final coupleId = ref.watch(
    currentCoupleProvider.select((c) => c.asData?.value?.id),
  );
  final today = ref.watch(adhkarTodayKeyProvider);
  if (coupleId == null || today == null) return Stream.value(const {});
  return ref
      .read(ameenRepositoryProvider)
      .watch(coupleId)
      .map((all) => {
            for (final a in all)
              if (a.day == today) a.userId: a.saidAt,
          });
});

final moodStoreProvider =
    Provider<MoodStore>((ref) => MoodStore(ref.read(secureStorageProvider)));

class TodayMood extends AsyncNotifier<Mood?> {
  @override
  Future<Mood?> build() async {
    final key = ref.watch(adhkarTodayKeyProvider);
    if (key == null) return null;
    return ref.read(moodStoreProvider).read(key);
  }

  Future<void> set(Mood? mood) async {
    final key = ref.read(adhkarTodayKeyProvider);
    if (key == null) return;
    state = AsyncData(mood);
    await ref.read(moodStoreProvider).write(key, mood);
  }
}

final todayMoodProvider =
    AsyncNotifierProvider<TodayMood, Mood?>(TodayMood.new);

final duaSuggestionsProvider = Provider<List<DuaSuggestion>>((ref) {
  final key = ref.watch(adhkarTodayKeyProvider);
  final library = ref.watch(duaLibraryProvider).asData?.value;
  final seed = ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (key == null || library == null || seed == null) return const [];
  final own = ref.watch(ownProfileProvider).asData?.value?.timezone;
  final spouse = ref.watch(spouseProfileProvider).asData?.value?.timezone;
  final p = key.split('-').map(int.parse).toList();
  return suggestDuas(
    mood: ref.watch(todayMoodProvider).asData?.value,
    today: DateTime(p[0], p[1], p[2]),
    events: ref.watch(upcomingEventsProvider),
    spouseAway: own != null && spouse != null && own != spouse,
    library: library,
    seed: seed,
  );
});
