// test/features/chat/chat_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Mocktail cannot mock the
// Supabase builder chain (established in test/integration/signal_server_test.dart
// and test/features/scoring/scoreboard_repository_test.dart), so this exercises
// ChatRepository against a real database: two throwaway users are signed up and
// paired into a real couple via the create_pairing_invite/accept_pairing_invite
// RPCs, then `sendEnvelopes` is asserted to write a real message_envelopes row
// (cipher_type + bytea ciphertext intact) readable by the recipient, and
// `deleteEnvelope` is asserted to remove it.
@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/crypto/signal_session_service.dart';
import 'package:lovinity/features/chat/data/chat_repository.dart';

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
    email: 'chat-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'chat-b-$stamp@test.local',
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
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test(
      'sendEnvelopes writes an envelope the recipient can read; deleteEnvelope removes it',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final senderRepo = ChatRepository(clientA);
    final recipientRepo = ChatRepository(clientB);

    final ciphertext = Uint8List.fromList([5, 1, 171, 0, 255, 42]);
    final result = await senderRepo.sendEnvelopes(
      senderDeviceNum: 1,
      copies: [
        EncryptedCopy(
          userId: pairing.userB,
          deviceNum: 1,
          ciphertext: ciphertext,
          cipherType: 3,
        ),
      ],
    );

    expect(result.messageId, isNotEmpty);
    expect(result.createdAt, isNotNull);

    // The recipient reads exactly one envelope for that message, with
    // cipher_type and ciphertext (bytea) intact. Selected directly (not via
    // watchInbox) so the assertion doesn't depend on realtime delivery.
    final rows = await clientB
        .from('message_envelopes')
        .select()
        .eq('message_id', result.messageId);

    expect(rows.length, 1);
    final row = Map<String, dynamic>.from(rows.first as Map);
    expect(row['cipher_type'], 3);
    expect(row['recipient_id'], pairing.userB);

    final rawBytea = row['ciphertext'] as String;
    final hex = rawBytea.startsWith(r'\x') ? rawBytea.substring(2) : rawBytea;
    final decoded = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < decoded.length; i++) {
      decoded[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    expect(decoded, ciphertext);

    final envelopeId = row['id'] as String;
    await recipientRepo.deleteEnvelope(envelopeId);

    final rowsAfterDelete = await clientB
        .from('message_envelopes')
        .select()
        .eq('message_id', result.messageId);
    expect(rowsAfterDelete, isEmpty);
  });

  test('uploadAttachment/downloadAttachment round-trips ciphertext via the couple path',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await _pairCouple(clientA, clientB, stamp);
    final coupleId = await clientA.rpc('current_couple') as String;

    final senderRepo = ChatRepository(clientA);
    final recipientRepo = ChatRepository(clientB);
    final storageKey = '$coupleId/attachment-$stamp';
    // Every possible byte value 0-255, not just the ASCII-safe low range:
    // real ciphertext is uniformly random, and a naive text-based encoding
    // anywhere in the upload/download path would only corrupt the high bytes.
    final ciphertext = Uint8List.fromList(List.generate(256, (i) => i));

    await senderRepo.uploadAttachment(storageKey, ciphertext);
    final downloaded = await recipientRepo.downloadAttachment(storageKey);

    expect(downloaded, ciphertext);
  });

  test('an unrelated user cannot download another couple\'s attachment', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await _pairCouple(clientA, clientB, stamp);
    final coupleId = await clientA.rpc('current_couple') as String;

    final senderRepo = ChatRepository(clientA);
    final storageKey = '$coupleId/attachment-outsider-$stamp';
    await senderRepo.uploadAttachment(storageKey, Uint8List.fromList([1, 2, 3]));

    final outsiderClient = _anonClient();
    final outsiderSignUp = await outsiderClient.auth.signUp(
      email: 'chat-outsider-$stamp@test.local',
      password: 'password123',
    );
    addTearDown(() => adminClient.auth.admin.deleteUser(outsiderSignUp.user!.id));
    final outsiderRepo = ChatRepository(outsiderClient);

    await expectLater(
      outsiderRepo.downloadAttachment(storageKey),
      throwsA(anything),
    );
  });
}
