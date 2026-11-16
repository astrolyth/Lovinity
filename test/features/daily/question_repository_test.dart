// test/features/daily/question_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Mocktail cannot mock the
// Supabase builder chain (established in test/features/chat/chat_repository_test.dart),
// so this exercises QuestionRepository against a real database: two throwaway
// users are signed up and paired into a real couple via the
// create_pairing_invite/accept_pairing_invite RPCs, then currentQuestion() is
// asserted to return the same question for both partners and to advance the
// queue only once both partners have submitted an answer.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/daily/data/question_repository.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

// Service-role key for teardown only (admin.deleteUser). Same throwaway-user
// cleanup pattern as the other integration tests in this project.
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

/// Signs up two throwaway users and pairs them into a real couple via the
/// same create_pairing_invite/accept_pairing_invite RPC flow the app uses
/// (accept_pairing_invite requires both members to have a distinct gender
/// set first). Registers addTearDown cleanup for both users.
Future<({String userA, String userB})> _pairCouple(
  SupabaseClient clientA,
  SupabaseClient clientB,
  int stamp,
) async {
  final signUpA = await clientA.auth.signUp(
    email: 'daily-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'daily-b-$stamp@test.local',
    password: 'password123',
  );
  final userA = signUpA.user!.id;
  final userB = signUpB.user!.id;

  addTearDown(() async {
    await adminClient.auth.admin.deleteUser(userA);
  });
  addTearDown(() async {
    await adminClient.auth.admin.deleteUser(userB);
  });

  await clientA.from('users').update({'gender': 'male'}).eq('id', userA);
  await clientB.from('users').update({'gender': 'female'}).eq('id', userB);

  final inviteRes = await clientA.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  final code = inviteRow['code'] as String;

  await clientB.rpc('accept_pairing_invite', params: {'p_code': code});

  return (userA: userA, userB: userB);
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(_url, _serviceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
  });

  test('currentQuestion returns the same question for both partners, and '
      'advances only once both have answered', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = QuestionRepository(clientA);
    final repoB = QuestionRepository(clientB);

    final qA = await repoA.currentQuestion();
    final qB = await repoB.currentQuestion();
    expect(qA, isNotNull);
    expect(qA!.id, qB!.id, reason: 'both partners must see the same question');

    final coupleId = await clientA.rpc('current_couple') as String;

    await repoA.submit(
        coupleId: coupleId, userId: pairing.userA, questionId: qA.id, answer: 'a');
    expect((await repoA.currentQuestion())!.id, qA.id,
        reason: 'one answer must not advance the queue');

    await repoB.submit(
        coupleId: coupleId, userId: pairing.userB, questionId: qA.id, answer: 'b');
    expect((await repoA.currentQuestion())!.id, isNot(qA.id),
        reason: 'the queue must advance once both partners answered');
  });
}
