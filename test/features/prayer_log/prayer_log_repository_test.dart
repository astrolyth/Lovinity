// test/features/prayer_log/prayer_log_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Same pairing/cleanup
// pattern as test/features/chat/chat_repository_test.dart and
// test/features/gratitude/gratitude_repository_test.dart.
//
// Regression coverage for cross-timezone partner sync.
//
// A partner's prayer_logs row is written under HER local calendar date, which
// legitimately differs from this device's (different zones, or one device past
// midnight). Two streams must both cope:
//
//   * `watchCouple` (the notification pump) sees every row regardless of date;
//   * `watchDays` (the date-scoped UI) scopes each row to ITS OWN OWNER's day,
//     so her rows survive under her key while his survive under his.
//
// The second is the fix. The previous `watchDay(date)` applied one caller-
// supplied key to both spouses, so her rows were silently discarded and the UI
// rendered "Not yet" for prayers she had already completed. An earlier version
// of this test asserted that exclusion as correct behaviour -- it was the bug.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/prayer_log/data/prayer_log_repository.dart';
import 'package:lovinity/core/time/prayer_engine.dart';

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

Future<({String userA, String userB, String coupleId})> _pairCouple(
  SupabaseClient clientA,
  SupabaseClient clientB,
  int stamp,
) async {
  final signUpA = await clientA.auth.signUp(
    email: 'prayersync-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'prayersync-b-$stamp@test.local',
    password: 'password123',
  );
  final userA = signUpA.user!.id;
  final userB = signUpB.user!.id;

  addTearDown(() => adminClient.auth.admin.deleteUser(userA));
  addTearDown(() => adminClient.auth.admin.deleteUser(userB));

  await clientA.from('users').update({'gender': 'male'}).eq('id', userA);
  await clientB.from('users').update({'gender': 'female'}).eq('id', userB);

  final inviteRes = await clientA.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  final code = inviteRow['code'] as String;
  await clientB.rpc('accept_pairing_invite', params: {'p_code': code});

  final coupleId = await clientA.rpc('current_couple') as String;
  return (userA: userA, userB: userB, coupleId: coupleId);
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test(
      'watchDays scopes each spouse to their own calendar day, and watchCouple '
      'still surfaces everything', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = PrayerLogRepository(clientA);
    final repoB = PrayerLogRepository(clientB);

    // Simulate timezone drift: A's device thinks it's July 30th, B's device
    // (ahead of A, e.g. UTC vs UTC-6) thinks it's July 31st. Both log Isha.
    final localToday = DateTime(2026, 7, 30);
    final partnerTomorrow = DateTime(2026, 7, 31);

    await repoA.logPrayer(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      date: localToday,
      prayer: Prayer.isha,
    );
    await repoB.logPrayer(
      coupleId: pairing.coupleId,
      userId: pairing.userB,
      date: partnerTomorrow,
      prayer: Prayer.isha,
    );

    // UI provider path (`watchDays`, per-owner scoped): from A's perspective
    // looking at "today", A is anchored to July 30th and B to her own July
    // 31st. BOTH check-ins must survive -- this is the whole fix. Under the
    // old single-key filter B's row was dropped and the UI said "Not yet" for
    // a prayer she had completed.
    final dayView = await repoA.watchDays(
      coupleId: pairing.coupleId,
      dayKeyByUserId: {
        pairing.userA: '2026-07-30',
        pairing.userB: '2026-07-31',
      },
    ).first;
    expect(
      dayView.map((e) => e.userId).toSet(),
      {pairing.userA, pairing.userB},
    );

    // ...and each row is still pinned to its own owner's day: anchoring B to
    // A's date must drop B's row, not silently re-file it.
    final mismatched = await repoA.watchDays(
      coupleId: pairing.coupleId,
      dayKeyByUserId: {
        pairing.userA: '2026-07-30',
        pairing.userB: '2026-07-30',
      },
    ).first;
    expect(mismatched.map((e) => e.userId), [pairing.userA]);

    // A user absent from the anchor map has no honest day to be filed under,
    // so their rows are excluded rather than defaulted.
    final unanchored = await repoA.watchDays(
      coupleId: pairing.coupleId,
      dayKeyByUserId: {pairing.userA: '2026-07-30'},
    ).first;
    expect(unanchored.map((e) => e.userId), [pairing.userA]);

    // Notification-pump path (`watchCouple`, unscoped): must see BOTH
    // check-ins, including the partner's row dated a different day. This is
    // the exact scenario FIX 2 addresses -- before the fix, only `watchDay`
    // existed and the pump would have silently dropped the partner's row.
    final coupleView =
        await repoA.watchCouple(coupleId: pairing.coupleId).first;
    expect(coupleView.map((e) => e.userId).toSet(),
        {pairing.userA, pairing.userB});
    final partnerEntry =
        coupleView.firstWhere((e) => e.userId == pairing.userB);
    expect(partnerEntry.dateKey, '2026-07-31');
  });
}
