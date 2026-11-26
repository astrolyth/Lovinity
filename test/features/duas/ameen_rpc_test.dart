// LOCAL Supabase: "Ameen together" (20261125000003_dua_ameen.sql).
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/data/ameen_repository.dart';

import '../../shared/live_supabase.dart';

void main() {
  test('Ameen is once per person per day and visible to the spouse', () async {
    final c = await livePairedCouple('ameen');
    final hers = AmeenRepository(c.wife);
    await hers.say(coupleId: c.coupleId, userId: c.wifeId, day: '2026-11-25');
    await hers.say(coupleId: c.coupleId, userId: c.wifeId, day: '2026-11-25');

    final seen = await AmeenRepository(c.husband).watch(c.coupleId).first;
    expect(seen.map((a) => (a.userId, a.day)), [(c.wifeId, '2026-11-25')]);
  });
}
