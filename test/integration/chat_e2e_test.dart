// test/integration/chat_e2e_test.dart
//
// The headline end-to-end proof: two real devices — Alice and Bob — each
// with their own in-memory Drift database and KeyVault, registered through
// the real ensureRegistered path and paired into a real couple via the
// create_pairing_invite/accept_pairing_invite RPCs (same harness as
// test/integration/signal_server_test.dart and
// test/features/chat/chat_repository_test.dart). ChatService is driven for
// each side over a genuine SignalSessionService (real X3DH + Double Ratchet)
// against local Supabase. No mocks of crypto or the database.
@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_registration.dart';
import 'package:lovinity/core/crypto/signal_session_service.dart';
import 'package:lovinity/core/storage/media_cache.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/chat/data/chat_repository.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/domain/chat_service.dart';

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

/// One real device end-to-end: its own authenticated Supabase client, its own
/// in-memory Drift DB + isolated KeyVault, registered via the real
/// [ensureRegistered] path, and a [ChatService] wired over a genuine
/// [SignalSessionService] talking to the live server
/// ([SupabasePreKeyBundleSource] + [SupabaseDeviceRegistrar]).
class _Party {
  _Party(this.client, this.userId);
  final SupabaseClient client;
  final String userId;
  late SignalDb db;
  late KeyVault vault;
  late int deviceNum;
  late SignalSessionService session;
  late ChatRepository repo;
  late ChatStore store;
  late ChatService chat;
  late _InMemoryMediaCache cache;
}

class _InMemoryMediaCache implements MediaCache {
  final Map<String, Uint8List> written = {};

  @override
  Future<String> write(String key, Uint8List bytes) async {
    written[key] = bytes;
    return 'memory://$key';
  }

  @override
  Future<void> clear() async => written.clear();
}

Future<_Party> _makeParty(
  SupabaseClient client,
  String userId,
  String spouseId,
) async {
  final p = _Party(client, userId);
  p.db = SignalDb.memory();
  p.vault = KeyVault(InMemorySecureStore());
  addTearDown(() => p.db.close());

  final registrar = SupabaseDeviceRegistrar(client);
  p.deviceNum =
      await ensureRegistered(db: p.db, vault: p.vault, registrar: registrar);

  p.session = SignalSessionService(
    db: p.db,
    vault: p.vault,
    bundles: SupabasePreKeyBundleSource(client),
    selfUserId: userId,
    selfDeviceNum: p.deviceNum,
  );
  p.repo = ChatRepository(client);
  p.store = ChatStore(p.db);
  final coupleId = await client.rpc('current_couple') as String;
  p.cache = _InMemoryMediaCache();
  p.chat = ChatService(
    session: p.session,
    repo: p.repo,
    store: p.store,
    selfUserId: userId,
    spouseUserId: spouseId,
    selfDeviceNum: p.deviceNum,
    coupleId: coupleId,
    cache: p.cache,
  );
  return p;
}

/// Signs up two throwaway users, gives them distinct genders (required by
/// accept_pairing_invite), and pairs them into a real couple via the same
/// create_pairing_invite/accept_pairing_invite RPC flow the app uses.
/// Registers addTearDown cleanup for both users.
Future<({String userA, String userB})> _pairCouple(
  SupabaseClient clientA,
  SupabaseClient clientB,
  int stamp,
) async {
  final signUpA = await clientA.auth.signUp(
    email: 'e2e-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'e2e-b-$stamp@test.local',
    password: 'password123',
  );
  final userA = signUpA.user!.id;
  final userB = signUpB.user!.id;

  addTearDown(() async => adminClient.auth.admin.deleteUser(userA));
  addTearDown(() async => adminClient.auth.admin.deleteUser(userB));

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

Map<String, dynamic> _row(dynamic r) => Map<String, dynamic>.from(r as Map);

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test(
      'two devices: send -> deliver -> read receipt -> react -> idempotent redelivery',
      () async {
    final aliceClient = _anonClient();
    final bobClient = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(aliceClient, bobClient, stamp);

    final alice = await _makeParty(aliceClient, pairing.userA, pairing.userB);
    final bob = await _makeParty(bobClient, pairing.userB, pairing.userA);

    // --- Alice sends "salam" ------------------------------------------------
    await alice.chat.sendText('salam');

    // Fetch Bob's inbox envelope with a direct select (deterministic; doesn't
    // depend on realtime delivery timing the way watchInbox would).
    final inboxRows = await bobClient
        .from('message_envelopes')
        .select()
        .eq('recipient_id', pairing.userB);
    expect(inboxRows.length, 1,
        reason: 'one device per side => exactly one envelope for bob');
    final textEnvelope = _row(inboxRows.first);
    final messageId = textEnvelope['message_id'] as String;

    await bob.chat.handleInboxRow(textEnvelope);

    // Bob's local store has a real decrypted, delivered message.
    expect(await bob.store.messageExists(messageId), isTrue);
    final bobRows = await bob.store.watchConversation().first;
    final bobMsg = bobRows.singleWhere((r) => r.id == messageId);
    expect(bobMsg.body, 'salam');
    expect(bobMsg.status, 'delivered');

    // handleInboxRow marks delivered itself for a spouse-sent message; the
    // server row reflects that, visible to Alice too (couple-scoped RLS).
    final afterDeliverRows =
        await aliceClient.from('messages').select().eq('id', messageId);
    expect(afterDeliverRows.length, 1);
    final afterDeliver = _row(afterDeliverRows.first);
    expect(afterDeliver['delivered_at'], isNotNull);
    expect(afterDeliver['read_at'], isNull);

    // The envelope is spent: gone from the server once Bob has handled it.
    final envAfterHandle = await bobClient
        .from('message_envelopes')
        .select()
        .eq('id', textEnvelope['id'] as String);
    expect(envAfterHandle, isEmpty);

    // --- Bob marks the message read -----------------------------------------
    await bob.repo.markRead(messageId);

    final afterReadRows =
        await aliceClient.from('messages').select().eq('id', messageId);
    expect(afterReadRows.length, 1);
    final afterRead = _row(afterReadRows.first);
    expect(afterRead['read_at'], isNotNull);

    // --- Alice reacts with a heart ------------------------------------------
    await alice.chat
        .sendReaction(targetMessageId: messageId, emoji: '❤️', add: true);

    final reactionInbox = await bobClient
        .from('message_envelopes')
        .select()
        .eq('recipient_id', pairing.userB);
    expect(reactionInbox.length, 1,
        reason: 'the earlier text envelope was already spent; this is the '
            'reaction envelope only');
    final reactionEnvelope = _row(reactionInbox.first);

    await bob.chat.handleInboxRow(reactionEnvelope);

    final bobReactions = await bob.store.reactionsFor(messageId);
    expect(bobReactions.map((r) => r.emoji), contains('❤️'));

    // --- Idempotent redelivery: same text envelope handled again ------------
    // A second real decrypt of the same ciphertext would throw (Double
    // Ratchet message keys are single-use); the messageExists short-circuit
    // in ChatService.handleInboxRow must prevent that from ever being tried.
    await bob.chat.handleInboxRow(textEnvelope);

    final bobRowsAfterRedeliver = await bob.store.watchConversation().first;
    expect(bobRowsAfterRedeliver.where((r) => r.id == messageId), hasLength(1),
        reason: 'redelivery of the same logical message must not duplicate it');

    final envAfterRedeliver = await bobClient
        .from('message_envelopes')
        .select()
        .eq('id', textEnvelope['id'] as String);
    expect(envAfterRedeliver, isEmpty,
        reason: 'the envelope was already spent; redelivery must not '
            'resurrect it');
  });

  test('attachment: send -> deliver -> download decrypts to the original bytes',
      () async {
    final aliceClient = _anonClient();
    final bobClient = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(aliceClient, bobClient, stamp);

    final alice = await _makeParty(aliceClient, pairing.userA, pairing.userB);
    final bob = await _makeParty(bobClient, pairing.userB, pairing.userA);

    final originalBytes = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final thumbnail = Uint8List.fromList([1, 2, 3, 4, 5]);

    await alice.chat.sendPhoto(
      bytes: originalBytes,
      mimeType: 'image/jpeg',
      width: 800,
      height: 600,
      thumbnailBytes: thumbnail,
    );

    // Direct select rather than watchInbox: deterministic, no dependence on
    // realtime delivery timing (same pattern as the text-message test above).
    final inboxRows = await bobClient
        .from('message_envelopes')
        .select()
        .eq('recipient_id', pairing.userB);
    expect(inboxRows.length, 1);
    final envelope = _row(inboxRows.first);
    final messageId = envelope['message_id'] as String;

    await bob.chat.handleInboxRow(envelope);

    expect(await bob.store.messageExists(messageId), isTrue);
    final bobRows = await bob.store.watchConversation().first;
    final bobMsg = bobRows.singleWhere((r) => r.id == messageId);
    expect(bobMsg.attachmentKind, 'photo');
    expect(bobMsg.downloadStatus, 'none',
        reason: 'attachments are tap-to-load, never auto-downloaded');

    await bob.chat.downloadAttachment(messageId);

    final bobRowsAfterDownload = await bob.store.watchConversation().first;
    final bobMsgAfterDownload =
        bobRowsAfterDownload.singleWhere((r) => r.id == messageId);
    expect(bobMsgAfterDownload.downloadStatus, 'downloaded');
    expect(bob.cache.written[messageId], originalBytes,
        reason: 'the decrypted bytes must exactly match what Alice sent');

    // Alice's own row ends up locally cached too, so re-opening her own
    // photo never round-trips through Storage.
    final aliceRow = await alice.store.messageById(messageId);
    expect(aliceRow!.status, 'sent');
    expect(aliceRow.downloadStatus, 'downloaded');
    expect(alice.cache.written[messageId], originalBytes);
  });
}
