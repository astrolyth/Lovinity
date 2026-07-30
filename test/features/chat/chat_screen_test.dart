import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/domain/chat_providers.dart';
import 'package:lovinity/features/chat/presentation/chat_screen.dart';
import 'package:lovinity/features/chat/presentation/media_picker.dart';
import 'package:lovinity/core/storage/signal_db.dart';

class _FakeMediaPicker implements MediaPicker {
  PickedPhoto? nextPhoto;

  @override
  Future<PickedPhoto?> pickPhoto(MediaSource source) async => nextPhoto;

  @override
  Future<PickedVideo?> pickVideo(MediaSource source) async => null;
}

void main() {
  testWidgets('renders messages from the store', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'salam alaykum',
        createdAt: DateTime(2026), status: 'delivered');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();
    expect(find.text('salam alaykum'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // composer

    // Unmount explicitly (inside the fake-async zone) and elapse past drift's
    // zero-duration stream-close timer, so the framework's automatic
    // post-test unmount doesn't trip over a still-pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tapping the attach button shows Camera/Photo Library/Video options',
      (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(_FakeMediaPicker()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tapping the emoji button shows the emoji picker panel', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(_FakeMediaPicker()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    expect(find.byType(EmojiPicker), findsNothing);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();
    expect(find.byType(EmojiPicker), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
