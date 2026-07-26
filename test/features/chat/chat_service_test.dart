// test/features/chat/chat_service_test.dart
//
// Unit test for ChatService: send + inbound-decrypt orchestration. Crypto is
// REAL (two/three genuine SignalSessionServices over in-memory Drift + a fake
// bundle source), built exactly like
// test/core/crypto/signal_session_service_test.dart's round-trip test, so
// encrypt/decrypt is not stubbed. Only ChatRepository (network) is faked.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_keys.dart';
import 'package:lovinity/core/crypto/signal_registration.dart';
import 'package:lovinity/core/crypto/signal_session_service.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/chat/data/chat_repository.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/domain/chat_payload.dart';
import 'package:lovinity/features/chat/domain/chat_service.dart';

// ---------------------------------------------------------------------------
// Two/three-device crypto harness, copied from signal_session_service_test's
// round-trip setup so sendText/handleInboxRow exercise real X3DH + Double
// Ratchet, not a stub.
// ---------------------------------------------------------------------------

class _Device {
  _Device(this.userId, this.deviceNum);
  final String userId;
  final int deviceNum;
  late SignalDb db;
  late KeyVault vault;
  late _Registered generated;
  late SignalSessionService service;
  late _FakeBundles source;
}

class _Registered {
  const _Registered(this.public);
  final PublicBundle public;
}

class _RecordingRegistrar implements DeviceRegistrar {
  _RecordingRegistrar(this.deviceNum);
  final int deviceNum;
  PublicBundle? published;

  String? _deviceId;
  int? _registrationId;
  Uint8List? _identityPub;
  int? _signedPrekeyId;
  Uint8List? _signedPrekeyPub;
  Uint8List? _signedPrekeySig;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    _deviceId = deviceId;
    _registrationId = registrationId;
    _identityPub = identityPub;
    _signedPrekeyId = signedPrekeyId;
    _signedPrekeyPub = signedPrekeyPub;
    _signedPrekeySig = signedPrekeySig;
    return deviceNum;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async {
    published = PublicBundle(
      registrationId: _registrationId!,
      deviceId: _deviceId!,
      identityPub: _identityPub!,
      signedPrekeyId: _signedPrekeyId!,
      signedPrekeyPub: _signedPrekeyPub!,
      signedPrekeySig: _signedPrekeySig!,
      oneTimePrekeys: [
        for (final e in prekeys.entries) PublicPrekey(id: e.key, pub: e.value),
      ],
    );
  }

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async => 0;
}

class _FakeBundles implements PreKeyBundleSource {
  _FakeBundles(this.devices);
  final List<_Device> devices;

  @override
  Future<List<int>> deviceNumsFor(String userId) async {
    return devices.where((d) => d.userId == userId).map((d) => d.deviceNum).toList();
  }

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async {
    final matches = devices
        .where((d) => d.userId == userId && d.deviceNum == deviceNum)
        .toList();
    if (matches.isEmpty) return null;
    final d = matches.first;
    final p = d.generated.public;
    final otp = p.oneTimePrekeys.first;
    return DeviceBundle(
      deviceNum: d.deviceNum,
      registrationId: p.registrationId,
      identityPub: p.identityPub,
      signedPrekeyId: p.signedPrekeyId,
      signedPrekeyPub: p.signedPrekeyPub,
      signedPrekeySig: p.signedPrekeySig,
      oneTimePrekeyId: otp.id,
      oneTimePrekeyPub: otp.pub,
    );
  }
}

Future<_Device> _makeDevice(String userId, int deviceNum, List<_Device> registry) async {
  final d = _Device(userId, deviceNum);
  d.db = SignalDb.memory();
  d.vault = KeyVault(InMemorySecureStore());

  final registrar = _RecordingRegistrar(deviceNum);
  final assignedNum = await ensureRegistered(db: d.db, vault: d.vault, registrar: registrar);
  expect(assignedNum, deviceNum,
      reason: 'test setup assumes the fake registrar\'s device_num is used');
  d.generated = _Registered(registrar.published!);

  d.source = _FakeBundles(registry);
  d.service = SignalSessionService(
    db: d.db,
    vault: d.vault,
    bundles: d.source,
    selfUserId: userId,
    selfDeviceNum: deviceNum,
  );
  return d;
}

// ---------------------------------------------------------------------------
// Fake ChatRepository: captures sendEnvelopes/markDelivered/deleteEnvelope
// calls instead of touching the network. It must extend the real
// ChatRepository (there is no abstract interface) so ChatService's
// `required ChatRepository repo` typing is satisfied; the SupabaseClient
// passed to super is never exercised because every method is overridden.
// ---------------------------------------------------------------------------

class _FakeChatRepo extends ChatRepository {
  _FakeChatRepo() : super(SupabaseClient('http://localhost:0', 'fake-anon-key'));

  final List<({int senderDeviceNum, List<EncryptedCopy> copies, String? messageId})>
      sendEnvelopesCalls = [];
  final List<String> markDeliveredCalls = [];
  final List<String> markReadCalls = [];
  final List<String> deleteEnvelopeCalls = [];

  String nextMessageId = 'm-1';
  DateTime nextCreatedAt = DateTime.utc(2026, 1, 1);

  /// When true, the next sendEnvelopes call throws instead of succeeding
  /// (then resets to false), so tests can exercise the offline/failed path.
  bool failNextSend = false;

  @override
  Future<({String messageId, DateTime createdAt})> sendEnvelopes({
    required int senderDeviceNum,
    required List<EncryptedCopy> copies,
    String? messageId,
  }) async {
    sendEnvelopesCalls.add(
        (senderDeviceNum: senderDeviceNum, copies: copies, messageId: messageId));
    if (failNextSend) {
      failNextSend = false;
      throw Exception('network unreachable');
    }
    return (messageId: messageId ?? nextMessageId, createdAt: nextCreatedAt);
  }

  @override
  Future<void> markDelivered(String messageId) async {
    markDeliveredCalls.add(messageId);
  }

  @override
  Future<void> markRead(String messageId) async {
    markReadCalls.add(messageId);
  }

  @override
  Future<void> deleteEnvelope(String envelopeId) async {
    deleteEnvelopeCalls.add(envelopeId);
  }
}

/// Hex-encodes ciphertext the way the real `message_envelopes` bytea column
/// arrives over Supabase realtime (`\x...`), exercising ChatService's string
/// decode path rather than only the raw-bytes path.
String _hexEnvelope(List<int> b) =>
    r'\x' + b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const selfUserId = 'self-user';
  const spouseUserId = 'spouse-user';

  late List<_Device> registry;
  late _Device self1; // the device under test (backs ChatService.session)
  late _Device self2; // self's OTHER device, for multi-device sync scenarios
  late _Device spouse1;

  late _FakeChatRepo repo;
  late ChatStore store;
  late ChatService chat;

  setUp(() async {
    registry = <_Device>[];
    self1 = await _makeDevice(selfUserId, 1, registry);
    self2 = await _makeDevice(selfUserId, 2, registry);
    spouse1 = await _makeDevice(spouseUserId, 1, registry);
    registry.addAll([self1, self2, spouse1]);

    repo = _FakeChatRepo();
    store = ChatStore(self1.db);
    chat = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
    );
  });

  tearDown(() async {
    await self1.db.close();
    await self2.db.close();
    await spouse1.db.close();
  });

  test('sendText encodes, encrypts to the spouse, sends envelopes, and stores a local sent message',
      () async {
    await chat.sendText('as-salamu alaykum');

    expect(repo.sendEnvelopesCalls, hasLength(1));
    final call = repo.sendEnvelopesCalls.single;
    expect(call.senderDeviceNum, 1);
    // encryptFor fans out to the spouse's device(s) plus self's OTHER
    // devices; here that's spouse:1 and self:2.
    expect(
      call.copies.map((c) => '${c.userId}:${c.deviceNum}').toSet(),
      {'$spouseUserId:1', '$selfUserId:2'},
    );
    // The id is now client-generated (not server-assigned) and passed
    // through to sendEnvelopes as p_message_id so a receipt lands on the
    // same row as the optimistic local copy.
    expect(call.messageId, isNotNull);

    expect(await store.messageExists(call.messageId!), isTrue);
    final rows = await store.watchConversation().first;
    final row = rows.singleWhere((r) => r.id == call.messageId);
    expect(row.senderId, selfUserId);
    expect(row.body, 'as-salamu alaykum');
    expect(row.status, 'sent');
  });

  test('sendText carries replyToMessageId through to the stored message', () async {
    await chat.sendText('reply body', replyToMessageId: 'original-1');

    final rows = await store.watchConversation().first;
    final row = rows.singleWhere((r) => r.body == 'reply body');
    expect(row.replyToMessageId, 'original-1');
  });

  test('handleInboxRow decrypts a spouse TextPayload, upserts delivered, marks delivered, deletes envelope',
      () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const TextPayload(body: 'hi from spouse')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-1',
      'message_id': 'msg-inbox-1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    expect(await store.messageExists('msg-inbox-1'), isTrue);
    final rows = await store.watchConversation().first;
    final row = rows.singleWhere((r) => r.id == 'msg-inbox-1');
    expect(row.senderId, spouseUserId);
    expect(row.body, 'hi from spouse');
    expect(row.status, 'delivered');

    expect(repo.markDeliveredCalls, ['msg-inbox-1']);
    expect(repo.deleteEnvelopeCalls, ['env-1']);
  });

  test('handleInboxRow is idempotent: processing the same envelope twice yields one local message',
      () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const TextPayload(body: 'only once')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-2',
      'message_id': 'msg-inbox-2',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);
    // Second delivery of the SAME envelope (e.g. a retried realtime event).
    // A second real decrypt of the same ciphertext would throw (Double
    // Ratchet message keys are single-use); the messageExists short-circuit
    // must prevent that.
    await chat.handleInboxRow(envelope);

    final rows = await store.watchConversation().first;
    expect(rows.where((r) => r.id == 'msg-inbox-2'), hasLength(1));
    expect(repo.markDeliveredCalls.where((id) => id == 'msg-inbox-2'), hasLength(1),
        reason: 'delivered receipt must not be sent twice for one logical message');
    expect(repo.deleteEnvelopeCalls, ['env-2', 'env-2'],
        reason: 'the envelope row itself is cleaned up on every delivery');
  });

  test('handleInboxRow on a ReactionPayload applies the reaction to the target message', () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const ReactionPayload(
        targetMessageId: 'target-msg-1',
        emoji: '❤️',
        add: true,
      )),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-3',
      'message_id': 'msg-reaction-1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    final reactions = await store.reactionsFor('target-msg-1');
    expect(reactions, hasLength(1));
    expect(reactions.single.reactorId, spouseUserId);
    expect(reactions.single.emoji, '❤️');
    // A reaction payload never creates its own message row.
    expect(await store.messageExists('msg-reaction-1'), isFalse);
    expect(repo.deleteEnvelopeCalls, contains('env-3'));
  });

  test('handleInboxRow on a self-sync copy (own other device) stores sent status, no delivered receipt',
      () async {
    // self2 (our own other device) sent a message to the spouse; the
    // resulting self:1 copy is what OUR device receives to stay in sync.
    final copies = await self2.service.encryptFor(
      recipientUserId: spouseUserId,
      plaintext: encodePayload(const TextPayload(body: 'sent from my other device')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-4',
      'message_id': 'msg-self-sync-1',
      'sender_id': selfUserId,
      'sender_device_num': 2,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    final rows = await store.watchConversation().first;
    final row = rows.singleWhere((r) => r.id == 'msg-self-sync-1');
    expect(row.status, 'sent',
        reason: 'a copy from our own other device is already-sent, not delivered');
    expect(repo.markDeliveredCalls, isEmpty,
        reason: 'self-sync copies must never trigger a delivered receipt');
    expect(repo.deleteEnvelopeCalls, contains('env-4'));
  });

  test('handleInboxRow never throws on a bad envelope and leaves it for retry', () async {
    final envelope = <String, dynamic>{
      'id': 'env-bad',
      'message_id': 'msg-bad-1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(Uint8List.fromList(List.filled(40, 7))),
      'cipher_type': 3, // CiphertextMessage.prekeyType, but garbage bytes
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await expectLater(chat.handleInboxRow(envelope), completes);

    expect(await store.messageExists('msg-bad-1'), isFalse);
    expect(repo.deleteEnvelopeCalls, isNot(contains('env-bad')),
        reason: 'a bad envelope is left in place so it can be retried');
  });

  test('sendText stores a "sending" row, then "sent"; "failed" on send error', () async {
    // Happy path: after sendText, the local row exists with status 'sent'.
    await chat.sendText('salam');
    final ok = (await store.watchConversation().first).last;
    expect(ok.body, 'salam');
    expect(ok.status, 'sent');

    // Failure path: make the fake repo's sendEnvelopes throw once.
    repo.failNextSend = true;
    await chat.sendText('offline msg');
    final failed = (await store.watchConversation().first)
        .firstWhere((m) => m.body == 'offline msg');
    expect(failed.status, 'failed',
        reason: 'a failed send must leave a retryable failed row, not vanish');
  });

  test('sendReaction encodes, encrypts to the spouse, sends envelopes, and reflects the reaction locally',
      () async {
    const targetMessageId = 'target-msg-outbound';
    const emoji = '❤️';

    await chat.sendReaction(targetMessageId: targetMessageId, emoji: emoji, add: true);

    // Assertion 1: repo.sendEnvelopes was called once
    expect(repo.sendEnvelopesCalls, hasLength(1));
    final call = repo.sendEnvelopesCalls.single;
    expect(call.senderDeviceNum, 1);
    // encryptFor fans out to the spouse's device(s) plus self's OTHER devices;
    // here that's spouse:1 and self:2.
    expect(
      call.copies.map((c) => '${c.userId}:${c.deviceNum}').toSet(),
      {'$spouseUserId:1', '$selfUserId:2'},
    );

    // Assertion 2: the local store reflects the reaction immediately
    final reactions = await store.reactionsFor(targetMessageId);
    expect(reactions, hasLength(1));
    final reaction = reactions.single;
    expect(reaction.reactorId, selfUserId,
        reason: 'the sender reflects their own reaction locally immediately');
    expect(reaction.emoji, emoji);
  });

  test('ignores an envelope addressed to a DIFFERENT device (no delete, no decrypt)',
      () async {
    // This device (device 1) already processed the message for itself —
    // 'm-other' exists locally. The same logical message also has an
    // envelope row addressed to device 2 (a sibling device on this same
    // account); watchInbox filters only by recipient_id, so device 1's
    // stream still surfaces device 2's row. Without the device guard, the
    // messageExists short-circuit below would delete it before device 2
    // ever gets to fetch it.
    await store.upsertMessage(
      id: 'm-other',
      senderId: spouseUserId,
      body: 'hi from spouse',
      createdAt: DateTime.utc(2026, 1, 3),
      status: 'delivered',
    );

    final env = {
      'id': 'env-for-d2',
      'message_id': 'm-other',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 2, // NOT ours (we are device 1)
      'cipher_type': 3,
      'ciphertext': 'deadbeef',
      'created_at': DateTime(2026).toIso8601String(),
    };

    await chat.handleInboxRow(env); // chat.selfDeviceNum == 1

    expect(repo.deleteEnvelopeCalls, isEmpty,
        reason: 'must not delete a sibling device\'s envelope');
    expect(await store.messageExists('m-other'), isTrue,
        reason: 'the existing local copy for this device must be untouched');
  });

  test('processes an envelope addressed to OUR device', () async {
    // A real spouse -> us TextPayload envelope with recipient_device_num
    // equal to chat.selfDeviceNum: it must decrypt, store as delivered,
    // send the delivered receipt, and be deleted, same as before the guard.
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const TextPayload(body: 'hello device 1')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-for-d1',
      'message_id': 'msg-for-d1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1, // ours (chat.selfDeviceNum == 1)
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    expect(await store.messageExists('msg-for-d1'), isTrue);
    final rows = await store.watchConversation().first;
    final row = rows.singleWhere((r) => r.id == 'msg-for-d1');
    expect(row.status, 'delivered');
    expect(repo.markDeliveredCalls, contains('msg-for-d1'));
    expect(repo.deleteEnvelopeCalls, contains('env-for-d1'));
  });

  test('an undecryptable envelope is retried then dead-lettered, not looped forever', () async {
    // env addressed to OUR device but with garbage ciphertext that never decrypts.
    final env = {
      'id': 'bad-env', 'message_id': 'm-bad',
      'sender_id': spouseUserId, 'sender_device_num': 1,
      'recipient_device_num': chat.selfDeviceNum,
      'cipher_type': 2, 'ciphertext': 'deadbeef',
      'created_at': DateTime(2026).toIso8601String(),
    };
    // Below the threshold: retried, NOT deleted.
    for (var i = 0; i < ChatService.maxDecryptAttempts - 1; i++) {
      await chat.handleInboxRow(env);
    }
    expect(repo.deleteEnvelopeCalls, isEmpty);
    // The attempt that reaches the threshold dead-letters it.
    await chat.handleInboxRow(env);
    expect(repo.deleteEnvelopeCalls, contains('bad-env'));
    // Further ticks do nothing (already dead-lettered / not re-added).
    await chat.handleInboxRow(env);
    expect(repo.deleteEnvelopeCalls.where((e) => e == 'bad-env').length, 1);
  });

  test('serializes inbound processing so concurrent decrypts never overlap',
      () async {
    // Realtime delivers overlapping batches and Dart does not await an async
    // stream listener before the next event, so handleInboxRow can be invoked
    // concurrently. decryptFrom mutates Double Ratchet state (not
    // concurrency-safe), so inbound handling must be serialized.
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    final spy = _SpySession();
    final localRepo = _FakeChatRepo();
    final svc = ChatService(
      session: spy,
      repo: localRepo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
    );

    Map<String, dynamic> env(String id) => {
          'id': 'env-$id',
          'message_id': id,
          'sender_id': spouseUserId,
          'sender_device_num': 1,
          'recipient_device_num': 1,
          'cipher_type': 2,
          'ciphertext': 'aa',
          'created_at': DateTime.utc(2026).toIso8601String(),
        };

    await Future.wait([
      svc.handleInboxRow(env('m1')),
      svc.handleInboxRow(env('m2')),
      svc.handleInboxRow(env('m3')),
    ]);

    expect(spy.maxConcurrent, 1,
        reason: 'inbound decrypts must never overlap (ratchet state is not '
            'concurrency-safe)');
    final rows = await store.watchConversation().first;
    expect(rows.length, 3); // all three still processed + stored
  });

  test('markConversationRead reads incoming unread locally + on the server',
      () async {
    await store.upsertMessage(id: 'in1', senderId: spouseUserId, body: 'a',
        createdAt: DateTime(2026, 1, 1), status: 'delivered');
    await store.upsertMessage(id: 'in2', senderId: spouseUserId, body: 'b',
        createdAt: DateTime(2026, 1, 2), status: 'delivered');
    // Own sent message — must NOT be marked read on the server.
    await store.upsertMessage(id: 'out1', senderId: selfUserId, body: 'c',
        createdAt: DateTime(2026, 1, 3), status: 'sent');

    await chat.markConversationRead();

    expect(await store.watchUnreadCount(selfUserId).first, 0);
    expect(repo.markReadCalls.toSet(), {'in1', 'in2'});

    // Idempotent: nothing left unread, so no further server calls.
    await chat.markConversationRead();
    expect(repo.markReadCalls.length, 2);
  });

  test('sendText marks the message failed when encryptFor throws (no recipient device)',
      () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    final svc = ChatService(
      session: _ThrowingSession(),
      repo: _FakeChatRepo(),
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
    );

    await svc.sendText('hi');

    final row = (await store.watchConversation().first).single;
    expect(row.body, 'hi', reason: 'the text must not be silently lost');
    expect(row.status, 'failed',
        reason: 'a message that could not be encrypted/sent is failed, not sent');
  });

  test('a re-delivered reaction envelope is deduped, not re-decrypted',
      () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    final session = _ReactionSession();
    final repo = _FakeChatRepo();
    final svc = ChatService(
      session: session,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
    );
    final env = {
      'id': 'env-r',
      'message_id': 'rmsg',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'cipher_type': 2,
      'ciphertext': 'aa',
      'created_at': DateTime.utc(2026).toIso8601String(),
    };

    await svc.handleInboxRow(env);
    await svc.handleInboxRow(env); // duplicate realtime delivery

    expect(session.decryptCalls, 1,
        reason: 'a processed reaction envelope must not be decrypted again '
            '(a spent ratchet would fail)');
    expect((await store.reactionsFor('m1')).length, 1);
  });
}

/// A stand-in SignalSessionService that records how many `decryptFrom` calls
/// are in flight at once, so a test can assert inbound handling is serialized.
class _SpySession implements SignalSessionService {
  int _active = 0;
  int maxConcurrent = 0;

  @override
  Future<Uint8List> decryptFrom({
    required String senderUserId,
    required int senderDeviceNum,
    required Uint8List ciphertext,
    required int cipherType,
  }) async {
    _active++;
    if (_active > maxConcurrent) maxConcurrent = _active;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _active--;
    return Uint8List.fromList(encodePayload(const TextPayload(body: 'hi')));
  }

  @override
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) =>
      throw UnimplementedError();
}

/// encryptFor always throws — simulates a recipient with no registered device.
class _ThrowingSession implements SignalSessionService {
  @override
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) async =>
      throw Exception('recipient has no registered device');

  @override
  Future<Uint8List> decryptFrom({
    required String senderUserId,
    required int senderDeviceNum,
    required Uint8List ciphertext,
    required int cipherType,
  }) =>
      throw UnimplementedError();
}

/// decryptFrom returns a reaction payload and counts calls, so a test can
/// assert a duplicate envelope isn't decrypted twice.
class _ReactionSession implements SignalSessionService {
  int decryptCalls = 0;

  @override
  Future<Uint8List> decryptFrom({
    required String senderUserId,
    required int senderDeviceNum,
    required Uint8List ciphertext,
    required int cipherType,
  }) async {
    decryptCalls++;
    return Uint8List.fromList(encodePayload(
        const ReactionPayload(targetMessageId: 'm1', emoji: '❤️', add: true)));
  }

  @override
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) =>
      throw UnimplementedError();
}
