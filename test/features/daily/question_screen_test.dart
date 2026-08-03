import 'dart:async';

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

  testWidgets('queue exhausted: the all-caught-up empty state replaces the '
      'composer', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider
            .overrideWith((ref) => Stream.value(_signedInSession('me'))),
        ownProfileProvider.overrideWith((ref) async => _me),
        spouseProfileProvider.overrideWith((ref) async => _spouse),
        // A resolved `null` -- hasValue is true, so this is the exhausted
        // queue, not a load still in flight.
        currentQuestionProvider.overrideWith((ref) async => null),
        questionAnswersProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: const MaterialApp(home: QuestionScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('New questions are on their way. Check back soon.'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'there is no question to answer, so no composer may render');
    expect(find.text('Next question'), findsNothing);
  });

  testWidgets('the queue advances on the explicit tap and on nothing else',
      (tester) async {
    // The feature's defining property. A static override can't catch a
    // regression here -- the question would be identical either way -- so
    // this counts how many times currentQuestionProvider is built and drives
    // the answers from a controller, separating "the second answer landed"
    // from "the user tapped".
    var questionBuilds = 0;
    final answers = StreamController<List<QuestionAnswer>>();
    addTearDown(answers.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider
            .overrideWith((ref) => Stream.value(_signedInSession('me'))),
        ownProfileProvider.overrideWith((ref) async => _me),
        spouseProfileProvider.overrideWith((ref) async => _spouse),
        currentQuestionProvider.overrideWith((ref) async {
          questionBuilds++;
          return _question;
        }),
        questionAnswersProvider.overrideWith((ref) => answers.stream),
      ],
      child: const MaterialApp(home: QuestionScreen()),
    ));
    answers.add([_answer('me', 'Your voice note')]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(questionBuilds, 1,
        reason: 'answers arriving must never rebuild the question provider');

    // The partner answers: the reveal happens, and that is all it does.
    answers.add([
      _answer('me', 'Your voice note'),
      _answer('spouse', 'The dua you sent'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('The dua you sent'), findsOneWidget);
    expect(find.text('Next question'), findsOneWidget);
    expect(questionBuilds, 1,
        reason: 'the second answer must not advance the queue -- if it did, '
            'the reveal would be swapped away before either partner could '
            'read it');

    await tester.tap(find.text('Next question'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // A third pump: the refetched question remounts the LovEnter stagger, and
    // its delay timers are created during the previous frame's build -- they
    // have to be run out or the tree is disposed with timers pending.
    await tester.pump(const Duration(seconds: 1));

    expect(questionBuilds, 2,
        reason: 'the explicit tap is the one thing that advances the queue');
  });
}
