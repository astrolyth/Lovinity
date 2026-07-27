// lib/core/notifications/push_service.dart
//
// Content-free push notifications (FCM) with graceful degradation: this app
// must build/analyze/test with NO Firebase config present (no
// google-services.json / GoogleService-Info.plist / firebase_options.dart).
// `init()` guards `Firebase.initializeApp()` in try/catch; on ANY failure
// (which is exactly what happens with no native config) the service marks
// itself unavailable and every other method becomes a safe no-op. Nothing
// here ever puts message plaintext into a push payload or notification --
// display uses only what already arrived in the (content-free) FCM payload
// built server-side (see supabase/migrations/20260726000001_push_notifications.sql).
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The routing hint carried by a tapped notification's content-free payload
/// (`data.type`, sent by the push-dispatch edge function). The only values
/// the backend currently sends are `'chat'` and `'pairing'`; PushService
/// doesn't validate against that set so a future type doesn't need a client
/// change to arrive safely (the app-level tap handler in Task 4 decides what
/// to do with unrecognized values).
@immutable
class NotificationTap {
  const NotificationTap({required this.type});

  final String type;

  @override
  bool operator ==(Object other) =>
      other is NotificationTap && other.type == type;

  @override
  int get hashCode => type.hashCode;

  @override
  String toString() => 'NotificationTap(type: $type)';
}

/// Thin seam over the handful of `FirebaseMessaging` entry points
/// [PushService] needs. Exists so unit tests can substitute a fake instead of
/// driving real plugin method channels -- calling any real
/// `FirebaseMessaging` method without a running Firebase app throws, and
/// even with one it needs platform channel bindings a bare `flutter_test`
/// run doesn't have.
abstract class PushMessaging {
  Future<NotificationSettings> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  Stream<String> get onTokenRefresh;
}

class _FirebaseMessagingAdapter implements PushMessaging {
  @override
  Future<NotificationSettings> requestPermission() =>
      FirebaseMessaging.instance.requestPermission();

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;
}

/// Thin seam over the two push-token RPCs from the Task 1 migration
/// (`register_push_token` / `unregister_push_token`). This exists as its own
/// interface -- not just inline `client.rpc(...)` calls -- because
/// `SupabaseClient.rpc()` returns the concrete `PostgrestFilterBuilder<T>`
/// (which implements `Future<T>` rather than just being one), so mocktail's
/// `thenAnswer` can't satisfy its static type and a `Mock`-based
/// `SupabaseClient` can't stub `.rpc()` directly -- the same limitation
/// already documented in `test/features/chat/chat_repository_test.dart` and
/// `test/features/scoring/scoreboard_repository_test.dart` for `.from()`.
/// Mocking this small interface instead keeps `PushService`'s own token
/// lifecycle logic (get token -> call RPC -> handle refresh) unit-testable
/// without a real Supabase client.
abstract class PushTokenApi {
  Future<void> register(String token, String platform);
  Future<void> unregister(String token);
}

class SupabasePushTokenApi implements PushTokenApi {
  SupabasePushTokenApi(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register(String token, String platform) => _client.rpc(
    'register_push_token',
    params: {'p_token': token, 'p_platform': platform},
  );

  @override
  Future<void> unregister(String token) =>
      _client.rpc('unregister_push_token', params: {'p_token': token});
}

/// Parses the routing hint out of a content-free push payload's `data` map.
/// Pure function so tap parsing can be unit-tested with a plain `Map`,
/// without constructing a real `RemoteMessage`.
NotificationTap? tapFromData(Map<String, dynamic>? data) {
  final type = data?['type'];
  if (type is String && type.isNotEmpty) return NotificationTap(type: type);
  return null;
}

/// Coordinates FCM + local notification display for chat/pairing pushes.
///
/// Graceful degradation is the load-bearing property here: [init] guards
/// `Firebase.initializeApp()` in try/catch. On any failure (no native config
/// present -- the expected state for this repo without Task 5's setup, and
/// for every CI/analyze/test run) the service logs once, marks itself
/// unavailable, and every other method becomes a safe no-op. Nothing throws
/// and nothing blocks app boot.
class PushService {
  PushService({
    PushMessaging? messaging,
    FlutterLocalNotificationsPlugin? notifications,
    @visibleForTesting PushTokenApi? pushTokenApi,
  }) : _messaging = messaging ?? _FirebaseMessagingAdapter(),
       _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _pushTokenApi = pushTokenApi;

  /// Test-only escape hatch: skips `Firebase.initializeApp()` entirely and
  /// marks the service available immediately, wired to an injected
  /// [PushMessaging] fake (and optionally a [PushTokenApi] fake) -- lets
  /// [registerToken]/[unregisterToken] be exercised without any real
  /// Firebase plugin channel.
  @visibleForTesting
  factory PushService.availableForTesting({
    required PushMessaging messaging,
    PushTokenApi? pushTokenApi,
  }) {
    final service = PushService(
      messaging: messaging,
      pushTokenApi: pushTokenApi,
    );
    service._available = true;
    return service;
  }

  static const _channelId = 'chat';
  static const _channelName = 'Chat';
  static const _channelDescription = 'Chat message notifications';

  final PushMessaging _messaging;
  final FlutterLocalNotificationsPlugin _notifications;
  final PushTokenApi? _pushTokenApi;

  bool _available = false;
  bool _loggedInitFailure = false;

  /// Monotonic id for locally-shown notifications. All chat pushes carry
  /// identical title/body, so `notification.hashCode` (the previous id
  /// source) would collapse distinct notifications into one the moment
  /// `RemoteNotification` gained value-equality; a simple incrementing
  /// counter can't collide.
  int _localNotifId = 0;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  final _tapController = StreamController<NotificationTap>.broadcast();

  /// The tap that launched the app from a terminated state (cold start via
  /// `getInitialMessage()`), captured during [init] and consumed once via
  /// [takeInitialTap]. See that getter's doc for why this can't just be
  /// pushed onto [_tapController] like the other tap sources.
  NotificationTap? _pendingInitialTap;

  /// True once [init] has completed successfully. Everything else is a
  /// no-op while this is false.
  bool get isAvailable => _available;

  /// Notification taps (foreground-shown local notification tapped, or the
  /// system tray notification opened/relaunched the app), carrying the
  /// content-free `data.type` routing hint. The app shell (Task 4) listens
  /// here to deep-link.
  ///
  /// Deliberately does NOT also carry the cold-start ("initial message")
  /// tap -- see [takeInitialTap].
  Stream<NotificationTap> get taps => _tapController.stream;

  /// Returns (and clears) the tap that launched the app from a terminated
  /// state, or `null` if there wasn't one (or it was already consumed).
  ///
  /// This exists separately from [taps] because [_tapController] is a
  /// *broadcast* stream: an event added while nobody is listening is
  /// dropped, not buffered. [init] resolves `getInitialMessage()` and
  /// finishes before `app.dart` gets a chance to attach its `taps`
  /// listener, so pushing the cold-start tap onto that stream during
  /// [init] would silently lose it -- which is exactly the bug this seam
  /// fixes. Callers should read this once, right after attaching [taps],
  /// and defer acting on it until the first frame (the router isn't
  /// guaranteed to exist yet at that point).
  NotificationTap? takeInitialTap() {
    final tap = _pendingInitialTap;
    _pendingInitialTap = null;
    return tap;
  }

  /// Initializes Firebase + local notifications, requests permission, and
  /// wires message/tap listeners. Returns `false` (and does nothing further)
  /// on any failure -- in particular, with no native Firebase config present
  /// this always returns `false`, by design (constraint: the app must work
  /// with no push config at all).
  Future<bool> init() async {
    if (_available) return true;

    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      _logOnce(
        'PushService unavailable: Firebase.initializeApp failed '
        '(expected with no native push config present)',
        e,
        st,
      );
      return false;
    }

    try {
      await _initLocalNotifications();
      await _messaging.requestPermission();

      _onMessageSub = _messaging.onMessage.listen(_showLocalNotification);
      _onMessageOpenedSub = _messaging.onMessageOpenedApp.listen(
        _handleRemoteMessageTap,
      );

      await _captureInitialTap();

      _available = true;
      return true;
    } catch (e, st) {
      _logOnce(
        'PushService unavailable: setup failed after Firebase init',
        e,
        st,
      );
      return false;
    }
  }

  /// Gets the current FCM token and registers it via `register_push_token`;
  /// subscribes to token refresh so a rotated token stays registered. No-op
  /// (including no interaction with [client]) when unavailable.
  Future<void> registerToken(SupabaseClient client) async {
    if (!_available) return;
    try {
      final platform = _platform();
      final api = _pushTokenApi ?? SupabasePushTokenApi(client);

      final token = await _messaging.getToken();
      if (token != null) await api.register(token, platform);

      _onTokenRefreshSub ??= _messaging.onTokenRefresh.listen((newToken) {
        unawaited(api.register(newToken, platform));
      });
    } catch (e, st) {
      developer.log(
        'PushService.registerToken failed',
        name: 'PushService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Unregisters the current FCM token via `unregister_push_token`, then
  /// deletes it locally so a fresh token is minted on next use (e.g. after
  /// sign-out on a shared device). No-op when unavailable.
  Future<void> unregisterToken(SupabaseClient client) async {
    if (!_available) return;
    try {
      final api = _pushTokenApi ?? SupabasePushTokenApi(client);

      final token = await _messaging.getToken();
      if (token != null) await api.unregister(token);

      await _messaging.deleteToken();
    } catch (e, st) {
      developer.log(
        'PushService.unregisterToken failed',
        name: 'PushService',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _onTokenRefreshSub?.cancel();
    await _tapController.close();
  }

  /// This app targets iOS + Android only (no web/desktop, per README), so a
  /// binary check is sufficient -- and it's what a bare `flutter test` host
  /// (macOS/Linux, neither iOS nor Android) resolves to as well: `'android'`,
  /// deterministically.
  String _platform() => Platform.isIOS ? 'ios' : 'android';

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _notifications.show(
      id: _localNotifId++,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Resolves `getInitialMessage()` and, if it carries a recognized routing
  /// hint, stashes it in [_pendingInitialTap] for [takeInitialTap]. Split
  /// out of [init] so a test can drive this exact cold-start capture logic
  /// (via [captureInitialTapForTesting]) against an injected [PushMessaging]
  /// fake, without needing a real Firebase app to reach it.
  Future<void> _captureInitialTap() async {
    final initial = await _messaging.getInitialMessage();
    if (initial == null) return;
    final tap = tapFromData(initial.data);
    if (tap != null) _pendingInitialTap = tap;
  }

  /// Test-only seam: exercises [_captureInitialTap] -- the same cold-start
  /// `getInitialMessage()` handling [init] performs on a real launch --
  /// without going through `Firebase.initializeApp()`. Used to prove
  /// [takeInitialTap] surfaces a tap captured this way.
  @visibleForTesting
  Future<void> captureInitialTapForTesting() => _captureInitialTap();

  void _handleRemoteMessageTap(RemoteMessage message) {
    final tap = tapFromData(message.data);
    if (tap != null) _tapController.add(tap);
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final tap = tapFromData(data);
      if (tap != null) _tapController.add(tap);
    } catch (_) {
      // Malformed/legacy payload -- never crash on a notification tap.
    }
  }

  void _logOnce(String message, Object error, StackTrace st) {
    _available = false;
    if (_loggedInitFailure) return;
    _loggedInitFailure = true;
    developer.log(message, name: 'PushService', error: error, stackTrace: st);
  }
}
