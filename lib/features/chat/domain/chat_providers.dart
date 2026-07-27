// lib/features/chat/domain/chat_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/chat_repository.dart';
import '../data/chat_store.dart';
import '../data/typing_channel.dart';
import 'chat_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.read(supabaseClientProvider));
});

final chatStoreProvider = Provider<ChatStore>((ref) {
  return ChatStore(ref.watch(signalDbProvider));
});

/// Null until signed in + paired + this device is registered.
///
/// `signalSessionServiceProvider` is itself a `FutureProvider<
/// SignalSessionService?>` (null when signed out or unregistered) — awaiting
/// it here folds that same "not ready" state into `chatServiceProvider`
/// instead of duplicating the registration check.
final chatServiceProvider = FutureProvider<ChatService?>((ref) async {
  final session = await ref.watch(signalSessionServiceProvider.future);
  if (session == null) return null;

  final authSession = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (authSession == null || couple == null) return null;
  final selfId = authSession.user.id;

  final deviceNum = await ref.read(keyVaultProvider).readDeviceNum();
  if (deviceNum == null) return null; // not registered yet

  return ChatService(
    session: session,
    repo: ref.read(chatRepositoryProvider),
    store: ref.read(chatStoreProvider),
    selfUserId: selfId,
    spouseUserId: couple.spouseOf(selfId),
    selfDeviceNum: deviceNum,
  );
});

final conversationMessagesProvider =
    StreamProvider<List<ChatMessageRow>>((ref) {
  return ref.watch(chatStoreProvider).watchConversation();
});

/// Live count of unread incoming messages, for the home chat badge. Emits 0
/// when signed out.
final unreadChatCountProvider = StreamProvider<int>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return Stream.value(0);
  return ref.watch(chatStoreProvider).watchUnreadCount(authSession.user.id);
});

/// Subscribes to the inbox stream and feeds each row through
/// [ChatService.handleInboxRow]. No-op until `chatServiceProvider` resolves
/// to a real service; cancels its subscription on dispose.
final inboxPumpProvider = Provider<void>((ref) {
  final svc = ref.watch(chatServiceProvider).asData?.value;
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (svc == null || authSession == null) return;
  final sub = ref
      .read(chatRepositoryProvider)
      .watchInbox(authSession.user.id)
      .listen((rows) async {
    for (final r in rows) {
      await svc.handleInboxRow(r);
    }
  });
  ref.onDispose(sub.cancel);
});

/// Streams the couple's `messages` rows and reflects the sender-side
/// delivered/read receipts onto the local chat rows the sender authored.
final receiptPumpProvider = Provider<void>((ref) {
  final svc = ref.watch(chatServiceProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (svc == null || couple == null) return;
  final store = ref.read(chatStoreProvider);
  final selfId = svc.selfUserId;
  final sub =
      ref.read(chatRepositoryProvider).watchMyMessages(couple.id).listen((rows) async {
    for (final r in rows) {
      if (r['sender_id'] != selfId) continue; // only our own sent messages
      await store.applyReceipt(
        id: r['id'] as String,
        deliveredAt: r['delivered_at'] == null
            ? null
            : DateTime.parse(r['delivered_at'] as String),
        readAt: r['read_at'] == null
            ? null
            : DateTime.parse(r['read_at'] as String),
      );
    }
  });
  ref.onDispose(sub.cancel);
});

/// Ephemeral typing-presence channel for the current conversation. Not
/// stored, not encrypted — only created once chat is actually ready
/// (signed in, paired, device registered) so no realtime connection is
/// attempted before then.
final typingChannelProvider = Provider<TypingChannel?>((ref) {
  final chatService = ref.watch(chatServiceProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (chatService == null || couple == null) return null;

  final channel = TypingChannel(
    supabase: ref.read(supabaseClientProvider),
    conversationId: couple.id,
  );
  ref.onDispose(channel.dispose);
  return channel;
});

/// Whether the spouse is currently typing. False whenever the typing
/// channel isn't ready yet.
final spouseTypingProvider = StreamProvider<bool>((ref) {
  final channel = ref.watch(typingChannelProvider);
  if (channel == null) return Stream.value(false);
  return channel.spouseTyping;
});
