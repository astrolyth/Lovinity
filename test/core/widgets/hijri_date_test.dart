import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/widgets/hijri_date.dart';

/// Pumps [child] inside a hard width constraint, mirroring the home header
/// where [HijriDate] sits in an `Expanded` beside the bell + settings icons.
Future<void> _pumpAtWidth(
  WidgetTester tester,
  Widget child, {
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  // A long Hijri month name ("Rabi al-Thani") next to a long weekday/month
  // ("Sunday, 12 October") is the realistic worst case -- it is what
  // overflowed the real home header on an iPhone.
  final longDate = DateTime(2026, 10, 12);

  testWidgets('does not overflow when the row is narrower than both dates',
      (tester) async {
    await _pumpAtWidth(tester, HijriDate(date: longDate), width: 220);

    expect(tester.takeException(), isNull,
        reason: 'the date line must shrink to fit, not overflow its row');
  });

  testWidgets('does not overflow at a very narrow width', (tester) async {
    await _pumpAtWidth(tester, HijriDate(date: longDate), width: 120);

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps both dates readable rather than dropping one',
      (tester) async {
    await _pumpAtWidth(tester, HijriDate(date: longDate), width: 220);

    // Both halves must still render -- the fix must not silently truncate the
    // Gregorian date away to make room.
    expect(find.textContaining('1448 AH'), findsOneWidget);
    expect(find.textContaining('October'), findsOneWidget);
  });

  testWidgets('still renders a single date when showBoth is false',
      (tester) async {
    await _pumpAtWidth(
      tester,
      HijriDate(date: longDate, showBoth: false),
      width: 120,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('1448 AH'), findsOneWidget);
  });
}
