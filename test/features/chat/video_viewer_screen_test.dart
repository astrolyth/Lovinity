import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/video_viewer_screen.dart';

void main() {
  testWidgets('constructs without hanging and shows AppBar', (tester) async {
    // Verifies the screen constructs without hanging/crashing. In a plain
    // widget test without a real video_player platform implementation,
    // initialize() rejects immediately, triggering the error state
    // (tested separately below). This test just confirms basic construction.
    await tester.pumpWidget(
      const MaterialApp(home: VideoViewerScreen(filePath: '/tmp/does-not-need-to-exist.mp4')),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('shows error state when video initialization fails',
      (tester) async {
    // No real video_player platform implementation is registered, so
    // initialize() will reject immediately or on first pump. After the
    // catchError fires and setState updates, the error UI (icon, message,
    // retry button) should be visible instead of the loading spinner.
    await tester.pumpWidget(
      const MaterialApp(home: VideoViewerScreen(filePath: '/tmp/does-not-need-to-exist.mp4')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(Text), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data?.contains("Couldn't play this video") == true,
      ),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
