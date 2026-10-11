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

/// Singleton [NotificationStore] over the same local DB chat uses, so it's
/// covered by the same account-switch wipe (`SignalDb.wipeAll()`).
final notificationStoreProvider = Provider<NotificationStore>((ref) {
  return NotificationStore(ref.watch(signalDbProvider));
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
