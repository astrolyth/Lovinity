import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/local_day.dart';
import '../../../core/time/tz_sync.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/grocery_repository.dart';
import '../data/meal_plan_repository.dart';
import '../data/recipe_repository.dart';

final groceryRepositoryProvider = Provider<GroceryRepository>((ref) {
  return GroceryRepository(ref.read(supabaseClientProvider));
});

final mealPlanRepositoryProvider = Provider<MealPlanRepository>((ref) {
  return MealPlanRepository(ref.read(supabaseClientProvider));
});

final recipeRepositoryProvider = Provider<RecipeRepository>((ref) {
  return RecipeRepository(ref.read(supabaseClientProvider));
});

/// The Monday of the week currently being planned, as a `YYYY-MM-DD` key.
///
/// Anchored on the viewer's own zone via `local_day.dart`, and exposed as a
/// string so watchers wake only when the week actually changes rather than on
/// every tick of the 30-second clock.
final currentWeekKeyProvider = Provider<String>((ref) {
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value ?? 'UTC';
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  return dayKey(weekStarting(localDayAt(deviceTz, now)));
});

/// How many weeks forward or back the planner is showing. 0 is this week.
class PlannerWeekOffset extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state = state + 1;
  void previous() => state = state - 1;
  void reset() => state = 0;
}

final plannerWeekOffsetProvider =
    NotifierProvider<PlannerWeekOffset, int>(PlannerWeekOffset.new);

/// The Monday of the week being viewed.
final viewedWeekProvider = Provider<DateTime>((ref) {
  final base = DateTime.parse(ref.watch(currentWeekKeyProvider));
  final offset = ref.watch(plannerWeekOffsetProvider);
  return DateTime(base.year, base.month, base.day + offset * 7);
});

final mealPlansProvider = StreamProvider<List<MealPlan>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(mealPlanRepositoryProvider).watchPlans(coupleId: coupleId);
});

/// The plan for the week being viewed, or null when nothing is planned yet.
final viewedMealPlanProvider = Provider<MealPlan?>((ref) {
  final plans = ref.watch(mealPlansProvider).asData?.value ?? const [];
  final week = dayKey(ref.watch(viewedWeekProvider));
  for (final p in plans) {
    if (dayKey(p.weekStarting) == week) return p;
  }
  return null;
});

final groceryListsProvider = StreamProvider<List<GroceryList>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(groceryRepositoryProvider).watchLists(coupleId: coupleId);
});

final groceryItemsProvider = StreamProvider<List<GroceryItem>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(groceryRepositoryProvider).watchItems(coupleId: coupleId);
});

/// The list currently being shopped — the couple's first list, created lazily.
final activeGroceryListProvider = Provider<GroceryList?>((ref) {
  final lists = ref.watch(groceryListsProvider).asData?.value ?? const [];
  return lists.isEmpty ? null : lists.first;
});

/// Items belonging to [listId], unchecked first then checked, each group in
/// insertion order.
///
/// Bought items sink rather than disappear: they are the record of what has
/// already gone in the trolley, and removing them from view mid-shop makes it
/// impossible to tell "not needed" from "already got it".
List<GroceryItem> partitionItems(List<GroceryItem> items, String listId) {
  final mine = [for (final i in items) if (i.listId == listId) i];
  final unchecked = [for (final i in mine) if (!i.checked) i];
  final checked = [for (final i in mine) if (i.checked) i];
  return [...unchecked, ...checked];
}

final activeGroceryItemsProvider = Provider<List<GroceryItem>>((ref) {
  final list = ref.watch(activeGroceryListProvider);
  final items = ref.watch(groceryItemsProvider).asData?.value ?? const [];
  if (list == null) return const [];
  return partitionItems(items, list.id);
});

final recipesProvider = StreamProvider<List<Recipe>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(recipeRepositoryProvider).watchAll(coupleId: coupleId);
});

/// Notifies when the spouse adds something to the shopping list.
///
/// Deliberately fires on additions only, not on ticks: during a shop the two
/// of you tick constantly, and a notification per tick would be noise that
/// trains the user to ignore the channel entirely.
final groceryNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<GroceryItem>(
    keyOf: (i) => i.id,
    onNew: (item) {
      if (item.createdBy == selfId) return;
      unawaited(store.insertBestEffort(
        kind: 'grocery',
        title: 'Your partner added ${item.name} to the list',
        route: '/home/groceries',
      ));
    },
  );

  final sub = ref
      .read(groceryRepositoryProvider)
      .watchItems(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
