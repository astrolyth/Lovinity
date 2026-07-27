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

  Future<void> setStatus(String id, String status) {
    return (_db.update(_db.chatMessages)..where((t) => t.id.equals(id)))
        .write(ChatMessagesCompanion(status: Value(status)));
  }

  Future<void> applyReceipt({
    required String id,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    final status = readAt != null
        ? 'read'
        : (deliveredAt != null ? 'delivered' : null);
    await (_db.update(_db.chatMessages)..where((t) => t.id.equals(id))).write(
      ChatMessagesCompanion(
        deliveredAt: deliveredAt != null ? Value(deliveredAt) : const Value.absent(),
        readAt: readAt != null ? Value(readAt) : const Value.absent(),
        status: status != null ? Value(status) : const Value.absent(),
      ),
    );
  }

  Future<bool> messageExists(String id) async {
    final row = await (_db.select(_db.chatMessages)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null;
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

  /// Locally mark every unread incoming message read (clears the unread count).
  Future<void> markIncomingRead(String selfUserId) async {
    await (_db.update(_db.chatMessages)
          ..where((t) =>
              t.senderId.isNotValue(selfUserId) & t.readAt.isNull()))
        .write(ChatMessagesCompanion(readAt: Value(DateTime.now())));
  }
}
