// Integration test against the LOCAL Supabase instance (see `supabase status`).
//
// The brief's original test mocked SupabaseClient/SupabaseQueryBuilder/
// PostgrestFilterBuilder with mocktail. As already established on this
// project (Task 3, and documented in
// `test/features/onboarding/onboarding_repository_test.dart`), that approach
// does not work against the installed supabase_flutter (2.16.0) / postgrest
// (2.8.0): every builder in the chain implements `Future<T>` directly rather
// than returning a plain Future from its methods, which breaks mocktail's
// `thenReturn`/`thenAnswer`/`.then` stubbing. Per the task's sanctioned
// fallback, this test instead exercises `ScoreboardRepository` against the
// local Supabase instance:
//
//   - Two throwaway users are signed up and paired into a real couple via
//     the `create_pairing_invite`/`accept_pairing_invite` RPCs (the same
//     flow the app uses), so `prayer_logs`/`cycle_records` RLS
//     (`is_couple_member`, `user_id = auth.uid()`) is exercised for real
//     rather than bypassed.
//   - `fetchDayLogs` is asserted to group `prayed`-status rows into one
//     `DayLog` per date and to exclude `missed` rows — the exact behavior
//     the brief's mocked test intended.
//   - `fetchCycles` is asserted against a real `cycle_records` row.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/features/scoring/data/scoreboard_repository.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

SupabaseClient _anonClient() => SupabaseClient(
      _supabaseUrl,
      _anonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

Future<({String coupleId, String userA, String userB})> _pairCouple(
  SupabaseClient clientA,
  SupabaseClient clientB,
  int stamp,
) async {
  final signUpA = await clientA.auth.signUp(
    email: 'scoreboard-a-$stamp@example.com',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'scoreboard-b-$stamp@example.com',
    password: 'password123',
  );
  final userA = signUpA.user!.id;
  final userB = signUpB.user!.id;

  // accept_pairing_invite requires both members to have a gender set (and
  // different from each other) — set these before pairing.
  await clientA.from('users').update({'gender': 'male'}).eq('id', userA);
  await clientB.from('users').update({'gender': 'female'}).eq('id', userB);

  final inviteRes = await clientA.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  final code = inviteRow['code'] as String;

  final coupleRes = await clientB.rpc('accept_pairing_invite', params: {
    'p_code': code,
  });
  final coupleRow = Map<String, dynamic>.from(
    (coupleRes is List ? coupleRes.first : coupleRes) as Map,
  );

  return (coupleId: coupleRow['id'] as String, userA: userA, userB: userB);
}

void main() {
  final adminClient = SupabaseClient(
    _supabaseUrl,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  test('fetchDayLogs groups prayed-status rows by date, excluding missed',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    addTearDown(() async {
      await adminClient.auth.admin.deleteUser(pairing.userA);
      await adminClient.auth.admin.deleteUser(pairing.userB);
    });

    await clientA.from('prayer_logs').insert([
      {
        'couple_id': pairing.coupleId,
        'user_id': pairing.userA,
        'date': '2026-07-01',
        'prayer': 'fajr',
        'status': 'prayed',
      },
      {
        'couple_id': pairing.coupleId,
        'user_id': pairing.userA,
        'date': '2026-07-01',
        'prayer': 'isha',
        'status': 'missed',
      },
      {
        'couple_id': pairing.coupleId,
        'user_id': pairing.userA,
        'date': '2026-07-02',
        'prayer': 'dhuhr',
        'status': 'prayed',
      },
    ]);

    final repo = ScoreboardRepository(clientA);
    final logs = await repo.fetchDayLogs(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      from: DateTime(2026, 7, 1),
      toInclusive: DateTime(2026, 7, 2),
    );
    logs.sort((a, b) => a.date.compareTo(b.date));

    expect(logs.length, 2); // one DayLog per date
    expect(logs[0].date, DateTime(2026, 7, 1));
    expect(logs[0].prayed, {Prayer.fajr}); // 'missed' excluded
    expect(logs[1].date, DateTime(2026, 7, 2));
    expect(logs[1].prayed, {Prayer.dhuhr});
  });

  test('fetchCycles returns the user\'s cycle records within range',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch + 1;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    addTearDown(() async {
      await adminClient.auth.admin.deleteUser(pairing.userA);
      await adminClient.auth.admin.deleteUser(pairing.userB);
    });

    await clientA.from('cycle_records').insert({
      'user_id': pairing.userA,
      'couple_id': pairing.coupleId,
      'started_on': '2026-07-05',
      'visibility': 'private',
    });

    final repo = ScoreboardRepository(clientA);
    final cycles = await repo.fetchCycles(
      userId: pairing.userA,
      from: DateTime(2026, 7, 1),
      toInclusive: DateTime(2026, 7, 10),
    );

    expect(cycles.single.userId, pairing.userA);
    expect(cycles.single.startedOn, DateTime(2026, 7, 5));
    expect(cycles.single.visibility, 'private');
  });
}
