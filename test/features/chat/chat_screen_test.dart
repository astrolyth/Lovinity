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

  @override
  Future<void> clear() async {}
}

/// A ChatService whose crypto/network dependencies are never actually
/// exercised by these tests -- it exists only so chatServiceProvider
/// resolves non-null, making the composer's `ready` flag true.
/// Records the args the composer passes to sendPhoto/sendVideo instead of
/// running the real send. ChatService is concrete (no interface), so this
/// subclasses it and overrides only the two entry points under test -- the
/// same "extend the real class" convention `_FakeChatRepo` uses in
/// test/features/chat/chat_service_test.dart.
class _RecordingChatService extends ChatService {
  _RecordingChatService({
    required super.session,
    required super.repo,
    required super.store,
    required super.selfUserId,
    required super.spouseUserId,
    required super.selfDeviceNum,
    required super.coupleId,
    required super.cache,
  });

  final List<({String? caption, String? replyToMessageId})> sendPhotoCalls = [];
  final List<({String? caption, String? replyToMessageId})> sendVideoCalls = [];

  @override
  Future<void> sendPhoto({
    required Uint8List bytes,
    required String mimeType,
    required int width,
    required int height,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
  }) async {
    sendPhotoCalls.add((caption: caption, replyToMessageId: replyToMessageId));
  }

  @override
  Future<void> sendVideo({
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
  }) async {
    sendVideoCalls.add((caption: caption, replyToMessageId: replyToMessageId));
  }
}

_RecordingChatService _recordingChatService(SignalDb db) {
  return _RecordingChatService(
    session: SignalSessionService(
      db: db,
      vault: KeyVault(InMemorySecureStore()),
      bundles: _NoopBundles(),
      selfUserId: 'me',
      selfDeviceNum: 1,
    ),
    repo: ChatRepository(SupabaseClient(
      'http://localhost:0',
      'fake-anon-key',
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

  testWidgets(
      'attaching a photo sends the typed text as the caption and clears the composer',
      (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    final picker = _FakeMediaPicker()
      ..nextPhoto = PickedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        width: 10,
        height: 10,
        thumbnailBytes: Uint8List.fromList([9]),
      );
    final service = _recordingChatService(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider
            .overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(picker),
        chatServiceProvider.overrideWith((ref) async => service),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '  look at this  ');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(service.sendPhotoCalls, hasLength(1));
    expect(service.sendPhotoCalls.single.caption, 'look at this',
        reason: 'the composer text must travel with the attachment as its '
            'caption, trimmed, instead of being silently dropped');
    expect(service.sendPhotoCalls.single.replyToMessageId, isNull);
    expect(
      (tester.widget<TextField>(find.byType(TextField)).controller)!.text,
      isEmpty,
      reason: 'the caption was consumed by the send; it must not be left '
          'behind to reattach to the next message',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('attaching a photo carries a pending reply and clears the banner',
      (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    await store.upsertMessage(id: 'm1', senderId: 'spouse', body: 'salam',
        createdAt: DateTime(2026), status: 'delivered');
    final picker = _FakeMediaPicker()
      ..nextPhoto = PickedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        width: 10,
        height: 10,
        thumbnailBytes: Uint8List.fromList([9]),
      );
    final service = _recordingChatService(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider
            .overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(picker),
        chatServiceProvider.overrideWith((ref) async => service),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    // Arm a pending reply through the real affordance (long-press -> Reply).
    await tester.longPress(find.text('salam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Replying to'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(service.sendPhotoCalls, hasLength(1));
    expect(service.sendPhotoCalls.single.replyToMessageId, 'm1',
        reason: 'picking media while a reply is pending must not silently '
            'drop the reply');
    expect(service.sendPhotoCalls.single.caption, isNull,
        reason: 'an empty composer means no caption, not an empty string');
    expect(find.text('Replying to'), findsNothing,
        reason: 'the reply was consumed; the banner must not linger');

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
