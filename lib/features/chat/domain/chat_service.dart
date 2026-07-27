// lib/features/chat/domain/chat_service.dart
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../../core/crypto/signal_session_service.dart';
import '../data/chat_repository.dart';
import '../data/chat_store.dart';
import 'chat_payload.dart';

class ChatService {
  ChatService({
    required this.session,
    required this.repo,
    required this.store,
    required this.selfUserId,
    required this.spouseUserId,
    required this.selfDeviceNum,
  });

  final SignalSessionService session;
  final ChatRepository repo;
  final ChatStore store;
  final String selfUserId;
  final String spouseUserId;
  final int selfDeviceNum;

  /// Bounded retry for envelopes that fail to decrypt (e.g. corrupt
  /// ciphertext, or a session we can never rebuild). Counted in-memory only:
  /// a dead-letter delete persists, so a corrupt envelope survives at most
  /// one session's worth of retries.
  static const int maxDecryptAttempts = 8;
  final Map<String, int> _decryptAttempts = {};

  /// Envelope ids already successfully processed this session. The text-message
  /// `messageExists` dedup doesn't cover reactions (they create no
  /// chat_messages row), so without this a re-delivered reaction envelope would
  /// re-decrypt a spent ratchet and fail. Applies to every envelope type.
  final Set<String> _processedEnvelopes = {};

  Future<void> sendText(String body, {String? replyToMessageId}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    // The whole body — including the optimistic write — is covered here so
    // sendText never throws. It's invoked via unawaited(...) from _send, so
    // an escaping exception would become an unhandled async error.
    try {
      // Optimistic row shown immediately, before the network round-trip.
      await store.upsertMessage(
        id: id,
        senderId: selfUserId,
        body: body,
        replyToMessageId: replyToMessageId,
        createdAt: now,
        status: 'sending',
      );
      final payload = TextPayload(body: body, replyToMessageId: replyToMessageId);
      final copies = await session.encryptFor(
        recipientUserId: spouseUserId,
        plaintext: encodePayload(payload),
      );
      // The client-generated id is passed through as p_message_id so the
      // server message shares this same id — required for receipts to land
      // on this row instead of a different server-generated one.
      await repo.sendEnvelopes(
          senderDeviceNum: selfDeviceNum, copies: copies, messageId: id);
      await store.setStatus(id, 'sent');
    } catch (_) {
      try {
        await store.setStatus(id, 'failed');
      } catch (_) {
        // The optimistic write itself may have failed, so there's no row to
        // mark 'failed' against. Nothing more we can do here.
      }
    }
  }

  Future<void> sendReaction({
    required String targetMessageId,
    required String emoji,
    required bool add,
  }) async {
    try {
      final payload = ReactionPayload(
          targetMessageId: targetMessageId, emoji: emoji, add: add);
      final copies = await session.encryptFor(
        recipientUserId: spouseUserId,
        plaintext: encodePayload(payload),
      );
      await repo.sendEnvelopes(senderDeviceNum: selfDeviceNum, copies: copies);
      // Reflect our own reaction locally only once it's actually been sent.
      await store.applyReaction(
          messageId: targetMessageId,
          reactorId: selfUserId,
          emoji: emoji,
          add: add);
    } catch (_) {
      // Reaction couldn't be sent (e.g. spouse not yet registered, offline).
      // A reaction is best-effort; don't crash the caller or leave an
      // unhandled async error.
    }
  }

  /// Mark every unread incoming message read: locally (clears the unread badge)
  /// and on the server (so the spouse's sent messages flip to "read"). Server
  /// calls are best-effort — a failure doesn't block the local badge clearing.
  Future<void> markConversationRead() async {
    final ids = await store.incomingUnreadIds(selfUserId);
    if (ids.isEmpty) return;
    await store.markIncomingRead(selfUserId);
    for (final id in ids) {
      try {
        await repo.markRead(id);
      } catch (_) {
        // best-effort; retried next time the chat is opened
      }
    }
  }

  Future<void> _inboxLock = Future<void>.value();

  /// Decrypt one inbound envelope, apply it, acknowledge, and delete it.
  /// Never throws for a bad envelope — logs via return.
  ///
  /// Serialized: Supabase realtime delivers overlapping row batches, and Dart
  /// does not await an async stream listener before delivering the next event,
  /// so two calls could otherwise run concurrently. `decryptFrom` mutates
  /// Double Ratchet state, which is not concurrency-safe, so inbound handling
  /// must run one at a time.
  Future<void> handleInboxRow(Map<String, dynamic> env) {
    final result = _inboxLock.then((_) => _handleInboxRow(env));
    _inboxLock = result.catchError((_) {});
    return result;
  }

  Future<void> _handleInboxRow(Map<String, dynamic> env) async {
    // Only handle envelopes addressed to THIS device. A user's other devices
    // share the same recipient_id and appear in this stream, but their
    // envelopes are theirs to fetch — we must not read or delete them.
    final recipientDeviceNum = (env['recipient_device_num'] as num?)?.toInt();
    if (recipientDeviceNum != selfDeviceNum) return;

    final envId = env['id'] as String?;
    // Dedup EVERY envelope type (text, reaction, …): re-decrypting a spent
    // ratchet fails, and reactions have no chat_messages row to gate on.
    if (envId != null && _processedEnvelopes.contains(envId)) {
      await repo.deleteEnvelope(envId);
      return;
    }

    final messageId = env['message_id'] as String;
    if (await store.messageExists(messageId) && envId != null) {
      // Already processed this logical message; just clean up the envelope.
      _processedEnvelopes.add(envId);
      await repo.deleteEnvelope(envId);
      return;
    }
    // Sender address comes from the envelope itself (denormalized): it may be
    // the spouse OR the recipient's own other device (multi-device sync).
    final String senderId = env['sender_id'] as String;
    final int senderDeviceNum = (env['sender_device_num'] as num).toInt();
    final Uint8List ciphertext = _bytes(env['ciphertext']);
    late final ChatPayload payload;
    try {
      final plain = await session.decryptFrom(
        senderUserId: senderId,
        senderDeviceNum: senderDeviceNum,
        ciphertext: ciphertext,
        cipherType: (env['cipher_type'] as num).toInt(),
      );
      payload = decodePayload(Uint8List.fromList(plain));
      _decryptAttempts.remove(env['id']);
    } catch (_) {
      final id = env['id'] as String?;
      if (id == null) return;
      final n = (_decryptAttempts[id] ?? 0) + 1;
      _decryptAttempts[id] = n;
      if (n >= maxDecryptAttempts) {
        // Unrecoverable (corrupt, or a session we can never rebuild). Dead-letter
        // it so the inbox stream stops re-delivering it every tick.
        _decryptAttempts.remove(id);
        await repo.deleteEnvelope(id);
      }
      return; // otherwise leave it for the next tick
    }

    switch (payload) {
      case TextPayload():
        await store.upsertMessage(
          id: messageId,
          senderId: senderId,
          body: payload.body,
          replyToMessageId: payload.replyToMessageId,
          createdAt: DateTime.parse(env['created_at'] as String),
          // Own-device sync copies are already-sent; spouse copies are delivered.
          status: senderId == selfUserId ? 'sent' : 'delivered',
        );
        if (senderId != selfUserId) await repo.markDelivered(messageId);
      case ReactionPayload():
        await store.applyReaction(
          messageId: payload.targetMessageId,
          reactorId: senderId,
          emoji: payload.emoji,
          add: payload.add,
        );
      case UnsupportedPayload():
        break; // skip, still delete the envelope below
    }
    if (envId != null) _processedEnvelopes.add(envId);
    await repo.deleteEnvelope(env['id'] as String);
  }
}

Uint8List _bytes(dynamic v) {
  if (v is String) {
    final hex = v.startsWith('\\x') ? v.substring(2) : v;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ]);
  }
  return Uint8List.fromList((v as List).cast<int>());
}
