import 'dart:typed_data';

import 'package:drift/drift.dart';
import '../../../core/storage/signal_db.dart';

typedef ChatMessageRow = ChatMessage;

class ChatStore {
  ChatStore(this._db);
  final SignalDb _db;

  Future<void> upsertMessage({
    required String id,
    required String senderId,
    required String? body,
    required DateTime createdAt,
    required String status,
    String? replyToMessageId,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return _db.into(_db.chatMessages).insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            id: id,
            senderId: senderId,
            body: Value(body),
            replyToMessageId: Value(replyToMessageId),
            createdAt: createdAt,
            deliveredAt: Value(deliveredAt),
            readAt: Value(readAt),
            status: status,
          ),
        );
  }

  Future<void> upsertAttachmentMessage({
    required String id,
    required String senderId,
    required String attachmentKind, // 'photo' | 'video'
    required String mimeType,
    required int sizeBytes,
    int? width,
    int? height,
    int? durationMs,
    required String storageKey,
    required Uint8List encKey,
    required Uint8List nonce,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
    required DateTime createdAt,
    required String status,
    String? localMediaPath,
    String downloadStatus = 'none',
  }) {
    return _db.into(_db.chatMessages).insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            id: id,
            senderId: senderId,
            body: Value(caption),
            replyToMessageId: Value(replyToMessageId),
            createdAt: createdAt,
            status: status,
            attachmentKind: Value(attachmentKind),
            mimeType: Value(mimeType),
            sizeBytes: Value(sizeBytes),
            width: Value(width),
            height: Value(height),
            durationMs: Value(durationMs),
            storageKey: Value(storageKey),
            encKey: Value(encKey),
            nonce: Value(nonce),
            thumbnailBytes: Value(thumbnailBytes),
            localMediaPath: Value(localMediaPath),
            downloadStatus: Value(downloadStatus),
          ),
        );
  }

  Future<void> updateDownloadStatus({
    required String id,
    required String status,
    String? localMediaPath,
  }) {
    return (_db.update(_db.chatMessages)..where((t) => t.id.equals(id))).write(
      ChatMessagesCompanion(
        downloadStatus: Value(status),
        localMediaPath:
            localMediaPath != null ? Value(localMediaPath) : const Value.absent(),
      ),
    );
  }

  Future<void> setStatus(String id, String status) {
    return (_db.update(_db.chatMessages)..where((t) => t.id.equals(id)))
        .write(ChatMessagesCompanion(status: Value(status)));
  }

  /// Returns the number of rows changed. Writes nothing (and so wakes no
  /// watchers) when the row already has this status: the receipt stream
  /// re-sends every message on each change, so most calls are repeats.
  Future<int> applyReceipt({
    required String id,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    if (readAt == null && deliveredAt == null) return 0;
    final alreadyDone =
        readAt != null ? const ['read'] : const ['delivered', 'read'];
    final status = readAt != null ? 'read' : 'delivered';
    return (_db.update(_db.chatMessages)
          ..where((t) => t.id.equals(id) & t.status.isNotIn(alreadyDone)))
        .write(
      ChatMessagesCompanion(
        deliveredAt: deliveredAt != null ? Value(deliveredAt) : const Value.absent(),
        readAt: readAt != null ? Value(readAt) : const Value.absent(),
        status: Value(status),
      ),
    );
  }

  Future<bool> messageExists(String id) async {
    final row = await (_db.select(_db.chatMessages)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  Future<ChatMessageRow?> messageById(String id) {
    return (_db.select(_db.chatMessages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> applyReaction({
    required String messageId,
    required String reactorId,
    required String emoji,
    required bool add,
  }) async {
    if (add) {
      await _db.into(_db.chatReactions).insertOnConflictUpdate(
            ChatReactionsCompanion.insert(
              messageId: messageId,
              reactorId: reactorId,
              emoji: emoji,
              createdAt: DateTime.now(),
            ),
          );
    } else {
      await (_db.delete(_db.chatReactions)
            ..where((t) =>
                t.messageId.equals(messageId) &
                t.reactorId.equals(reactorId) &
                t.emoji.equals(emoji)))
          .go();
    }
  }

  Future<List<ChatReaction>> reactionsFor(String messageId) {
    return (_db.select(_db.chatReactions)
          ..where((t) => t.messageId.equals(messageId)))
        .get();
  }

  Stream<List<ChatMessageRow>> watchConversation() {
    return (_db.select(_db.chatMessages)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// Live count of incoming messages (from the spouse) not yet read.
  Stream<int> watchUnreadCount(String selfUserId) {
    final count = _db.chatMessages.id.count();
    final q = _db.selectOnly(_db.chatMessages)
      ..addColumns([count])
      ..where(_db.chatMessages.senderId.isNotValue(selfUserId) &
          _db.chatMessages.readAt.isNull());
    return q.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Ids of incoming (spouse-authored) messages not yet read — used to send
  /// per-message read receipts to the server.
  Future<List<String>> incomingUnreadIds(String selfUserId) async {
    final rows = await (_db.select(_db.chatMessages)
          ..where((t) =>
              t.senderId.isNotValue(selfUserId) & t.readAt.isNull()))
        .get();
    return [for (final r in rows) r.id];
  }

  /// Locally mark these messages read (clears them from the unread count).
  Future<void> markRead(List<String> ids) async {
    await (_db.update(_db.chatMessages)
          ..where((t) => t.id.isIn(ids) & t.readAt.isNull()))
        .write(ChatMessagesCompanion(readAt: Value(DateTime.now())));
  }
}
