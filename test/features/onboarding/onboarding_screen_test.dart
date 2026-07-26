import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('onboarding shows male/female selection and disables continue until chosen',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: OnboardingScreen()),
    ));
    expect(find.text('Man'), findsOneWidget);
    expect(find.text('Woman'), findsOneWidget);
    final continueBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'));
    expect(continueBtn.onPressed, isNull); // disabled until gender chosen
  });
}
