// Integration test against LOCAL Supabase for the two reveal gates.
//
// Both features rest on the same claim: you cannot see your spouse's answer
// before committing your own. If that fails, nothing crashes — the check-in
// quietly becomes copying and the guessing game quietly becomes cheating. The
// feature still renders, it just stops meaning anything, which is why this
// needs a test rather than a code review.
//
// Everything here runs through the spouse's OWN JWT, i.e. the exact path a
// modified client would take. A test that drove the widget would prove nothing:
// the question is whether the server hands the row over, not whether the UI
// chooses to draw it.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/learning/data/lesson_repository.dart';
import 'package:lovinity/features/lovemap/data/lovemap_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

late SupabaseClient adminClient;

SupabaseClient _anonClient() => SupabaseClient(
      _url,
      _anon,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

Future<String> _signUp(
    SupabaseClient client, String email, String gender) async {
  final res = await client.auth.signUp(email: email, password: 'password123');
  final id = res.user!.id;
  addTearDown(() => adminClient.auth.admin.deleteUser(id));
  await client.from('users').update({'gender': gender}).eq('id', id);
  return id;
}

Future<String> _pair(SupabaseClient a, SupabaseClient b) async {
  final inviteRes = await a.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  await b.rpc('accept_pairing_invite',
      params: {'p_code': inviteRow['code'] as String});
  return await a.rpc('current_couple') as String;
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  group('love map', () {
    test('a truth is hidden until the guesser commits a guess', () async {
      final husband = _anonClient();
      final wife = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final husbandId =
          await _signUp(husband, 'lm-h-$stamp@test.local', 'male');
      final wifeId = await _signUp(wife, 'lm-w-$stamp@test.local', 'female');
      final coupleId = await _pair(husband, wife);

      final repoH = LoveMapRepository(husband);
      final repoW = LoveMapRepository(wife);

      final quizzes = await repoH.fetchQuizzes();
      expect(quizzes, isNotEmpty,
          reason: 'seeded approved quizzes should be readable');
      final quiz = quizzes.first;

      // The wife records what is true about her.
      await repoW.setTruth(
        coupleId: coupleId,
        quizId: quiz.id,
        subjectId: wifeId,
        answer: 'Surah ad-Duha',
      );

      // The husband has not guessed yet, so he must not see it.
      final beforeGuess = await repoH.watchTruths(coupleId: coupleId).first;
      expect(
        beforeGuess.where((t) => t.subjectId == wifeId),
        isEmpty,
        reason: 'the guesser must not be able to read the answer first',
      );

      // She can always see her own.
      final herOwn = await repoW.watchTruths(coupleId: coupleId).first;
      expect(herOwn.single.answer, 'Surah ad-Duha');

      // He commits a guess — this is what unlocks it.
      await repoH.submitGuess(
        coupleId: coupleId,
        quizId: quiz.id,
        guesserId: husbandId,
        subjectId: wifeId,
        guess: 'Surah ar-Rahman',
      );

      final afterGuess = await repoH.watchTruths(coupleId: coupleId).first;
      expect(
        afterGuess.where((t) => t.subjectId == wifeId).single.answer,
        'Surah ad-Duha',
        reason: 'committing a guess reveals the answer',
      );
    });

    test('guessing one question does not unlock the others', () async {
      final husband = _anonClient();
      final wife = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final husbandId =
          await _signUp(husband, 'lm2-h-$stamp@test.local', 'male');
      final wifeId = await _signUp(wife, 'lm2-w-$stamp@test.local', 'female');
      final coupleId = await _pair(husband, wife);

      final repoH = LoveMapRepository(husband);
      final repoW = LoveMapRepository(wife);
      final quizzes = await repoH.fetchQuizzes();
      final first = quizzes[0];
      final second = quizzes[1];

      for (final q in [first, second]) {
        await repoW.setTruth(
          coupleId: coupleId,
          quizId: q.id,
          subjectId: wifeId,
          answer: 'answer for ${q.id}',
        );
      }

      await repoH.submitGuess(
        coupleId: coupleId,
        quizId: first.id,
        guesserId: husbandId,
        subjectId: wifeId,
        guess: 'a guess',
      );

      final visible = await repoH.watchTruths(coupleId: coupleId).first;
      final quizIds = visible.map((t) => t.quizId).toSet();
      expect(quizIds, contains(first.id));
      expect(quizIds, isNot(contains(second.id)),
          reason: 'the gate is per question, not all-or-nothing');
    });

    test('a player cannot record a truth about their spouse', () async {
      final husband = _anonClient();
      final wife = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      await _signUp(husband, 'lm3-h-$stamp@test.local', 'male');
      final wifeId = await _signUp(wife, 'lm3-w-$stamp@test.local', 'female');
      final coupleId = await _pair(husband, wife);

      final quizzes = await LoveMapRepository(husband).fetchQuizzes();

      // Writing a truth as the spouse would let a player fabricate the answer
      // they are about to be graded against.
      await expectLater(
        LoveMapRepository(husband).setTruth(
          coupleId: coupleId,
          quizId: quizzes.first.id,
          subjectId: wifeId,
          answer: 'forged',
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('unapproved questions are never served', () async {
      final husband = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      await _signUp(husband, 'lm4-h-$stamp@test.local', 'male');

      final unapprovedId = (await adminClient
          .from('love_map_quizzes')
          .insert({
            'question': 'UNAPPROVED probe question',
            'category': 'deen',
            'approved': false,
          })
          .select('id')
          .single())['id'] as String;
      addTearDown(() =>
          adminClient.from('love_map_quizzes').delete().eq('id', unapprovedId));

      final served = await LoveMapRepository(husband).fetchQuizzes();
      expect(
        served.map((q) => q.id),
        isNot(contains(unapprovedId)),
        reason: 'the approval gate must hold for generated content',
      );
    });
  });

  group('lessons', () {
    test('a spouse\'s answers are hidden until you complete the lesson',
        () async {
      final husband = _anonClient();
      final wife = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final husbandId =
          await _signUp(husband, 'ls-h-$stamp@test.local', 'male');
      final wifeId = await _signUp(wife, 'ls-w-$stamp@test.local', 'female');
      final coupleId = await _pair(husband, wife);

      // Lessons seed as unapproved (they await scholarly review), so approve
      // one for the duration of this test rather than asserting against an
      // empty library.
      final lessonId = (await adminClient
          .from('learning_lessons')
          .select('id')
          .limit(1)
          .single())['id'] as String;
      await adminClient
          .from('learning_lessons')
          .update({'approved': true}).eq('id', lessonId);
      addTearDown(() => adminClient
          .from('learning_lessons')
          .update({'approved': false}).eq('id', lessonId));

      final repoH = LessonRepository(husband);
      final repoW = LessonRepository(wife);

      expect((await repoH.fetchLessons()).map((l) => l.id),
          contains(lessonId));

      // She answers first.
      await repoW.submit(
        coupleId: coupleId,
        userId: wifeId,
        lessonId: lessonId,
        answers: {'0': 'her first answer', '1': 'her second answer'},
      );

      // He has not answered, so hers must not be readable.
      final beforeHe = await repoH.watchProgress(coupleId: coupleId).first;
      expect(
        beforeHe.where((p) => p.userId == wifeId),
        isEmpty,
        reason: 'answering must not be optional to see your spouse\'s answers',
      );

      // He answers.
      await repoH.submit(
        coupleId: coupleId,
        userId: husbandId,
        lessonId: lessonId,
        answers: {'0': 'his first answer', '1': 'his second answer'},
      );

      final afterHe = await repoH.watchProgress(coupleId: coupleId).first;
      final hers = afterHe.where((p) => p.userId == wifeId).single;
      expect(hers.answerFor(0), 'her first answer');
      expect(hers.answerFor(1), 'her second answer');
    });

    test('unapproved lessons are never served', () async {
      final husband = _anonClient();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      await _signUp(husband, 'ls2-h-$stamp@test.local', 'male');

      // The seeded lessons are all unapproved, which is exactly the state the
      // gate is meant to hold in.
      final served = await LessonRepository(husband).fetchLessons();
      final unapprovedCount = (await adminClient
              .from('learning_lessons')
              .select('id')
              .eq('approved', false))
          .length;
      expect(unapprovedCount, greaterThan(0),
          reason: 'seeded lessons should be awaiting review');
      expect(served, isEmpty,
          reason: 'nothing making a religious claim ships unreviewed');
    });
  });
}
