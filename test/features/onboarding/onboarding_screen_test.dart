import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/core/widgets/lov_kit.dart';
import 'package:lovinity/features/onboarding/presentation/onboarding_screen.dart';

LovPrimaryButton _cta(WidgetTester t) =>
    t.widget<LovPrimaryButton>(find.byType(LovPrimaryButton));

void main() {
  testWidgets('continue stays disabled until a name, then until a role', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
    );
    await tester.pump();
    expect(_cta(tester).onPressed, isNull); // no name yet

    await tester.enterText(find.byType(TextField), 'Ridwan');
    await tester.pump();
    expect(_cta(tester).onPressed, isNotNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Husband'), findsOneWidget);
    expect(find.text('Wife'), findsOneWidget);
    expect(_cta(tester).onPressed, isNull); // role not chosen

    await tester.tap(find.text('Wife'));
    await tester.pump();
    expect(_cta(tester).onPressed, isNotNull);
  });
}
