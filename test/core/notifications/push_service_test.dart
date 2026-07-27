// test/core/notifications/push_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/core/notifications/push_service.dart';

class _MockPushMessaging extends Mock implements PushMessaging {}

class _MockPushTokenApi extends Mock implements PushTokenApi {}

/// Never actually invoked in the "unavailable" tests below -- PushService
/// must short-circuit before touching it at all -- but it needs *some*
/// SupabaseClient-typed value to pass to registerToken/unregisterToken.
class _MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  group('registerToken', () {
    late _MockPushMessaging messaging;
    late _MockPushTokenApi tokenApi;
    late PushService service;
    late SupabaseClient client;

    setUp(() {
      messaging = _MockPushMessaging();
      tokenApi = _MockPushTokenApi();
      client = _MockSupabaseClient();
      service = PushService.availableForTesting(
        messaging: messaging,
        pushTokenApi: tokenApi,
      );
      when(
        () => messaging.onTokenRefresh,
      ).thenAnswer((_) => const Stream<String>.empty());
      when(() => tokenApi.register(any(), any())).thenAnswer((_) async {});
    });

    test(
      'calls register_push_token with the FCM token and this platform',
      () async {
        when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-token-1');

        await service.registerToken(client);

        // The unit test host is neither iOS nor Android, so PushService's real
        // Platform.isIOS/isAndroid check resolves to 'android' here (mirrors
        // how the ternary actually runs in CI) -- this exercises the same
        // branch a real Android device hits.
        verify(() => tokenApi.register('fcm-token-1', 'android')).called(1);
        verifyZeroInteractions(client);
      },
    );

    test('does nothing when getToken returns null', () async {
      when(() => messaging.getToken()).thenAnswer((_) async => null);

      await service.registerToken(client);

      verifyNever(() => tokenApi.register(any(), any()));
    });

    test(
      'is a safe no-op on an unavailable service (never touches client)',
      () async {
        final unavailable = PushService();

        await unavailable.registerToken(client);

        verifyZeroInteractions(client);
      },
    );
  });

  group('unregisterToken', () {
    late _MockPushMessaging messaging;
    late _MockPushTokenApi tokenApi;
    late PushService service;
    late SupabaseClient client;

    setUp(() {
      messaging = _MockPushMessaging();
      tokenApi = _MockPushTokenApi();
      client = _MockSupabaseClient();
      service = PushService.availableForTesting(
        messaging: messaging,
        pushTokenApi: tokenApi,
      );
      when(() => tokenApi.unregister(any())).thenAnswer((_) async {});
      when(() => messaging.deleteToken()).thenAnswer((_) async {});
    });

    test('calls unregister_push_token then clears the local token', () async {
      when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-token-2');

      await service.unregisterToken(client);

      verify(() => tokenApi.unregister('fcm-token-2')).called(1);
      verify(() => messaging.deleteToken()).called(1);
      verifyZeroInteractions(client);
    });

    test(
      'still deletes the local token when there is no current token',
      () async {
        when(() => messaging.getToken()).thenAnswer((_) async => null);

        await service.unregisterToken(client);

        verifyNever(() => tokenApi.unregister(any()));
        verify(() => messaging.deleteToken()).called(1);
      },
    );

    test(
      'is a safe no-op on an unavailable service (never touches client)',
      () async {
        final unavailable = PushService();

        await unavailable.unregisterToken(client);

        verifyZeroInteractions(client);
      },
    );
  });

  group('tapFromData', () {
    test("maps data:{'type':'chat'} to NotificationTap(type:'chat')", () {
      final tap = tapFromData({'type': 'chat'});
      expect(tap, const NotificationTap(type: 'chat'));
    });

    test("maps data:{'type':'pairing'} to NotificationTap(type:'pairing')", () {
      final tap = tapFromData({'type': 'pairing'});
      expect(tap, const NotificationTap(type: 'pairing'));
    });

    test('returns null for missing type', () {
      expect(tapFromData({}), isNull);
    });

    test('returns null for null data', () {
      expect(tapFromData(null), isNull);
    });

    test('returns null for a non-string type', () {
      expect(tapFromData({'type': 42}), isNull);
    });
  });

  group('NotificationTap equality', () {
    test('two taps with the same type are equal', () {
      expect(
        const NotificationTap(type: 'chat'),
        const NotificationTap(type: 'chat'),
      );
    });

    test('taps with different types are not equal', () {
      expect(
        const NotificationTap(type: 'chat') ==
            const NotificationTap(type: 'pairing'),
        isFalse,
      );
    });
  });
}
