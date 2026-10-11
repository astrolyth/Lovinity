// Integration test against LOCAL Supabase for the future-letter seal.
//
// This is the security claim of the whole feature: a letter written today and
// dated for an anniversary years away must not be readable by its recipient
// before then — not through the app, and not by calling the API directly.
//
// Before 20260807000004 the bulk RLS loop gave `future_letters` a blanket
// `for all using (is_couple_member(couple_id))` policy, so the recipient could
// select the ciphertext the moment it was written and the unlock date was
// enforced only by the client choosing not to decrypt. These tests exercise
// the server, using the recipient's own JWT, which is exactly the path a
// modified client would take.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/letter_crypto.dart';
import 'package:lovinity/features/letters/data/letter_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

Future<String> _signUp(
    SupabaseClient client, String email, String gender) async {
  final res = await client.auth.signUp(email: email, password: 'password123');
  final id = res.user!.id;
  addTearDown(() => adminClient.auth.admin.deleteUser(id));
  await client.from('users').update({'gender': gender}).eq('id', id);
  return id;
}

Future<String> _pair(SupabaseClient a, SupabaseClient b) async {
  final inviteRes = await a.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  await b.rpc('accept_pairing_invite',
      params: {'p_code': inviteRow['code'] as String});
  return await a.rpc('current_couple') as String;
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test('the recipient cannot read a sealed letter, but can once it opens',
      () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'let-h-$stamp@test.local', 'male');
    await _signUp(wife, 'let-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final key = await generateLetterKey();
    final authorRepo = LetterRepository(husband);
    final recipientRepo = LetterRepository(wife);

    final sealedId = await authorRepo.seal(
      coupleId: coupleId,
      authorId: husbandId,
      body: 'Happy tenth anniversary.',
      unlockAt: DateTime.now().add(const Duration(days: 3650)),
      letterKey: key,
    );

    // The author always sees their own letter — they must be able to review or
    // withdraw it.
    final asAuthor = await authorRepo.watchLetters(coupleId: coupleId).first;
    expect(asAuthor.map((l) => l.id), [sealedId]);

    // The recipient sees nothing at all. Not a redacted row, not a countdown —
    // the row itself is withheld, so even the existence of the surprise is not
    // disclosed by the API.
    final asRecipient =
        await recipientRepo.watchLetters(coupleId: coupleId).first;
    expect(asRecipient, isEmpty,
        reason: 'a sealed letter must not reach its recipient');

    // And fetching the ciphertext directly by id — the route a modified client
    // would take — returns nothing.
    expect(
      await recipientRepo.openBody(letterId: sealedId, letterKey: key),
      isNull,
      reason: 'the ciphertext must not be served before unlock_at',
    );

    // A letter that unlocks in a few seconds, so the transition is exercised
    // on the real clock rather than simulated by rewriting the row. This also
    // proves the boundary is `now()` evaluated server-side per request, not a
    // value cached when the row was written.
    final openId = await authorRepo.seal(
      coupleId: coupleId,
      authorId: husbandId,
      body: 'You made it.',
      unlockAt: DateTime.now().add(const Duration(seconds: 3)),
      letterKey: key,
    );

    expect(
      await recipientRepo.openBody(letterId: openId, letterKey: key),
      isNull,
      reason: 'still sealed a moment before its unlock time',
    );

    await Future<void>.delayed(const Duration(seconds: 5));

    final opened =
        await recipientRepo.openBody(letterId: openId, letterKey: key);
    expect(opened, 'You made it.',
        reason: 'the same request must succeed once unlock_at has passed');

    // The still-sealed one remains sealed — unlocking one letter must not
    // widen access to the rest.
    expect(
      await recipientRepo.openBody(letterId: sealedId, letterKey: key),
      isNull,
    );
  });

  test('a letter cannot be back-dated to unlock immediately', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'let2-h-$stamp@test.local', 'male');
    await _signUp(wife, 'let2-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    // The check constraint requires unlock_at > created_at, so "sealing"
    // something that is already open is rejected rather than quietly behaving
    // like an ordinary message.
    await expectLater(
      LetterRepository(husband).seal(
        coupleId: coupleId,
        authorId: husbandId,
        body: 'not really sealed',
        unlockAt: DateTime.now().subtract(const Duration(days: 1)),
        letterKey: await generateLetterKey(),
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('an outsider cannot read any of the couple\'s letters', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final outsider = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'let3-h-$stamp@test.local', 'male');
    await _signUp(wife, 'let3-w-$stamp@test.local', 'female');
    await _signUp(outsider, 'let3-o-$stamp@test.local', 'male');
    final coupleId = await _pair(husband, wife);

    final key = await generateLetterKey();
    final id = await LetterRepository(husband).seal(
      coupleId: coupleId,
      authorId: husbandId,
      body: 'private',
      unlockAt: DateTime.now().add(const Duration(seconds: 2)),
      letterKey: key,
    );
    await Future<void>.delayed(const Duration(seconds: 4));

    // Unlocking is about time, not membership: even fully open, the letter
    // belongs to the couple alone.
    expect(
      await LetterRepository(husband).openBody(letterId: id, letterKey: key),
      'private',
      reason: 'sanity check that the letter really did unlock',
    );
    expect(
      await LetterRepository(outsider)
          .openBody(letterId: id, letterKey: key),
      isNull,
    );
  });

  test('the author can withdraw a sealed letter', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'let4-h-$stamp@test.local', 'male');
    await _signUp(wife, 'let4-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repo = LetterRepository(husband);
    final id = await repo.seal(
      coupleId: coupleId,
      authorId: husbandId,
      body: 'second thoughts',
      unlockAt: DateTime.now().add(const Duration(days: 100)),
      letterKey: await generateLetterKey(),
    );

    await repo.withdraw(id);
    expect(await repo.watchLetters(coupleId: coupleId).first, isEmpty);
  });
}
