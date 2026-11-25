// LOCAL Supabase: cycle moods are private unless she shares them, and only
// the wife can write them (20261125000002_cycle_moods.sql).
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/cycle/data/cycle_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/live_supabase.dart';

void main() {
  test('moods: private by default, shared on request, wife-only', () async {
    final c = await livePairedCouple('moods');
    final hers = CycleRepository(c.wife);
    Future<List<Map<String, dynamic>>> husbandSees() =>
        c.husband.from('cycle_moods').select().eq('couple_id', c.coupleId);

    await hers.setMoods(
      userId: c.wifeId,
      coupleId: c.coupleId,
      day: '2026-11-25',
      moods: {'calm', 'tired'},
      shared: false,
    );
    expect(await husbandSees(), isEmpty);

    await hers.setMoods(
      userId: c.wifeId,
      coupleId: c.coupleId,
      day: '2026-11-25',
      moods: {'calm'},
      shared: true,
    );
    final seen = await husbandSees();
    expect(seen, hasLength(1));
    expect(CycleMood.fromRow(seen.single).moods, {'calm'});

    await expectLater(
      CycleRepository(c.husband).setMoods(
        userId: c.husbandId,
        coupleId: c.coupleId,
        day: '2026-11-25',
        moods: {'tired'},
        shared: true,
      ),
      throwsA(isA<PostgrestException>()),
    );
  });
}
