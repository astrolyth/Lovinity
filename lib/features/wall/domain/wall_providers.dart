import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/link_preview_service.dart';
import '../data/wall_repository.dart';
import 'wall_logic.dart';
import 'wall_models.dart';

final wallRepositoryProvider = Provider<WallRepository>((ref) {
  return WallRepository(ref.read(supabaseClientProvider));
});

final linkPreviewServiceProvider = Provider<LinkPreviewService>((ref) {
  final service = LinkPreviewService();
  ref.onDispose(service.close);
  return service;
});

final wallSelfIdProvider = Provider<String?>((ref) {
  return ref.watch(authSessionProvider).asData?.value?.user.id;
});

/// The spouse's display name, or null when unknown/blank.
final wallSpouseNameProvider = Provider<String?>((ref) {
  final name = ref.watch(spouseProfileProvider).asData?.value?.displayName.trim();
  return (name == null || name.isEmpty) ? null : name;
});

/// Label for an author: "You", the spouse's name, or "Your partner".
final wallNameForProvider = Provider<String Function(String userId)>((ref) {
  final self = ref.watch(wallSelfIdProvider);
  final spouse = ref.watch(wallSpouseNameProvider);
  return (userId) => userId == self ? 'You' : (spouse ?? 'Your partner');
});

/// Opens [open] for the current couple. Stays loading while the couple is
/// loading (no empty-state flash); empty when there is no couple.
Stream<T> _forCouple<T>(Ref ref, T empty, Stream<T> Function(String coupleId) open) {
  final coupleAsync = ref.watch(currentCoupleProvider);
  final couple = coupleAsync.asData?.value;
  if (couple == null) {
    return coupleAsync.isLoading ? Stream<T>.empty() : Stream<T>.value(empty);
  }
  return open(couple.id);
}

final wallItemsProvider = StreamProvider<List<WallItem>>((ref) {
  return _forCouple(ref, const <WallItem>[], ref.read(wallRepositoryProvider).watchItems);
});

final wallReactionsProvider = StreamProvider<List<WallReaction>>((ref) {
  return _forCouple(
      ref, const <WallReaction>[], ref.read(wallRepositoryProvider).watchReactions);
});

final wallCommentsProvider = StreamProvider<List<WallComment>>((ref) {
  return _forCouple(
      ref, const <WallComment>[], ref.read(wallRepositoryProvider).watchComments);
});

class WallFilter extends Notifier<WallCollection?> {
  @override
  WallCollection? build() => null;

  void select(WallCollection? collection) => state = collection;
}

final wallFilterProvider =
    NotifierProvider<WallFilter, WallCollection?>(WallFilter.new);

final filteredWallItemsProvider = Provider<AsyncValue<List<WallItem>>>((ref) {
  final filter = ref.watch(wallFilterProvider);
  return ref.watch(wallItemsProvider).whenData((items) => filter == null
      ? items
      : [for (final i in items) if (i.collection == filter) i]);
});

final pinnedWallItemsProvider = Provider<List<WallItem>>((ref) {
  final items = ref.watch(wallItemsProvider).asData?.value ?? const <WallItem>[];
  return [for (final i in items) if (i.isPinned) i];
});

final wallItemProvider = Provider.family<AsyncValue<WallItem?>, String>((ref, id) {
  return ref.watch(wallItemsProvider).whenData((items) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  });
});

final wallReactionSummaryProvider =
    Provider.family<List<ReactionCount>, String>((ref, itemId) {
  return summarizeReactions(
    ref.watch(wallReactionsProvider).asData?.value ?? const <WallReaction>[],
    itemId: itemId,
    selfId: ref.watch(wallSelfIdProvider),
  );
});

final wallItemCommentsProvider =
    Provider.family<List<WallComment>, String>((ref, itemId) {
  final comments = ref.watch(wallCommentsProvider).asData?.value ?? const <WallComment>[];
  return [for (final c in comments) if (c.itemId == itemId) c];
});

final wallSharedThisWeekProvider = Provider<int>((ref) {
  return itemsThisWeek(
    ref.watch(wallItemsProvider).asData?.value ?? const <WallItem>[],
    now: DateTime.now(),
  );
});

/// When this account last left the Wall. Stored on-device per account
/// (`wall.last_visit.<userId>`), so accounts sharing a device don't mix.
class WallLastVisit extends AsyncNotifier<DateTime?> {
  static String _key(String userId) => 'wall.last_visit.$userId';

  @override
  Future<DateTime?> build() async {
    final userId = ref.watch(wallSelfIdProvider);
    if (userId == null) return null;
    final raw = await ref.read(secureStoreProvider).read(_key(userId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markNow() async {
    final userId = ref.read(wallSelfIdProvider);
    if (userId == null) return;
    final now = DateTime.now();
    state = AsyncData(now);
    try {
      await ref.read(secureStoreProvider).write(_key(userId), now.toIso8601String());
    } catch (_) {
      // Best-effort: worst case the dots reappear next launch.
    }
  }
}

final wallLastVisitProvider =
    AsyncNotifierProvider<WallLastVisit, DateTime?>(WallLastVisit.new);

final unseenWallItemIdsProvider = Provider<Set<String>>((ref) {
  final lastVisit = ref.watch(wallLastVisitProvider);
  if (lastVisit.isLoading) return const {}; // don't flash dots before we know
  return unseenItemIds(
    ref.watch(wallItemsProvider).asData?.value ?? const <WallItem>[],
    selfId: ref.watch(wallSelfIdProvider),
    lastVisit: lastVisit.asData?.value,
  );
});
