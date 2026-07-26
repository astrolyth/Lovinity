import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/scoring/domain/score_engine.dart';
import 'package:lovinity/features/scoring/domain/scoreboard_providers.dart';
import 'package:lovinity/features/scoring/presentation/scoreboard_card.dart';

void main() {
  testWidgets('renders both percentages', (tester) async {
    const board = CoupleScoreboard(
      own: ScoreResult(prayed: 95, due: 100, currentStreak: 7, longestStreak: 9),
      spouse: ScoreResult(prayed: 90, due: 100, currentStreak: 4, longestStreak: 6),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scoreboardProvider.overrideWith((ref) async => board),
      ],
      child: const MaterialApp(home: Scaffold(body: ScoreboardCard())),
    ));
    await tester.pump();
    expect(find.textContaining('95%'), findsOneWidget);
    expect(find.textContaining('90%'), findsOneWidget);
  });
}
