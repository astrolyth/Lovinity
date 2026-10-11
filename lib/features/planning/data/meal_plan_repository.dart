import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/local_day.dart';

/// The meals a week is planned around.
///
/// Slot keys are `<weekday>_<meal>` (`mon_dinner`), matching the shape the
/// `meal_plans.slots` jsonb column documents.
enum MealSlot { breakfast, lunch, dinner }

extension MealSlotX on MealSlot {
  String get dbName => switch (this) {
        MealSlot.breakfast => 'breakfast',
        MealSlot.lunch => 'lunch',
        MealSlot.dinner => 'dinner',
      };

  String get label => switch (this) {
        MealSlot.breakfast => 'Breakfast',
        MealSlot.lunch => 'Lunch',
        MealSlot.dinner => 'Dinner',
      };
}

const weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const weekdayLabels = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String mealSlotKey(int weekdayIndex, MealSlot slot) =>
    '${weekdayKeys[weekdayIndex]}_${slot.dbName}';

/// The Monday of the week containing [date].
///
/// Weeks are anchored on the viewer's own local day (resolve [date] through
/// `local_day.dart` first). Deriving it from a UTC instant would put a couple
/// either side of midnight into different weeks and show them different plans
/// for the same seven days.
DateTime weekStarting(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

class MealPlan {
  const MealPlan({
    required this.id,
    required this.weekStarting,
    required this.slots,
  });

  final String id;
  final DateTime weekStarting;

  /// `{"mon_dinner": "Biryani", ...}` — absent keys mean an unplanned slot.
  final Map<String, String> slots;

  String? mealFor(int weekdayIndex, MealSlot slot) =>
      slots[mealSlotKey(weekdayIndex, slot)];

  int get plannedCount => slots.values.where((v) => v.trim().isNotEmpty).length;

  factory MealPlan.fromRow(Map<String, dynamic> row) => MealPlan(
        id: row['id'] as String,
        weekStarting: DateTime.parse(row['week_starting'] as String),
        slots: {
          for (final e in (row['slots'] as Map? ?? const {}).entries)
            e.key.toString(): e.value?.toString() ?? '',
        },
      );
}

class MealPlanRepository {
  MealPlanRepository(this._client);

  final SupabaseClient _client;

  Stream<List<MealPlan>> watchPlans({required String coupleId}) {
    return _client
        .from('meal_plans')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                MealPlan.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Sets one slot for [week].
  ///
  /// Reads the current slots and writes the merged map back. Unlike the
  /// shopping list this is an acceptable read-modify-write: a week plan is
  /// edited deliberately at a kitchen table, not raced by two people in a
  /// shop, and the blast radius of a conflict is one overwritten meal name
  /// rather than a bought-twice item. If that assumption stops holding, this
  /// is the place to move to a jsonb merge RPC.
  Future<void> setSlot({
    required String coupleId,
    required DateTime week,
    required String slotKey,
    required String? value,
  }) async {
    final key = dayKey(weekStarting(week));
    final existing = await _client
        .from('meal_plans')
        .select()
        .eq('couple_id', coupleId)
        .eq('week_starting', key)
        .maybeSingle();

    final slots = <String, dynamic>{
      for (final e in (existing?['slots'] as Map? ?? const {}).entries)
        e.key.toString(): e.value,
    };
    if (value == null || value.trim().isEmpty) {
      slots.remove(slotKey);
    } else {
      slots[slotKey] = value.trim();
    }

    await _client.from('meal_plans').upsert(
      {'couple_id': coupleId, 'week_starting': key, 'slots': slots},
      onConflict: 'couple_id,week_starting',
    );
  }
}
