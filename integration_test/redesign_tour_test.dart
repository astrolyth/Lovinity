// Visual tour of the redesign on a real device/simulator. Visits each screen
// and prints `TOUR:<name>`; a shell watcher screenshots the simulator on each
// marker. Run by hand (needs a signed-in, paired session on the device):
//   flutter test integration_test/redesign_tour_test.dart -d <device> \
//     --dart-define-from-file=config/supabase.local.json
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lovinity/app.dart';
import 'package:lovinity/core/router/app_router.dart';
import 'package:lovinity/main.dart' as app;

const _stops = [
  ('home', '/home'),
  ('moments', '/moments'),
  ('wall', '/wall'),
  ('chat', '/home/chat'),
  ('prayer', '/home/prayer'),
  ('duas', '/home/duas'),
  ('tasbih', '/home/tasbih'),
  ('today', '/home/today'),
  ('letters', '/home/letters'),
  ('us', '/home/us'),
  ('cycle', '/home/cycle'),
  ('week', '/home/week'),
  ('notifications', '/home/notifications'),
  ('settings', '/home/settings'),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('redesign tour', (tester) async {
    await app.main();
    Future<void> settle(int seconds) =>
        tester.runAsync(() => Future.delayed(Duration(seconds: seconds)));
    await settle(8);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LovinityApp)),
    );
    final router = container.read(appRouterProvider);
    for (final (name, path) in _stops) {
      router.go(path);
      await settle(3);
      // ignore: avoid_print
      print('TOUR:$name');
      await settle(3); // the watcher screenshots during this pause
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
