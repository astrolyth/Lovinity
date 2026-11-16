// test/features/duas/dua_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Same pairing/cleanup
// pattern as test/features/gratitude/gratitude_repository_test.dart, which
// proves the identical class of bug for gratitude_notes.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/duas/data/dua_repository.dart';

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
    email: 'dua-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'dua-b-$stamp@test.local',
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
      'RLS blocks a partner from reading or writing a private dua directly -- '
      'querying/updating the table raw (bypassing DuaRepository/duasProvider\'s '
      'client-side filter) must withhold the private one and pass through '
      'only the shared one', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = DuaRepository(clientA);

    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      title: 'A private dua from A',
      visibility: 'private',
    );
    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      title: 'A shared dua from A',
      visibility: 'shared',
    );

    // Bypass DuaRepository entirely: query the table raw, as B, with B's
    // own JWT. If RLS is doing its job, the private row simply isn't in the
    // result set -- not filtered by us, never sent over the wire.
    final rawRows = await clientB
        .from('duas')
        .select()
        .eq('couple_id', pairing.coupleId);
    final titles = rawRows.map((r) => r['title'] as String).toSet();

    // Non-vacuous: B does receive the shared dua, so a blanket-deny bug
    // (e.g. an overly broad policy) would fail this assertion rather than
    // pass it.
    expect(titles, contains('A shared dua from A'));
    expect(titles, isNot(contains('A private dua from A')));

    // Also confirm B cannot update A's private dua directly.
    final privateRow = await clientA
        .from('duas')
        .select()
        .eq('couple_id', pairing.coupleId)
        .eq('title', 'A private dua from A')
        .single();
    final privateId = privateRow['id'] as String;

    final updateResult = await clientB
        .from('duas')
        .update({'visibility': 'shared'}).eq('id', privateId).select();
    expect(updateResult, isEmpty,
        reason: 'B must not be able to update A\'s private dua');

    final stillPrivate =
        await clientA.from('duas').select().eq('id', privateId).single();
    expect(stillPrivate['visibility'], 'private');
  });

  test(
      'set_dua_answered RPC lets a partner mark a SHARED dua answered but '
      'rejects the same call against a PRIVATE dua, leaving it unchanged',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = DuaRepository(clientA);
    final repoB = DuaRepository(clientB);

    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      title: 'RPC shared dua from A',
      visibility: 'shared',
    );
    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      title: 'RPC private dua from A',
      visibility: 'private',
    );

    final sharedRow = await clientA
        .from('duas')
        .select()
        .eq('couple_id', pairing.coupleId)
        .eq('title', 'RPC shared dua from A')
        .single();
    final sharedId = sharedRow['id'] as String;

    final privateRow = await clientA
        .from('duas')
        .select()
        .eq('couple_id', pairing.coupleId)
        .eq('title', 'RPC private dua from A')
        .single();
    final privateId = privateRow['id'] as String;

    // (a) B, the non-author, marks A's SHARED dua as answered through the
    // repository -- this is the "either partner can close a shared dua"
    // feature the app's dua list UI relies on.
    await repoB.setAnswered(sharedId, note: 'Alhamdulillah, from B');

    final sharedAfter =
        await clientA.from('duas').select().eq('id', sharedId).single();
    expect(sharedAfter['is_answered'], isTrue);
    expect(sharedAfter['answered_note'], 'Alhamdulillah, from B');

    // (b) B attempts the same RPC against A's PRIVATE dua -- must be
    // rejected, and the row must be left completely unchanged.
    await expectLater(
      repoB.setAnswered(privateId, note: 'should not work'),
      throwsA(anything),
    );

    final privateAfter =
        await clientA.from('duas').select().eq('id', privateId).single();
    expect(privateAfter['is_answered'], isFalse);
    expect(privateAfter['answered_note'], isNull);
  });
}
