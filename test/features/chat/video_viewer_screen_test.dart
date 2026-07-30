import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/video_viewer_screen.dart';

void main() {
  testWidgets('shows a loading indicator before the video plugin initializes',
      (tester) async {
    // No real video_player platform implementation is registered in a plain
    // widget test, so initialize() never resolves -- this only asserts the
    // pre-initialization loading state renders without crashing, plus the
    // play/pause FAB and dismiss AppBar are present.
    await tester.pumpWidget(
      const MaterialApp(home: VideoViewerScreen(filePath: '/tmp/does-not-need-to-exist.mp4')),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
