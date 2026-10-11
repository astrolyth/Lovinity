import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';

void main() {
  late SignalDb db;
  late ChatStore store;
  setUp(() { db = SignalDb.memory(); store = ChatStore(db); });
  tearDown(() => db.close());

  test('upsert is idempotent by message id', () async {
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'delivered');
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'delivered');
    final rows = await store.watchConversation().first;
    expect(rows.length, 1);
  });

  test('applyReaction add then remove', () async {
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'sent');
    await store.applyReaction(messageId: 'm1', reactorId: 'b', emoji: '❤️', add: true);
    expect((await store.reactionsFor('m1')).length, 1);
    await store.applyReaction(messageId: 'm1', reactorId: 'b', emoji: '❤️', add: false);
    expect((await store.reactionsFor('m1')).length, 0);
  });

  test('watchConversation orders by createdAt', () async {
    await store.upsertMessage(id: 'm2', senderId: 'a', body: '2',
        createdAt: DateTime(2026, 1, 2), status: 'sent');
    await store.upsertMessage(id: 'm1', senderId: 'a', body: '1',
        createdAt: DateTime(2026, 1, 1), status: 'sent');
    final rows = await store.watchConversation().first;
    expect(rows.map((r) => r.id), ['m1', 'm2']);
  });

  test('applyReceipt updates delivered/read + derives status; only on an existing row', () async {
    await store.upsertMessage(id: 'm1', senderId: 'me', body: 'hi',
        createdAt: DateTime(2026), status: 'sent');
    await store.applyReceipt(id: 'm1', deliveredAt: DateTime(2026, 1, 2));
    var row = (await store.watchConversation().first).single;
    expect(row.status, 'delivered');
    expect(row.deliveredAt, isNotNull);
    await store.applyReceipt(id: 'm1', readAt: DateTime(2026, 1, 3));
    row = (await store.watchConversation().first).single;
    expect(row.status, 'read');
    expect(row.readAt, isNotNull);
    // No-op on an unknown id (does not insert).
    await store.applyReceipt(id: 'ghost', deliveredAt: DateTime(2026));
    expect(await store.messageExists('ghost'), isFalse);
  });

  test('watchUnreadCount counts only incoming unread; markIncomingRead clears',
      () async {
    const me = 'me';
    // Incoming (from spouse), unread.
    await store.upsertMessage(id: 'in1', senderId: 'spouse', body: 'a',
        createdAt: DateTime(2026, 1, 1), status: 'delivered');
    await store.upsertMessage(id: 'in2', senderId: 'spouse', body: 'b',
        createdAt: DateTime(2026, 1, 2), status: 'delivered');
    // Own sent message — must NOT count.
    await store.upsertMessage(id: 'out1', senderId: me, body: 'c',
        createdAt: DateTime(2026, 1, 3), status: 'sent');
    // Incoming but already read — must NOT count.
    await store.upsertMessage(id: 'in3', senderId: 'spouse', body: 'd',
        createdAt: DateTime(2026, 1, 4), status: 'read',
        readAt: DateTime(2026, 1, 4));

    expect(await store.watchUnreadCount(me).first, 2);
    expect((await store.incomingUnreadIds(me)).toSet(), {'in1', 'in2'});

    await store.markIncomingRead(me);
    expect(await store.watchUnreadCount(me).first, 0);
    expect(await store.incomingUnreadIds(me), isEmpty);
  });

  test('upsertAttachmentMessage stores every attachment field, retrievable via messageById',
      () async {
    await store.upsertAttachmentMessage(
      id: 'a1',
      senderId: 'me',
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: 1234,
      width: 800,
      height: 600,
      storageKey: 'couple-1/a1',
      encKey: Uint8List.fromList(List.filled(32, 7)),
      nonce: Uint8List.fromList(List.filled(12, 3)),
      thumbnailBytes: Uint8List.fromList([1, 2, 3]),
      caption: 'nice view',
      createdAt: DateTime(2026),
      status: 'sent',
    );

    final row = await store.messageById('a1');
    expect(row, isNotNull);
    expect(row!.attachmentKind, 'photo');
    expect(row.mimeType, 'image/jpeg');
    expect(row.sizeBytes, 1234);
    expect(row.width, 800);
    expect(row.height, 600);
    expect(row.durationMs, isNull);
    expect(row.storageKey, 'couple-1/a1');
    expect(row.encKey, Uint8List.fromList(List.filled(32, 7)));
    expect(row.nonce, Uint8List.fromList(List.filled(12, 3)));
    expect(row.thumbnailBytes, [1, 2, 3]);
    expect(row.body, 'nice view');
    expect(row.downloadStatus, 'none');
  });

  test('messageById returns null for an unknown id', () async {
    expect(await store.messageById('nope'), isNull);
  });

  test('updateDownloadStatus sets status and localMediaPath', () async {
    await store.upsertAttachmentMessage(
      id: 'a2',
      senderId: 'me',
      attachmentKind: 'video',
      mimeType: 'video/mp4',
      sizeBytes: 999,
      durationMs: 5000,
      storageKey: 'couple-1/a2',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: Uint8List.fromList([9]),
      createdAt: DateTime(2026),
      status: 'delivered',
    );

    await store.updateDownloadStatus(
        id: 'a2', status: 'downloaded', localMediaPath: '/tmp/a2.mp4');

    final row = await store.messageById('a2');
    expect(row!.downloadStatus, 'downloaded');
    expect(row.localMediaPath, '/tmp/a2.mp4');
  });

  test('a plain text message (no attachment fields) has null attachmentKind/downloadStatus',
      () async {
    await store.upsertMessage(id: 't1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'sent');
    final row = await store.messageById('t1');
    expect(row!.attachmentKind, isNull);
    expect(row.downloadStatus, isNull);
  });
}
