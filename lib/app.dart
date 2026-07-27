import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_providers.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme.dart';

/// Handles a push notification the OS delivers while the app is backgrounded
/// or terminated. Content-free by design (see push_service.dart) -- the OS
/// already displays the notification from the FCM payload's `notification`
/// block built server-side, so there is nothing to decrypt or process here.
///
/// Must be a top-level (not class member) function annotated
/// `@pragma('vm:entry-point')` so the Dart VM can find it when relaunching
/// this isolate in the background -- a requirement of the firebase_messaging
/// plugin. Registered (guarded, best-effort) from [_LovinityAppState.initState]
/// only after [PushService.init] confirms Firebase actually initialized --
/// calling `FirebaseMessaging.onBackgroundMessage` before a Firebase app
/// exists throws, which would otherwise crash boot on the (default, expected)
/// no-native-config setup.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Maps a notification tap's content-free routing hint (`NotificationTap.type`)
/// to the app route to deep-link to, or `null` if the type isn't one this app
/// version knows how to route (nothing to navigate to -- never a crash).
/// Pure + exported so it's unit-testable without a widget tree or router.
String? routeForTap(NotificationTap tap) {
  const chatTypes = {'chat', 'message', 'reaction'};
  if (chatTypes.contains(tap.type)) return '/home/chat';
  if (tap.type == 'pairing') return '/home';
  return null;
}

class LovinityApp extends ConsumerStatefulWidget {
  const LovinityApp({super.key});

  @override
  ConsumerState<LovinityApp> createState() => _LovinityAppState();
}

class _LovinityAppState extends ConsumerState<LovinityApp> {
  StreamSubscription<NotificationTap>? _tapSub;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: push setup must never delay first frame, and any
    // failure here (including no native Firebase config at all -- the
    // default state for this repo) must never crash boot.
    unawaited(_initPush());
  }

  Future<void> _initPush() async {
    try {
      final pushService = ref.read(pushServiceProvider);
      final available = await pushService.init();
      if (!available) return;

      try {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      } catch (e, st) {
        developer.log(
          'Failed to register background message handler',
          name: 'LovinityApp',
          error: e,
          stackTrace: st,
        );
      }

      _tapSub = pushService.taps.listen(_handleTap);
    } catch (e, st) {
      developer.log(
        'PushService.init failed',
        name: 'LovinityApp',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _handleTap(NotificationTap tap) {
    try {
      final target = routeForTap(tap);
      if (target != null) ref.read(appRouterProvider).go(target);
    } catch (e, st) {
      developer.log(
        'Failed to handle notification tap',
        name: 'LovinityApp',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_tapSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Lovinity',
      theme: LovTheme.light(),
      darkTheme: LovTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
