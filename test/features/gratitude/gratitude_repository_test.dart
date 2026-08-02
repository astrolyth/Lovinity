// test/features/gratitude/gratitude_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Same pairing/cleanup
// pattern as test/features/chat/chat_repository_test.dart.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/gratitude/data/gratitude_repository.dart';

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
    email: 'gratitude-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'gratitude-b-$stamp@test.local',
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
      'watchAll never returns a partner\'s unrevealed note, but does return one\'s own and a revealed one',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = GratitudeRepository(clientA);
    final repoB = GratitudeRepository(clientB);

    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      body: 'A private note from A',
      revealToSpouse: false,
    );
    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      body: 'A revealed note from A',
      revealToSpouse: true,
    );

    // B's view: sees the revealed note's real body, and must NOT receive
    // the private note at all (not even a redacted placeholder row).
    final bView = await repoB
        .watchAll(coupleId: pairing.coupleId, selfUserId: pairing.userB)
        .first;
    expect(bView.map((n) => n.body), ['A revealed note from A']);

    // A's own view: sees BOTH of their own notes regardless of reveal state.
    final aView = await repoA
        .watchAll(coupleId: pairing.coupleId, selfUserId: pairing.userA)
        .first;
    expect(
      aView.map((n) => n.body).toSet(),
      {'A private note from A', 'A revealed note from A'},
    );
  });
}
