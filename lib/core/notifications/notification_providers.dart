// lib/core/notifications/notification_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_service.dart';

/// Singleton [PushService] for the app. Constructing it does nothing
/// Firebase-related by itself (`init()` -- called by Task 4's boot/lifecycle
/// wiring -- is what actually touches Firebase, and is fully guarded).
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});
