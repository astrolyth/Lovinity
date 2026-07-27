// Integration test against the LOCAL Supabase instance (see `supabase
// status`) proving fix C1: the couple scoreboard is computed server-side by
// the `get_couple_scoreboard` SECURITY DEFINER RPC (see
// `supabase/migrations/20260715000005_scoreboard_rpc.sql`), so a wife's
// PRIVATE cycle exemptions apply to her score correctly on her husband's
// device WITHOUT ever exposing her cycle_records rows to him (RLS still
// blocks a direct read; the RPC bypasses RLS only inside its own body).
//
// mocktail can't stub supabase_flutter's builder chain (see
// scoreboard_repository_test.dart for why), so this follows the same
// sanctioned real-Supabase pattern: two throwaway users, signed up and
// paired via the real `create_pairing_invite`/`accept_pairing_invite` RPCs.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _daysAgo(int n) {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  return today.subtract(Duration(days: n));
}

void main() {
  final adminClient = SupabaseClient(
    _supabaseUrl,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  test(
    'get_couple_scoreboard applies the wife\'s private cycle exemption to '
    'her score without exposing her cycle rows to the husband',
    () async {
      final husbandClient = _anonClient();
      final wifeClient = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final signUpHusband = await husbandClient.auth.signUp(
        email: 'scoreboard-rpc-husband-$stamp@example.com',
        password: 'password123',
      );
      final signUpWife = await wifeClient.auth.signUp(
        email: 'scoreboard-rpc-wife-$stamp@example.com',
        password: 'password123',
      );
      final husbandId = signUpHusband.user!.id;
      final wifeId = signUpWife.user!.id;

      addTearDown(() async {
        await adminClient.auth.admin.deleteUser(husbandId);
        await adminClient.auth.admin.deleteUser(wifeId);
      });

      // accept_pairing_invite requires both members to have a gender set
      // (and different from each other) before pairing.
      await husbandClient.from('users').update({'gender': 'male'}).eq('id', husbandId);
      await wifeClient.from('users').update({'gender': 'female'}).eq('id', wifeId);

      final inviteRes = await husbandClient.rpc('create_pairing_invite');
      final inviteRow = Map<String, dynamic>.from(
        (inviteRes is List ? inviteRes.first : inviteRes) as Map,
      );
      final code = inviteRow['code'] as String;

      final coupleRes = await wifeClient.rpc('accept_pairing_invite', params: {
        'p_code': code,
      });
      final coupleRow = Map<String, dynamic>.from(
        (coupleRes is List ? coupleRes.first : coupleRes) as Map,
      );
      final coupleId = coupleRow['id'] as String;

      // Window: use a small custom window (5 days) so the test doesn't need
      // to seed 30 days of data. Days, newest -> oldest: yesterday (1),
      // 2 days ago, 3 days ago, 4 days ago, 5 days ago.
      const windowDays = 5;
      final yesterday = _daysAgo(1);
      final twoDaysAgo = _daysAgo(2);
      final threeDaysAgo = _daysAgo(3);
      final fourDaysAgo = _daysAgo(4);
      final fiveDaysAgo = _daysAgo(5);

      // Wife's cycle covers yesterday and the day before (2 exempt days),
      // marked PRIVATE (the default the app uses).
      await wifeClient.from('cycle_records').insert({
        'user_id': wifeId,
        'couple_id': coupleId,
        'started_on': _d(twoDaysAgo),
        'ended_on': _d(yesterday),
        'visibility': 'private',
      });

      // No prayer_logs on the exempt days (yesterday / two days ago).
      // Full (5 prayed) prayer_logs on the 3 non-exempt earlier days.
      const prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      for (final day in [threeDaysAgo, fourDaysAgo, fiveDaysAgo]) {
        await wifeClient.from('prayer_logs').insert([
          for (final p in prayers)
            {
              'couple_id': coupleId,
              'user_id': wifeId,
              'date': _d(day),
              'prayer': p,
              'status': 'prayed',
            },
        ]);
      }

      // --- (1) Privacy: husband cannot read the wife's cycle row directly.
      final directRead = await husbandClient
          .from('cycle_records')
          .select()
          .eq('user_id', wifeId);
      expect(directRead, isEmpty,
          reason: 'husband must not be able to read the wife\'s private '
              'cycle_records row via normal RLS-gated select');

      // --- (2) Fairness: RPC (called as the husband) returns the wife's
      // exemption-applied score, not a naive one.
      final rpcRes = await husbandClient
          .rpc('get_couple_scoreboard', params: {'p_window_days': windowDays});
      final rows = (rpcRes as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      expect(rows.length, 2);
      final wifeRow = rows.firstWhere((r) => r['member_id'] == wifeId);

      // Non-exempt days in the 5-day window: 3 (three/four/five days ago).
      // due = 3 * 5 = 15. If the exemption were ignored, due would count
      // all 5 window days => 25 — the two values must differ, and the
      // returned due must be the exemption-applied (lower) one.
      const naiveDueIfExemptionIgnored = windowDays * 5; // 25
      const expectedDue = 3 * 5; // 15
      expect(expectedDue, isNot(equals(naiveDueIfExemptionIgnored)));

      expect(wifeRow['due'], expectedDue);
      expect(wifeRow['prayed'], 15); // full 5/5 on all 3 non-exempt days
      expect(wifeRow['current_streak'], 3);
      expect(wifeRow['longest_streak'], 3);
    },
  );
}
