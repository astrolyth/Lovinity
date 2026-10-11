import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/presentation/message_bubble.dart';
import 'package:lovinity/features/chat/presentation/photo_viewer_screen.dart';
import 'package:lovinity/features/chat/presentation/video_viewer_screen.dart';
import 'package:lovinity/core/storage/signal_db.dart';

// A minimal valid 1x1 PNG, so Image.memory has real bytes to decode (same
// fixture as test/features/chat/photo_viewer_screen_test.dart).
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

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
    String attachmentKind = 'photo',
  }) async {
    await store.upsertAttachmentMessage(
      id: id,
      senderId: 'spouse',
      attachmentKind: attachmentKind,
      mimeType: attachmentKind == 'video' ? 'video/mp4' : 'image/jpeg',
      sizeBytes: 10,
      storageKey: 'c/$id',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: _onePixelPng,
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

  testWidgets('a downloaded video attachment opens the video viewer, not the photo viewer, on tap',
      (tester) async {
    final row = await attachmentRow(
      id: 'm5',
      downloadStatus: 'downloaded',
      localMediaPath: '/tmp/does-not-need-to-exist-for-this-assertion.mp4',
      attachmentKind: 'video',
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
    await tester.pumpAndSettle();

    expect(find.byType(VideoViewerScreen), findsOneWidget);
    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(downloadCalls, 0);
  });
}
