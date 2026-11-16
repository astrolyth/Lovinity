// test/features/daily/question_notification_pump_test.dart
//
// Regression coverage for FIX 3: questionNotificationPumpProvider must not
// depend on the current question id.
//
// The queue advances server-side the instant both partners answer, but a
// client only re-reads which question is current on an explicit "Next
// question" tap. When the pump was keyed on the question id it opened a
// per-question subscription, so noticing the advance tore that subscription
// down and opened a new one -- and `newRowDetector` deliberately never fires
// on a subscription's first emission (that is existing history, not new
// activity). Any partner answer already present in the new subscription's
// first snapshot was therefore absorbed as baseline and never notified.
//
// The window is user-driven and unbounded: you answer Q1 in the morning;
// your partner answers Q1 at night, taps "Next question" and answers Q2
// immediately. By the time your client repoints to Q2, their Q2 answer is
// already in the first emission. No notification, ever.
//
// These tests drive the REAL provider (not a re-declared copy of its key),
// so they bind to the shipped wiring: the subscription it opens, how many
// times it opens one, and what it does across a queue advance. Mirrors
// test/features/prayer_log/prayer_notification_detector_test.dart, which
// covers the same class of bug for the prayer pump.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/core/notifications/notification_providers.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/daily/data/question_repository.dart';
import 'package:lovinity/features/daily/domain/question_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/shared/models/couple.dart';
import 'package:lovinity/shared/models/daily_content.dart';

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

Session _signedInSession(String userId) {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn(userId);
  when(() => session.user).thenReturn(user);
  return session;
}

const _couple = Couple(
  id: 'couple-1',
  memberA: 'me',
  memberB: 'partner',
  status: 'active',
  longDistance: false,
);

const _q1 = QuestionOfDay(id: 'q1', question: 'Q1?');
const _q2 = QuestionOfDay(id: 'q2', question: 'Q2?');

QuestionAnswer _answer({required String questionId, required String authorId}) =>
    QuestionAnswer(
      id: '$questionId-$authorId',
      questionId: questionId,
      authorId: authorId,
      answer: 'an answer',
      createdAt: DateTime(2026, 8, 3),
    );

/// Stands in for the Supabase-backed repository, faithfully to the two
/// properties that matter here:
///  * a new subscription REPLAYS the current snapshot as its first emission
///    (that is what Supabase realtime streams do, and it is exactly what
///    `newRowDetector` absorbs as baseline), and
///  * `watchAnswers` is the same stream filtered to one question.
///
/// Both methods are implemented, so the pre-fix pump (which called
/// `watchAnswers`) runs against this fake just as happily as the post-fix one
/// -- the test therefore measures behaviour, not a missing stub.
class _FakeQuestionRepository extends Fake implements QuestionRepository {
  final _controller = StreamController<List<QuestionAnswer>>.broadcast();
  var _snapshot = <QuestionAnswer>[];

  /// How many subscriptions the pump has opened. The structural assertion:
  /// post-fix this stays at 1 across a queue advance.
  var coupleSubscriptions = 0;
  var questionSubscriptions = 0;

  /// Pushes a new full snapshot, as a realtime stream would.
  void emit(List<QuestionAnswer> rows) {
    _snapshot = rows;
    _controller.add(rows);
  }

  Stream<List<QuestionAnswer>> _replayThenFollow() async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Stream<List<QuestionAnswer>> watchCoupleAnswers({required String coupleId}) {
    coupleSubscriptions++;
    return _replayThenFollow();
  }

  @override
  Stream<List<QuestionAnswer>> watchAnswers({
    required String coupleId,
    required String questionId,
  }) {
    questionSubscriptions++;
    return _replayThenFollow().map((rows) => [
          for (final r in rows)
            if (r.questionId == questionId) r,
        ]);
  }

  Future<void> dispose() => _controller.close();
}

class _RecordingStore extends Fake implements NotificationStore {
  final titles = <String>[];

  @override
  Future<void> insertBestEffort({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) async {
    titles.add(title);
  }
}

/// Holds "which question the client currently believes is current", so a
/// queue advance can be simulated. The post-fix pump must not care.
class _CurrentQuestion extends Notifier<QuestionOfDay?> {
  @override
  QuestionOfDay? build() => _q1;
  void set(QuestionOfDay? q) => state = q;
}

final _currentQuestionState =
    NotifierProvider<_CurrentQuestion, QuestionOfDay?>(_CurrentQuestion.new);

void main() {
  late _FakeQuestionRepository repo;
  late _RecordingStore store;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeQuestionRepository();
    store = _RecordingStore();
    container = ProviderContainer(
      overrides: [
        authSessionProvider
            .overrideWith((ref) => Stream.value(_signedInSession('me'))),
        currentCoupleProvider.overrideWith((ref) => Stream.value(_couple)),
        // Routed through a notifier so the test can advance the queue.
        currentQuestionProvider
            .overrideWith((ref) async => ref.watch(_currentQuestionState)),
        questionRepositoryProvider.overrideWithValue(repo),
        notificationStoreProvider.overrideWithValue(store),
      ],
    );
    // Instantiate and keep the pump alive for the whole test.
    container.listen<void>(questionNotificationPumpProvider, (_, _) {},
        fireImmediately: true);
  });

  tearDown(() async {
    container.dispose();
    await repo.dispose();
  });

  /// Lets the overridden streams/futures and the provider graph settle.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the partner answers the NEXT question before this device repoints, '
      'and it still notifies (regression for FIX 3)', () async {
    // The exact reported sequence, and the one the ordering matters for:
    // the partner's Q2 answer lands while this device is still pointed at
    // Q1, and only afterwards does this device notice the advance. Pre-fix
    // that repoint tore down the Q1-scoped subscription and opened a
    // Q2-scoped one whose FIRST emission already contained their Q2 answer,
    // so `newRowDetector` absorbed it as baseline and it never notified.
    await settle();

    // Baseline: I have answered Q1, my partner has not. Existing history --
    // must not notify.
    repo.emit([_answer(questionId: 'q1', authorId: 'me')]);
    await settle();
    expect(store.titles, isEmpty);

    // Partner answers Q1. This one always notified, pre-fix and post-fix.
    repo.emit([
      _answer(questionId: 'q1', authorId: 'me'),
      _answer(questionId: 'q1', authorId: 'partner'),
    ]);
    await settle();
    expect(store.titles.length, 1);

    // Partner taps Next and answers Q2 immediately. This device is still on
    // Q1, so pre-fix its subscription filtered this row out entirely.
    repo.emit([
      _answer(questionId: 'q1', authorId: 'me'),
      _answer(questionId: 'q1', authorId: 'partner'),
      _answer(questionId: 'q2', authorId: 'partner'),
    ]);
    await settle();

    // Only now does this device re-read the queue and repoint to Q2.
    container.read(_currentQuestionState.notifier).set(_q2);
    await settle();

    expect(store.titles.length, 2,
        reason: 'the partner answering the next question must notify; '
            'pre-fix the repoint re-baselined it away permanently');
  });

  test('the partner answers the next question AFTER this device has already '
      'repointed, and it notifies', () async {
    // The benign ordering -- this one notified pre-fix too, because the Q2
    // answer arrived as an increment on an already-established
    // subscription rather than inside its first emission. Kept so the fix
    // is covered from both sides of the race, not just the broken side.
    await settle();

    repo.emit([
      _answer(questionId: 'q1', authorId: 'me'),
      _answer(questionId: 'q1', authorId: 'partner'),
    ]);
    await settle();
    final afterQ1 = store.titles.length;

    container.read(_currentQuestionState.notifier).set(_q2);
    await settle();

    repo.emit([
      _answer(questionId: 'q1', authorId: 'me'),
      _answer(questionId: 'q1', authorId: 'partner'),
      _answer(questionId: 'q2', authorId: 'partner'),
    ]);
    await settle();

    expect(store.titles.length, afterQ1 + 1);
  });

  test('the pump opens exactly ONE couple-wide subscription, and a queue '
      'advance does not restart it', () async {
    await settle();
    expect(repo.coupleSubscriptions, 1);
    expect(repo.questionSubscriptions, 0,
        reason: 'the pump must not use the question-scoped stream');

    container.read(_currentQuestionState.notifier).set(_q2);
    await settle();
    container.read(_currentQuestionState.notifier).set(null);
    await settle();

    expect(repo.coupleSubscriptions, 1,
        reason: 'a queue advance must not resubscribe -- every resubscribe '
            're-baselines newRowDetector and can swallow a partner answer');
  });

  test('the user\'s own answers never notify', () async {
    await settle();
    repo.emit(const []);
    await settle();
    repo.emit([_answer(questionId: 'q1', authorId: 'me')]);
    await settle();
    repo.emit([
      _answer(questionId: 'q1', authorId: 'me'),
      _answer(questionId: 'q2', authorId: 'me'),
    ]);
    await settle();

    expect(store.titles, isEmpty);
  });

  test('the notification title is not date-framed', () async {
    await settle();
    repo.emit(const []);
    await settle();
    repo.emit([_answer(questionId: 'q1', authorId: 'partner')]);
    await settle();

    expect(store.titles, hasLength(1));
    expect(store.titles.single.toLowerCase(), isNot(contains('today')),
        reason: 'questions come from a queue now, not a calendar day');
  });
}
