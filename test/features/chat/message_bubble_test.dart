import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/presentation/message_bubble.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late ChatStore store;

  setUp(() {
    db = SignalDb.memory();
    store = ChatStore(db);
  });
  tearDown(() => db.close());

  Future<ChatMessageRow> attachmentRow({
    required String id,
    required String downloadStatus,
    String? localMediaPath,
  }) async {
    await store.upsertAttachmentMessage(
      id: id,
      senderId: 'spouse',
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: 10,
      storageKey: 'c/$id',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: Uint8List.fromList(List.filled(3, 9)),
      createdAt: DateTime(2026),
      status: 'delivered',
      downloadStatus: downloadStatus,
      localMediaPath: localMediaPath,
    );
    return (await store.messageById(id))!;
  }

  testWidgets('a not-yet-downloaded attachment shows the thumbnail and taps trigger onDownloadAttachment',
      (tester) async {
    final row = await attachmentRow(id: 'm1', downloadStatus: 'none');
    String? downloaded;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (id) => downloaded = id,
        ),
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();

    expect(downloaded, 'm1');
  });

  testWidgets('a downloading attachment shows a progress indicator and is not tappable to download again',
      (tester) async {
    final row = await attachmentRow(id: 'm2', downloadStatus: 'downloading');
    var downloadCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (_) => downloadCalls++,
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(downloadCalls, 0);
  });

  testWidgets('a failed attachment shows an error icon and tapping retries the download',
      (tester) async {
    final row = await attachmentRow(id: 'm3', downloadStatus: 'failed');
    String? downloaded;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (id) => downloaded = id,
        ),
      ),
    ));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(downloaded, 'm3');
  });

  testWidgets('a downloaded attachment opens a viewer on tap instead of calling onDownloadAttachment',
      (tester) async {
    final row = await attachmentRow(
      id: 'm4',
      downloadStatus: 'downloaded',
      localMediaPath: '/tmp/does-not-need-to-exist-for-this-assertion.jpg',
    );
    var downloadCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (_) => downloadCalls++,
        ),
      ),
    ));

    await tester.tap(find.byType(Image).first);
    await tester.pump();

    expect(downloadCalls, 0, reason: 'a downloaded attachment must not re-trigger a download');
  });
}
