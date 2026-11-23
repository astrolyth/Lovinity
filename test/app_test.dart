// test/app_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:lovinity/app.dart';
import 'package:lovinity/core/notifications/push_service.dart';

void main() {
  group('routeForTap', () {
    test("'chat' routes to /home/chat", () {
      expect(routeForTap(const NotificationTap(type: 'chat')), '/home/chat');
    });

    test("'message' routes to /home/chat", () {
      expect(routeForTap(const NotificationTap(type: 'message')), '/home/chat');
    });

    test("'reaction' routes to /home/chat", () {
      expect(
        routeForTap(const NotificationTap(type: 'reaction')),
        '/home/chat',
      );
    });

    test("'pairing' routes to /home", () {
      expect(routeForTap(const NotificationTap(type: 'pairing')), '/home');
    });

    test("'wall' routes to /wall", () {
      expect(routeForTap(const NotificationTap(type: 'wall')), '/wall');
    });

    test("'moment' routes to /moments, the nudge to the camera", () {
      expect(routeForTap(const NotificationTap(type: 'moment')), '/moments');
      expect(
        routeForTap(const NotificationTap(type: 'moment_nudge')),
        '/moments/camera',
      );
    });

    test('an unrecognized type routes nowhere', () {
      expect(routeForTap(const NotificationTap(type: 'unknown')), isNull);
    });
  });
}
