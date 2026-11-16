// Integration test against LOCAL Supabase, covering per-member day anchoring
// in `get_couple_scoreboard`
// (supabase/migrations/20260806000001_scoreboard_per_member_local_day.sql).
//
// The RPC used to anchor BOTH members' windows on a single date supplied by
// whoever called it. A caller's "today" is not their spouse's today, so for a
// couple in distant zones the further-ahead spouse had her most recent
// COMPLETED day excluded from the window, while a day still in progress for
// her was scored as finished — resetting `v_run` and setting `v_broken`. Her
// current streak therefore displayed as BROKEN on her husband's device while
// her own device showed it intact. Same class of falsehood as the prayer log
// itself: real, correct data presented as absence.
//
// The couple here sits 25 hours apart (Kiritimati UTC+14 / Niue UTC-11), so
// their local calendar days ALWAYS differ regardless of when this test runs.
// Each spouse completes all five prayers on their own local yesterday; with a
// one-day window, each must score a full day and a live streak.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/local_day.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const _husbandTz = 'Pacific/Kiritimati'; // UTC+14
const _wifeTz = 'Pacific/Niue'; // UTC-11

SupabaseClient _anonClient() => SupabaseClient(
      _supabaseUrl,
      _anonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

void main() {
  setUpAll(() async => initTimezones());

  final adminClient = SupabaseClient(
    _supabaseUrl,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  test(
    'each member\'s scoreboard window is anchored on their OWN local day, so '
    'a distant spouse\'s completed day is counted and her streak survives',
    () async {
      final husbandClient = _anonClient();
      final wifeClient = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final signUpHusband = await husbandClient.auth.signUp(
        email: 'sb-tz-husband-$stamp@example.com',
        password: 'password123',
      );
      final signUpWife = await wifeClient.auth.signUp(
        email: 'sb-tz-wife-$stamp@example.com',
        password: 'password123',
      );
      final husbandId = signUpHusband.user!.id;
      final wifeId = signUpWife.user!.id;

      addTearDown(() async {
        await adminClient.auth.admin.deleteUser(husbandId);
        await adminClient.auth.admin.deleteUser(wifeId);
      });

      await husbandClient
          .from('users')
          .update({'gender': 'male', 'timezone': _husbandTz}).eq(
              'id', husbandId);
      await wifeClient
          .from('users')
          .update({'gender': 'female', 'timezone': _wifeTz}).eq('id', wifeId);

      final inviteRes = await husbandClient.rpc('create_pairing_invite');
      final inviteRow = Map<String, dynamic>.from(
        (inviteRes is List ? inviteRes.first : inviteRes) as Map,
      );
      final coupleRes = await wifeClient.rpc('accept_pairing_invite',
          params: {'p_code': inviteRow['code'] as String});
      final coupleRow = Map<String, dynamic>.from(
        (coupleRes is List ? coupleRes.first : coupleRes) as Map,
      );
      final coupleId = coupleRow['id'] as String;

      // Each spouse's OWN local yesterday — the day each of them just
      // finished. These are genuinely different dates.
      final now = DateTime.now().toUtc();
      final husbandYesterday =
          dayKey(dayForOffset(tzId: _husbandTz, offset: 1, at: now));
      final wifeYesterday =
          dayKey(dayForOffset(tzId: _wifeTz, offset: 1, at: now));
      expect(
        husbandYesterday,
        isNot(equals(wifeYesterday)),
        reason: '25 hours apart — their local days must differ, or this test '
            'is not exercising the bug',
      );

      const prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      Future<void> seedFullDay(
        SupabaseClient client,
        String userId,
        String date,
      ) =>
          client.from('prayer_logs').insert([
            for (final p in prayers)
              {
                'couple_id': coupleId,
                'user_id': userId,
                'date': date,
                'prayer': p,
                'status': 'prayed',
              },
          ]);

      await seedFullDay(husbandClient, husbandId, husbandYesterday);
      await seedFullDay(wifeClient, wifeId, wifeYesterday);

      // A one-day window is exactly "each member's own yesterday".
      final rpcRes = await husbandClient
          .rpc('get_couple_scoreboard', params: {'p_window_days': 1});
      final rows = (rpcRes as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      expect(rows.length, 2);

      final husbandRow = rows.firstWhere((r) => r['member_id'] == husbandId);
      final wifeRow = rows.firstWhere((r) => r['member_id'] == wifeId);

      // The caller (husband) was always scored correctly, even before the fix
      // — his own local day was the one being used for everybody.
      expect(husbandRow['prayed'], 5);
      expect(husbandRow['due'], 5);
      expect(husbandRow['current_streak'], 1);

      // The wife is the regression. Anchored on the husband's day, her rows
      // fall outside the window entirely: prayed 0, due 5, streak 0 — a
      // completed day rendered as a failed one.
      expect(
        wifeRow['prayed'],
        5,
        reason: 'her completed day must be counted, not skipped over',
      );
      expect(wifeRow['due'], 5);
      expect(
        wifeRow['current_streak'],
        1,
        reason: 'her streak is intact on her own device and must be intact '
            'here too',
      );

      // Symmetry: the answer must not depend on who asked. Called as the
      // wife, both members' figures are identical.
      final asWifeRes = await wifeClient
          .rpc('get_couple_scoreboard', params: {'p_window_days': 1});
      final asWifeRows = (asWifeRes as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      for (final id in [husbandId, wifeId]) {
        final fromHusband = rows.firstWhere((r) => r['member_id'] == id);
        final fromWife = asWifeRows.firstWhere((r) => r['member_id'] == id);
        expect(
          fromWife['prayed'],
          fromHusband['prayed'],
          reason: 'both spouses must see the same score for $id',
        );
        expect(fromWife['current_streak'], fromHusband['current_streak']);
      }
    },
  );
}
