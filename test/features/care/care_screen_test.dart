// test/features/care/care_screen_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/shared/models/care_tip.dart';
import 'package:lovinity/features/care/domain/care_providers.dart';
import 'package:lovinity/features/care/presentation/care_screen.dart';

void main() {
  testWidgets('shows a tip, its pending-review note, and medical disclaimer',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        careTipsProvider.overrideWith((ref) async => const [
          CareTip(audience: 'wife', category: 'spiritual', title: 'Close to Allah',
              body: 'Body', reviewStatus: 'pending_review',
              islamicReference: 'Q 2:185'),
        ]),
      ],
      child: const MaterialApp(home: CareScreen()),
    ));
    await tester.pump();
    expect(find.text('Close to Allah'), findsOneWidget);
    expect(find.textContaining('verify'), findsWidgets); // pending-review note
    expect(find.textContaining('not medical advice'), findsOneWidget);
  });

  testWidgets('shows the medical disclaimer while care tips are still loading',
      (tester) async {
    // A future that never completes keeps careTipsProvider in the loading
    // state for the lifetime of the test.
    final neverCompletes = Completer<List<CareTip>>().future;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        careTipsProvider.overrideWith((ref) => neverCompletes),
      ],
      child: const MaterialApp(home: CareScreen()),
    ));
    await tester.pump();

    expect(find.textContaining('not medical advice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
