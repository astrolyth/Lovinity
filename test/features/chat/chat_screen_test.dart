import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_session_service.dart';
import 'package:lovinity/core/storage/media_cache.dart';
import 'package:lovinity/features/chat/data/chat_repository.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/domain/chat_providers.dart';
import 'package:lovinity/features/chat/domain/chat_service.dart';
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

class _NoopBundles implements PreKeyBundleSource {
  @override
  Future<List<int>> deviceNumsFor(String userId) async => [];
  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async => null;
}

class _NoopMediaCache implements MediaCache {
  @override
  Future<String> write(String key, Uint8List bytes) async => 'noop/$key';
}

/// A ChatService whose crypto/network dependencies are never actually
/// exercised by these tests -- it exists only so chatServiceProvider
/// resolves non-null, making the composer's `ready` flag true.
ChatService _readyChatService(SignalDb db) {
  final session = SignalSessionService(
    db: db,
    vault: KeyVault(InMemorySecureStore()),
    bundles: _NoopBundles(),
    selfUserId: 'me',
    selfDeviceNum: 1,
  );
  return ChatService(
    session: session,
    repo: ChatRepository(SupabaseClient(
      'http://localhost:0',
      'fake-anon-key',
      // Widget tests fail if any timer is still pending when the tree is
      // disposed -- the real GoTrueClient's periodic auto-refresh timer
      // would trip that check, so it's disabled here (this SupabaseClient
      // is never used to actually talk to auth/network in these tests).
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    )),
    store: ChatStore(db),
    selfUserId: 'me',
    spouseUserId: 'spouse',
    selfDeviceNum: 1,
    coupleId: 'couple-1',
    cache: _NoopMediaCache(),
  );
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
        chatServiceProvider.overrideWith((ref) async => _readyChatService(db)),
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
        chatServiceProvider.overrideWith((ref) async => _readyChatService(db)),
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
