import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/planning/data/grocery_repository.dart';
import 'package:lovinity/features/planning/data/meal_plan_repository.dart';
import 'package:lovinity/features/planning/data/recipe_repository.dart';
import 'package:lovinity/features/planning/domain/planning_providers.dart';

GroceryItem _item({
  required String id,
  String listId = 'list-1',
  bool checked = false,
  int position = 0,
  String name = 'Milk',
}) =>
    GroceryItem(
      id: id,
      listId: listId,
      name: name,
      checked: checked,
      position: position,
      createdBy: 'him',
    );

void main() {
  group('weekStarting', () {
    test('returns the Monday of the containing week', () {
      // 2026-08-07 is a Friday.
      expect(weekStarting(DateTime(2026, 8, 7)), DateTime(2026, 8, 3));
    });

    test('is idempotent on a Monday', () {
      expect(weekStarting(DateTime(2026, 8, 3)), DateTime(2026, 8, 3));
    });

    test('treats Sunday as the end of the week, not the start', () {
      // 2026-08-09 is a Sunday and belongs to the week beginning the 3rd.
      expect(weekStarting(DateTime(2026, 8, 9)), DateTime(2026, 8, 3));
    });

    test('crosses a month boundary', () {
      // 2026-09-01 is a Tuesday; its Monday is in August.
      expect(weekStarting(DateTime(2026, 9, 1)), DateTime(2026, 8, 31));
    });

    test('crosses a year boundary', () {
      // 2027-01-01 is a Friday; its Monday is in 2026.
      expect(weekStarting(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('discards any time component', () {
      expect(weekStarting(DateTime(2026, 8, 7, 23, 59)), DateTime(2026, 8, 3));
    });
  });

  group('mealSlotKey', () {
    test('builds the documented <weekday>_<meal> shape', () {
      expect(mealSlotKey(0, MealSlot.dinner), 'mon_dinner');
      expect(mealSlotKey(6, MealSlot.breakfast), 'sun_breakfast');
    });

    test('covers all seven days', () {
      expect(weekdayKeys.length, 7);
      expect(weekdayLabels.length, 7);
    });
  });

  group('MealPlan', () {
    final plan = MealPlan(
      id: 'p1',
      weekStarting: DateTime(2026, 8, 3),
      slots: const {'mon_dinner': 'Biryani', 'tue_lunch': 'Soup'},
    );

    test('reads a planned slot', () {
      expect(plan.mealFor(0, MealSlot.dinner), 'Biryani');
      expect(plan.mealFor(1, MealSlot.lunch), 'Soup');
    });

    test('returns null for an unplanned slot', () {
      expect(plan.mealFor(0, MealSlot.breakfast), isNull);
    });

    test('counts only non-empty slots', () {
      final withBlank = MealPlan(
        id: 'p2',
        weekStarting: DateTime(2026, 8, 3),
        slots: const {'mon_dinner': 'Biryani', 'tue_lunch': '   '},
      );
      expect(withBlank.plannedCount, 1);
    });
  });

  group('partitionItems', () {
    test('sinks bought items below outstanding ones', () {
      final items = [
        _item(id: '1', checked: true, name: 'Rice'),
        _item(id: '2', name: 'Milk'),
        _item(id: '3', checked: true, name: 'Oil'),
        _item(id: '4', name: 'Dates'),
      ];
      expect(
        partitionItems(items, 'list-1').map((i) => i.id),
        ['2', '4', '1', '3'],
      );
    });

    test('keeps bought items visible rather than removing them', () {
      // Mid-shop, a vanished item is indistinguishable from one that was never
      // on the list — you cannot tell "already got it" from "not needed".
      final items = [_item(id: '1', checked: true)];
      expect(partitionItems(items, 'list-1').length, 1);
    });

    test('excludes items belonging to another list', () {
      final items = [
        _item(id: '1', listId: 'list-1'),
        _item(id: '2', listId: 'list-2'),
      ];
      expect(partitionItems(items, 'list-1').map((i) => i.id), ['1']);
    });

    test('is empty for a list with no items', () {
      expect(partitionItems([_item(id: '1', listId: 'other')], 'list-1'),
          isEmpty);
    });
  });

  group('Recipe.fromRow', () {
    test('parses ingredients and steps, dropping blanks', () {
      final r = Recipe.fromRow({
        'id': 'r1',
        'title': 'Biryani',
        'ingredients': ['Rice', '', '  ', 'Chicken'],
        'steps': ['Soak rice', 'Cook'],
        'created_at': '2026-08-07T10:00:00Z',
      });
      expect(r.ingredients, ['Rice', 'Chicken']);
      expect(r.steps, ['Soak rice', 'Cook']);
    });

    test('tolerates missing lists', () {
      final r = Recipe.fromRow({
        'id': 'r1',
        'title': 'Toast',
        'created_at': '2026-08-07T10:00:00Z',
      });
      expect(r.ingredients, isEmpty);
      expect(r.steps, isEmpty);
      expect(r.halalNotes, isNull);
    });
  });
}
