import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/config/config_error_app.dart';

void main() {
  testWidgets('shows the config fix on screen', (tester) async {
    await tester.pumpWidget(
      const ConfigErrorApp(message: 'run with --dart-define-from-file'),
    );
    expect(find.text('run with --dart-define-from-file'), findsOneWidget);
  });
}
