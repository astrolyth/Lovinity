import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/daily/data/question_repository.dart';
import 'package:lovinity/features/daily/domain/question_providers.dart';
import 'package:lovinity/features/daily/presentation/question_screen.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/shared/models/daily_content.dart';
import 'package:lovinity/shared/models/user_profile.dart';

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

/// Drives [authSessionProvider] to a signed-in state -- same mocktail pattern
/// as test/core/crypto/crypto_providers_test.dart.
Session _signedInSession(String userId) {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn(userId);
  when(() => session.user).thenReturn(user);
  return session;
}

const _me = UserProfile(
  id: 'me',
  displayName: 'Ridwan',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'muslim_world_league',
  gender: 'male',
);

const _spouse = UserProfile(
  id: 'spouse',
  displayName: 'Naziha',
  timezone: 'UTC',
  madhhab: 'shafi',
  calcMethod: 'muslim_world_league',
  gender: 'female',
);

const _question = QuestionOfDay(
  id: 'q1',
  question: 'What made you smile today?',
);

QuestionAnswer _answer(String authorId, String text) => QuestionAnswer(
      id: 'a-$authorId',
      questionId: _question.id,
      authorId: authorId,
      answer: text,
      createdAt: DateTime(2026, 8, 2),
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<QuestionAnswer> answers,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authSessionProvider
          .overrideWith((ref) => Stream.value(_signedInSession('me'))),
      ownProfileProvider.overrideWith((ref) async => _me),
      spouseProfileProvider.overrideWith((ref) async => _spouse),
      currentQuestionProvider.overrideWith((ref) async => _question),
      questionAnswersProvider.overrideWith((ref) => Stream.value(answers)),
    ],
    child: const MaterialApp(home: QuestionScreen()),
  ));
  // Resolve the overridden futures/streams, then run out the staggered
  // LovEnter entrance delays so no timer is left pending at teardown.
  // Fixed pumps rather than pumpAndSettle: the loading state renders a
  // LovShimmerBox, whose looping animation never settles.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('neither answered: composer is open and the spouse block is '
      'pending', (tester) async {
    await _pumpScreen(tester, answers: const []);

    expect(find.text(_question.question), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Send answer'), findsOneWidget);
    expect(find.text('Waiting for their answer.'), findsOneWidget);
    expect(find.text('Next question'), findsNothing);
  });

  testWidgets('only the partner answered: composer stays open and their '
      'answer stays hidden', (tester) async {
    await _pumpScreen(tester, answers: [_answer('spouse', 'The dua you sent')]);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Send answer'), findsOneWidget);
    expect(find.text('The dua you sent'), findsNothing,
        reason: 'the spouse answer must not leak before you have answered');
    expect(find.text('Answer to reveal.'), findsOneWidget);
    expect(find.text('Next question'), findsNothing);
  });

  testWidgets('both answered: answers reveal, editing is locked, and Next '
      'question is offered', (tester) async {
    await _pumpScreen(tester, answers: [
      _answer('me', 'Your voice note'),
      _answer('spouse', 'The dua you sent'),
    ]);

    expect(find.text('Your voice note'), findsOneWidget);
    expect(find.text('The dua you sent'), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'answers are final once revealed -- no edit affordance may '
            'remain anywhere on the screen');
    expect(find.text('Send answer'), findsNothing);
    expect(find.text('Next question'), findsOneWidget);
  });
}
