// Integration test against LOCAL Supabase for the shared shopping list.
//
// The headline case is concurrent ticking. `grocery_lists.items` was a jsonb
// array, so checking one item meant rewriting the whole array; two spouses
// ticking at the same moment in a shop meant the second write silently
// discarded the first and the item reappeared unchecked. Row-per-item
// (20260807000003_grocery_items.sql) makes that impossible by construction,
// and this test is what would catch a regression back to array semantics.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/planning/data/grocery_repository.dart';
import 'package:lovinity/features/planning/data/meal_plan_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

late SupabaseClient adminClient;

SupabaseClient _anonClient() => SupabaseClient(
      _url,
      _anon,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

Future<String> _signUp(
    SupabaseClient client, String email, String gender) async {
  final res = await client.auth.signUp(email: email, password: 'password123');
  final id = res.user!.id;
  addTearDown(() => adminClient.auth.admin.deleteUser(id));
  await client.from('users').update({'gender': gender}).eq('id', id);
  return id;
}

Future<String> _pair(SupabaseClient a, SupabaseClient b) async {
  final inviteRes = await a.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  await b.rpc('accept_pairing_invite',
      params: {'p_code': inviteRow['code'] as String});
  return await a.rpc('current_couple') as String;
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test('concurrent ticks on different items both persist', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'gro-h-$stamp@test.local', 'male');
    final wifeId = await _signUp(wife, 'gro-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repoHusband = GroceryRepository(husband);
    final repoWife = GroceryRepository(wife);
    final listId = await repoHusband.createList(coupleId: coupleId);

    for (final name in ['Rice', 'Dates', 'Olive oil', 'Milk']) {
      await repoHusband.addItem(
        coupleId: coupleId,
        listId: listId,
        userId: husbandId,
        name: name,
      );
    }

    final items = await repoHusband.watchItems(coupleId: coupleId).first;
    expect(items.length, 4);
    final rice = items.firstWhere((i) => i.name == 'Rice');
    final dates = items.firstWhere((i) => i.name == 'Dates');

    // Both spouses tick, at the same time, from different devices. This is the
    // aisle scenario — under the old jsonb array one of these two writes would
    // have been silently lost.
    await Future.wait([
      repoHusband.setChecked(
          itemId: rice.id, userId: husbandId, checked: true),
      repoWife.setChecked(itemId: dates.id, userId: wifeId, checked: true),
    ]);

    final after = await repoHusband.watchItems(coupleId: coupleId).first;
    final checked = {
      for (final i in after)
        if (i.checked) i.name,
    };
    expect(checked, {'Rice', 'Dates'},
        reason: 'neither spouse\'s tick may be lost');

    // Attribution survives, so the list can say who got what.
    final riceAfter = after.firstWhere((i) => i.name == 'Rice');
    final datesAfter = after.firstWhere((i) => i.name == 'Dates');
    expect(riceAfter.checkedBy, husbandId);
    expect(datesAfter.checkedBy, wifeId);
    expect(riceAfter.checkedAt, isNotNull);
  });

  test('un-ticking clears attribution', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'gro2-h-$stamp@test.local', 'male');
    await _signUp(wife, 'gro2-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repo = GroceryRepository(husband);
    final listId = await repo.createList(coupleId: coupleId);
    await repo.addItem(
        coupleId: coupleId, listId: listId, userId: husbandId, name: 'Bread');

    final item = (await repo.watchItems(coupleId: coupleId).first).single;
    await repo.setChecked(
        itemId: item.id, userId: husbandId, checked: true);
    await repo.setChecked(
        itemId: item.id, userId: husbandId, checked: false);

    final after = (await repo.watchItems(coupleId: coupleId).first).single;
    expect(after.checked, isFalse);
    expect(after.checkedBy, isNull,
        reason: 'a re-added item must not still claim someone bought it');
    expect(after.checkedAt, isNull);
  });

  test('clearChecked removes only bought items', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'gro3-h-$stamp@test.local', 'male');
    await _signUp(wife, 'gro3-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repo = GroceryRepository(husband);
    final listId = await repo.createList(coupleId: coupleId);
    for (final name in ['Rice', 'Dates']) {
      await repo.addItem(
          coupleId: coupleId, listId: listId, userId: husbandId, name: name);
    }
    final items = await repo.watchItems(coupleId: coupleId).first;
    await repo.setChecked(
      itemId: items.firstWhere((i) => i.name == 'Rice').id,
      userId: husbandId,
      checked: true,
    );

    await repo.clearChecked(listId: listId);

    final after = await repo.watchItems(coupleId: coupleId).first;
    expect(after.map((i) => i.name), ['Dates']);
  });

  test('an outsider cannot read the couple\'s list', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final outsider = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'gro4-h-$stamp@test.local', 'male');
    await _signUp(wife, 'gro4-w-$stamp@test.local', 'female');
    await _signUp(outsider, 'gro4-o-$stamp@test.local', 'male');
    final coupleId = await _pair(husband, wife);

    final repo = GroceryRepository(husband);
    final listId = await repo.createList(coupleId: coupleId);
    await repo.addItem(
        coupleId: coupleId, listId: listId, userId: husbandId, name: 'Rice');

    final asOutsider =
        await GroceryRepository(outsider).watchItems(coupleId: coupleId).first;
    expect(asOutsider, isEmpty);
  });

  test('meal plan slots merge rather than replace the week', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    await _signUp(husband, 'meal-h-$stamp@test.local', 'male');
    await _signUp(wife, 'meal-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repo = MealPlanRepository(husband);
    final week = DateTime(2026, 8, 3);

    await repo.setSlot(
        coupleId: coupleId,
        week: week,
        slotKey: 'mon_dinner',
        value: 'Biryani');
    // A second slot set by the other spouse must not wipe the first.
    await MealPlanRepository(wife).setSlot(
        coupleId: coupleId, week: week, slotKey: 'tue_lunch', value: 'Soup');

    final plans = await repo.watchPlans(coupleId: coupleId).first;
    final plan = plans.single;
    expect(plan.mealFor(0, MealSlot.dinner), 'Biryani');
    expect(plan.mealFor(1, MealSlot.lunch), 'Soup');

    // Clearing one slot leaves the rest intact.
    await repo.setSlot(
        coupleId: coupleId, week: week, slotKey: 'mon_dinner', value: '');
    final after = (await repo.watchPlans(coupleId: coupleId).first).single;
    expect(after.mealFor(0, MealSlot.dinner), isNull);
    expect(after.mealFor(1, MealSlot.lunch), 'Soup');
  });
}
