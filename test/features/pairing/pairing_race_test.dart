// Integration test against the LOCAL Supabase instance: two accepts that
// involve the same user, run at the same moment, must not pair that user
// twice. accept_pairing_invite locks both users (see
// supabase/migrations/20261115000001_security_hardening.sql); without the
// locks both calls pass their "not already paired" checks and A ends up in
// two active couples.
//
// A race only fails when the two calls actually overlap, so it runs several
// rounds to make an overlap near-certain.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const _rounds = 8;

SupabaseClient _anonClient() => SupabaseClient(
      _supabaseUrl,
      _anonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

void main() {
  final admin = SupabaseClient(
    _supabaseUrl,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Future<(SupabaseClient, String)> newUser(String tag, String gender) async {
    final client = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final res = await client.auth.signUp(
      email: 'pair-race-$tag-$stamp@example.com',
      password: 'password123',
    );
    final id = res.user!.id;
    addTearDown(() => admin.auth.admin.deleteUser(id));
    await client.from('users').update({'gender': gender}).eq('id', id);
    return (client, id);
  }

  Future<String> invite(SupabaseClient client) async {
    final res = await client.rpc('create_pairing_invite');
    return ((res is List ? res.first : res) as Map)['code'] as String;
  }

  Future<bool> accept(SupabaseClient client, String code) async {
    try {
      await client.rpc('accept_pairing_invite', params: {'p_code': code});
      return true;
    } on PostgrestException {
      return false;
    }
  }

  test('concurrent accepts never put one user in two active couples',
      () async {
    for (var round = 0; round < _rounds; round++) {
      final (a, aId) = await newUser('a$round', 'male');
      final (b, _) = await newUser('b$round', 'female');
      final (c, _) = await newUser('c$round', 'female');

      final aCode = await invite(a);
      final cCode = await invite(c);

      // B accepts A's invite while A accepts C's: both involve A.
      final results = await Future.wait([accept(b, aCode), accept(a, cCode)]);

      // A's own session: couples is granted to authenticated, not service_role.
      final couples = await a
          .from('couples')
          .select('id')
          .or('member_a.eq.$aId,member_b.eq.$aId')
          .eq('status', 'active');
      expect(couples, hasLength(1),
          reason: 'round $round: A must be in exactly one active couple');
      expect(results.where((ok) => ok), hasLength(1),
          reason: 'round $round: exactly one accept may succeed');
    }
  });
}
