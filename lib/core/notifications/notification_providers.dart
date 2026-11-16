// lib/core/notifications/notification_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../crypto/crypto_providers.dart';
import 'notification_store.dart';
import 'push_service.dart';

/// Singleton [PushService] for the app. Constructing it does nothing
/// Firebase-related by itself (`init()` is what actually touches Firebase,
/// and is fully guarded).
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});

/// [NotificationStore] over the signed-in account's own local DB (the same one
/// chat uses), so each account sees only its own notification history.
/// Every reader already checks for a signed-in user first.
final notificationStoreProvider = Provider<NotificationStore>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (selfId == null) {
    throw StateError('notificationStoreProvider read while signed out');
  }
  return NotificationStore(ref.watch(signalDbProvider(selfId)));
});

/// Live count of unread in-app notifications, for the home bell badge.
/// Emits 0 when signed out.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return Stream.value(0);
  return ref.watch(notificationStoreProvider).watchUnreadCount();
});

/// Full notification history, newest first, for the notifications screen.
final notificationsListProvider =
    StreamProvider<List<NotificationRow>>((ref) {
  return ref.watch(notificationStoreProvider).watchAll();
});
