import 'dart:async';

import 'package:lovinity/core/theme/theme.dart';

/// Runs before every test file: endless decorative loops would keep
/// pumpAndSettle from ever settling.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  lovLoopingMotion = false;
  await testMain();
}
