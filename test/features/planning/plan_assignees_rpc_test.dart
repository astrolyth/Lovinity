// LOCAL Supabase: a plan's assignee and a grocery item's buyer must belong
// to the row's own couple (20261125000001_plan_assignees.sql).
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/calendar/data/calendar_repository.dart';
import 'package:lovinity/features/planning/data/grocery_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/live_supabase.dart';

void main() {
  test('assignee and buyer are limited to the couple', () async {
    final a = await livePairedCouple('plan-a');
    final b = await livePairedCouple('plan-b');

    final cal = CalendarRepository(a.husband);
    await cal.create(
      coupleId: a.coupleId,
      userId: a.husbandId,
      title: 'Dentist',
      startsAt: DateTime.now(),
      assigneeId: a.wifeId,
    );
    final row = await a.wife
        .from('calendar_events')
        .select('assignee_id')
        .eq('couple_id', a.coupleId)
        .single();
    expect(row['assignee_id'], a.wifeId);

    await expectLater(
      cal.create(
        coupleId: a.coupleId,
        userId: a.husbandId,
        title: 'Not yours',
        startsAt: DateTime.now(),
        assigneeId: b.wifeId,
      ),
      throwsA(isA<PostgrestException>()),
    );

    final list = await a.husband
        .from('grocery_lists')
        .insert({'couple_id': a.coupleId})
        .select()
        .single();
    final item = await a.husband
        .from('grocery_items')
        .insert({
          'list_id': list['id'],
          'couple_id': a.coupleId,
          'name': 'Dates',
          'created_by': a.husbandId,
        })
        .select()
        .single();
    final groceries = GroceryRepository(a.wife);
    await groceries.setBuyer(itemId: item['id'] as String, buyerId: a.wifeId);
    final updated = GroceryItem.fromRow(
      await a.wife.from('grocery_items').select().eq('id', item['id']).single(),
    );
    expect(updated.buyer, a.wifeId);
    await expectLater(
      groceries.setBuyer(itemId: item['id'] as String, buyerId: b.husbandId),
      throwsA(isA<PostgrestException>()),
    );
  });
}
