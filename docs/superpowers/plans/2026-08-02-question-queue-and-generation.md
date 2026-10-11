# Question Queue + AI Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the date-assigned question of the day with a per-couple queue that advances only when both partners have answered, and keep that queue supplied by an AI generator whose output lands in a human review queue.

**Architecture:** A `get_current_question()` Postgres RPC returns the first `status='approved'` question the couple hasn't both answered, ordered deterministically per couple via `hashtext(couple_id || question_id)` — so both partners resolve the same question with no stored cursor. `daily_questions` gains `status`/`source`/`created_at`; a `generate-questions` edge function calls the Claude API with structured outputs and inserts new rows as `status='pending'`. Verse and hadith stay date-based and untouched.

**Tech Stack:** Postgres/plpgsql, Supabase edge functions (Deno/TypeScript), `@anthropic-ai/sdk`, Flutter, Riverpod.

**Full spec:** `docs/superpowers/specs/2026-08-02-question-queue-and-generation-design.md`

## Global Constraints

- **Only `status = 'approved'` questions may reach a couple.** Enforced inside the RPC, never client-side.
- **Generated questions are always inserted as `status='pending'`.** The edge function must never write `'approved'`.
- `get_daily_content` is **not modified** — verse and hadith keep working exactly as they do today. The question feature simply stops reading its `question_id`.
- The 14 existing `daily_questions` rows must be backfilled to `status='approved'`, `source='seed'` so current behavior is preserved.
- No editing an answer once both partners have answered (the reveal must stay meaningful).
- After the reveal, the next question loads **only on an explicit user tap** — never automatically, or the user never gets to read their partner's answer.
- `ANTHROPIC_API_KEY` missing must fail loudly (non-2xx + logged), never silently no-op.
- `flutter analyze` stays clean (10 known pre-existing info lints, 0 errors) and `flutter test` stays green after every task.

---

## File Map

| File | Change |
|---|---|
| `supabase/migrations/20260802000003_question_queue.sql` | New — `status`/`source`/`created_at` columns, backfill, `get_current_question()` RPC |
| `supabase/tests/question_queue_test.sql` | New — RPC behavior assertions |
| `lib/features/daily/data/question_repository.dart` | Add `currentQuestion()` |
| `lib/features/daily/domain/question_providers.dart` | Add `currentQuestionProvider`; repoint answers + notification pump at it |
| `lib/features/daily/presentation/question_screen.dart` | Use `currentQuestionProvider`; lock edit after reveal; "Next question"; empty state |
| `supabase/functions/generate-questions/logic.ts` | New — pure prompt/schema/validation |
| `supabase/functions/generate-questions/index.ts` | New — Deno.serve, Claude call, insert as pending |
| `supabase/functions/generate-questions/logic.test.ts` | New — unit tests for the pure logic |

---

### Task 1: Schema — status/source/created_at + backfill

**Files:**
- Create: `supabase/migrations/20260802000003_question_queue.sql`

**Interfaces:**
- Produces: `daily_questions.status` (`'pending'|'approved'|'rejected'`), `.source` (`'seed'|'generated'`), `.created_at`; the 14 seeded rows backfilled to `approved`/`seed`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260802000003_question_queue.sql`:

```sql
-- Question queue: questions are drawn from a per-couple queue that advances
-- only when BOTH partners have answered, instead of being assigned per
-- calendar date. Also adds a review-queue status so AI-generated questions
-- (see supabase/functions/generate-questions) never reach a couple until a
-- human approves them.
--
-- get_daily_content() is deliberately NOT modified -- verse and hadith stay
-- date-based. Only the question feature moves to the queue.

alter table public.daily_questions
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  add column if not exists source text not null default 'generated'
    check (source in ('seed', 'generated')),
  add column if not exists created_at timestamptz not null default now();

-- The pre-existing seeded questions are already in circulation: preserve
-- today's behavior exactly by approving them.
update public.daily_questions
   set status = 'approved', source = 'seed'
 where source = 'generated' and created_at <= now();

create index if not exists daily_questions_status_idx
  on public.daily_questions(status);
```

- [ ] **Step 2: Apply and verify the backfill**

Run: `supabase db reset` (local), then:

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "select status, source, count(*) from public.daily_questions group by 1,2;"
```

Expected: one row — `approved | seed | 14`. If any row is `pending`, the backfill's `where` clause didn't match; fix before continuing.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260802000003_question_queue.sql
git commit -m "feat(daily): add review-queue status to daily_questions"
```

---

### Task 2: `get_current_question()` RPC

**Files:**
- Modify: `supabase/migrations/20260802000003_question_queue.sql` (append)
- Create: `supabase/tests/question_queue_test.sql`

**Interfaces:**
- Consumes: `public.current_couple()` (existing, `supabase/migrations/20260712000001_foundation.sql`).
- Produces: `public.get_current_question()` returning `(id uuid, question text, category text, language text)` — zero rows when the couple has answered everything.

- [ ] **Step 1: Write the failing SQL test**

Create `supabase/tests/question_queue_test.sql`, following the style of `supabase/tests/push_notifications_test.sql` (DO blocks that `raise exception` on failure, wrapped in a transaction that is rolled back):

```sql
-- Plain psql assertion script for 20260802000003_question_queue.sql.
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/question_queue_test.sql

begin;

insert into auth.users (id) values
  ('99999999-3000-0000-0000-00000000000a'),
  ('99999999-3000-0000-0000-00000000000b');

insert into public.couples (id, member_a, member_b)
values ('99999999-3000-0000-0000-0000000000c1',
        '99999999-3000-0000-0000-00000000000a',
        '99999999-3000-0000-0000-00000000000b');

-- Isolate from the seeded pool: drop everything, insert a known set.
delete from public.question_answers;
delete from public.daily_content;
delete from public.daily_questions;
insert into public.daily_questions (id, question, category, language, status, source) values
  ('99999999-3000-0000-0000-0000000000q1', 'Q1', 'playful', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000q2', 'Q2', 'deen', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000q3', 'Q3', 'future', 'en', 'pending', 'generated');

-- 1. Both partners resolve the SAME question.
do $$
declare a_q uuid; b_q uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into a_q from public.get_current_question();
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000b',true);
  select id into b_q from public.get_current_question();
  if a_q is null or a_q <> b_q then
    raise exception 'FAIL: partners disagree on current question (% vs %)', a_q, b_q;
  end if;
  raise notice 'PASS: both partners resolve the same question';
end $$;
reset role;

-- 2. A 'pending' question is never selected.
do $$
declare picked uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into picked from public.get_current_question();
  if picked = '99999999-3000-0000-0000-0000000000q3' then
    raise exception 'FAIL: a pending question was served to a couple';
  end if;
  raise notice 'PASS: pending questions are excluded';
end $$;
reset role;

-- 3. ONE answer does not advance the queue; BOTH does.
do $$
declare first_q uuid; still_q uuid; next_q uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into first_q from public.get_current_question();

  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', first_q,
          '99999999-3000-0000-0000-00000000000a', 'a answer');

  select id into still_q from public.get_current_question();
  if still_q <> first_q then
    raise exception 'FAIL: queue advanced after only one partner answered';
  end if;
  raise notice 'PASS: one answer does not advance the queue';

  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', first_q,
          '99999999-3000-0000-0000-00000000000b', 'b answer');

  select id into next_q from public.get_current_question();
  if next_q = first_q then
    raise exception 'FAIL: queue did not advance after both partners answered';
  end if;
  raise notice 'PASS: queue advances once both partners answered';
end $$;
reset role;

-- 4. Exhausted queue returns zero rows (not an error).
do $$
declare remaining uuid; n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into remaining from public.get_current_question();
  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', remaining,
          '99999999-3000-0000-0000-00000000000a', 'a'),
         ('99999999-3000-0000-0000-0000000000c1', remaining,
          '99999999-3000-0000-0000-00000000000b', 'b');

  select count(*) into n from public.get_current_question();
  if n <> 0 then
    raise exception 'FAIL: exhausted queue returned % rows, expected 0', n;
  end if;
  raise notice 'PASS: exhausted queue returns zero rows';
end $$;
reset role;

rollback;
```

- [ ] **Step 2: Run to verify it fails**

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f supabase/tests/question_queue_test.sql
```

Expected: FAIL — `function public.get_current_question() does not exist`.

- [ ] **Step 3: Append the RPC to the migration**

Append to `supabase/migrations/20260802000003_question_queue.sql`:

```sql
-- The couple's current question: the first APPROVED question they have not
-- both answered, in an order derived deterministically from the couple id --
-- so both partners resolve the same question with no stored cursor, and
-- different couples get a different sequence. Returns zero rows when the
-- couple has answered every approved question.
create or replace function public.get_current_question()
returns table (
  id uuid,
  question text,
  category text,
  language text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_couple uuid := public.current_couple();
begin
  if v_couple is null then raise exception 'no_couple'; end if;

  return query
  select q.id, q.question, q.category, q.language
    from public.daily_questions q
   where q.status = 'approved'
     and (
       select count(distinct qa.author_id)
         from public.question_answers qa
        where qa.couple_id = v_couple
          and qa.question_id = q.id
     ) < 2
   -- hashtext is deterministic for a given input, so this ordering is stable
   -- across calls and identical for both partners. q.id breaks ties.
   order by hashtext(v_couple::text || q.id::text), q.id
   limit 1;
end;
$$;

grant execute on function public.get_current_question() to authenticated;
```

Apply with `supabase db reset`.

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: 5x `PASS:` notices, exit 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260802000003_question_queue.sql supabase/tests/question_queue_test.sql
git commit -m "feat(daily): add get_current_question queue RPC"
```

---

### Task 3: Repository — `currentQuestion()`

**Files:**
- Modify: `lib/features/daily/data/question_repository.dart`
- Test: `test/features/daily/question_repository_test.dart` (new, integration)

**Interfaces:**
- Consumes: `get_current_question()` (Task 2), `QuestionOfDay` (existing, `lib/shared/models/daily_content.dart`).
- Produces: `QuestionRepository.currentQuestion() -> Future<QuestionOfDay?>` — null when the queue is exhausted.

- [ ] **Step 1: Write the failing integration test**

Create `test/features/daily/question_repository_test.dart`, using the same real-local-Supabase harness as `test/features/chat/chat_repository_test.dart` (copy its `_anonClient`, `_serviceRoleKey`, and `_pairCouple` helpers — Mocktail cannot mock the Supabase builder chain):

```dart
@Tags(['integration'])
library;

// ... same imports + _url/_anon/_serviceRoleKey/_anonClient/_pairCouple
// helpers as test/features/chat/chat_repository_test.dart ...

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(_url, _serviceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
  });

  test('currentQuestion returns the same question for both partners, and '
      'advances only once both have answered', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = QuestionRepository(clientA);
    final repoB = QuestionRepository(clientB);

    final qA = await repoA.currentQuestion();
    final qB = await repoB.currentQuestion();
    expect(qA, isNotNull);
    expect(qA!.id, qB!.id, reason: 'both partners must see the same question');

    final coupleId = await clientA.rpc('current_couple') as String;

    await repoA.submit(
        coupleId: coupleId, userId: pairing.userA, questionId: qA.id, answer: 'a');
    expect((await repoA.currentQuestion())!.id, qA.id,
        reason: 'one answer must not advance the queue');

    await repoB.submit(
        coupleId: coupleId, userId: pairing.userB, questionId: qA.id, answer: 'b');
    expect((await repoA.currentQuestion())!.id, isNot(qA.id),
        reason: 'the queue must advance once both partners answered');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test --tags integration test/features/daily/question_repository_test.dart`
Expected: FAIL — `currentQuestion` is not defined.

- [ ] **Step 3: Implement**

Add to `QuestionRepository` in `lib/features/daily/data/question_repository.dart` (add `import '../../../shared/models/daily_content.dart';` at the top):

```dart
  /// The couple's current queue question — the first approved question they
  /// have not both answered. Null when they've answered every approved
  /// question (the generator in supabase/functions/generate-questions is
  /// what normally keeps that from happening).
  Future<QuestionOfDay?> currentQuestion() async {
    final rows = await _client.rpc('get_current_question');
    final list = (rows is List) ? rows : [rows];
    if (list.isEmpty || list.first == null) return null;
    return QuestionOfDay.fromRow(Map<String, dynamic>.from(list.first as Map));
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test --tags integration test/features/daily/question_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/daily/data/question_repository.dart test/features/daily/question_repository_test.dart
git commit -m "feat(daily): add QuestionRepository.currentQuestion"
```

---

### Task 4: Providers — `currentQuestionProvider`

**Files:**
- Modify: `lib/features/daily/domain/question_providers.dart`

**Interfaces:**
- Produces: `currentQuestionProvider` (`FutureProvider<QuestionOfDay?>`). `questionAnswersProvider` and `questionNotificationPumpProvider` both repoint from `dailyContentProvider` to it.

- [ ] **Step 1: Add the provider and repoint the two consumers**

In `lib/features/daily/domain/question_providers.dart`:

Add `import '../../../shared/models/daily_content.dart';` and **remove** the now-unused `import 'daily_content_providers.dart';` (verify nothing else in the file uses it before removing).

Add after `questionRepositoryProvider`:

```dart
/// The couple's current queue question. Null when the queue is exhausted.
///
/// Deliberately NOT derived from `dailyContentProvider`: the question is a
/// joint activity that advances when both partners answer, not when the
/// calendar rolls over. Verse and hadith stay on dailyContentProvider.
///
/// Narrowed to the scalar couple id so a token refresh or a realtime
/// reconnect (which produces a new Couple object -- Couple has no
/// operator==) doesn't refetch and flicker the screen.
final currentQuestionProvider = FutureProvider<QuestionOfDay?>((ref) async {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return null;
  return ref.read(questionRepositoryProvider).currentQuestion();
});
```

Change `questionAnswersProvider` to read from it:

```dart
final questionAnswersProvider =
    StreamProvider<List<QuestionAnswer>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  final questionId =
      ref.watch(currentQuestionProvider.select((q) => q.asData?.value?.id));
  if (coupleId == null || questionId == null) return const Stream.empty();
  return ref.read(questionRepositoryProvider).watchAnswers(
        coupleId: coupleId,
        questionId: questionId,
      );
});
```

In `questionNotificationPumpProvider`, replace the `questionId` line:

```dart
  final questionId =
      ref.watch(currentQuestionProvider.select((q) => q.asData?.value?.id));
```

(everything else in that provider stays as-is, including the `.select` narrowing on `selfId`/`coupleId` and the `ref.onDispose(sub.cancel)`).

- [ ] **Step 2: Verify it compiles and nothing regressed**

Run: `flutter analyze lib/features/daily/`
Expected: `No issues found!`

Run: `flutter test --exclude-tags integration`
Expected: all pass (baseline: 239 passed, 1 skipped).

- [ ] **Step 3: Commit**

```bash
git add lib/features/daily/domain/question_providers.dart
git commit -m "feat(daily): add currentQuestionProvider, repoint answers + pump at the queue"
```

---

### Task 5: Question screen — reveal, lock, next, empty state

**Files:**
- Modify: `lib/features/daily/presentation/question_screen.dart`
- Modify: `lib/features/daily/presentation/question_card.dart`
- Test: `test/features/daily/question_screen_test.dart` (new)

**Interfaces:**
- Consumes: `currentQuestionProvider`, `questionAnswersProvider` (Task 4).

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/daily/question_screen_test.dart` with three tests, overriding `currentQuestionProvider` and `questionAnswersProvider` (follow the override style in `test/features/chat/chat_screen_test.dart`):

1. **Neither answered** — the composer (`TextField` + send button) is visible, and the spouse block shows the pending state.
2. **Only partner answered** — the composer is still visible; the spouse's answer text is **not** rendered (hidden), and the "has answered" hint is.
3. **Both answered** — both answer texts render, **no** `TextField` is present (edit is locked), and a "Next question" control is.

Assert on the concrete widgets/strings the implementation uses — read the current `question_screen.dart` first and match its existing `_AnswerBlock` API rather than inventing one.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/daily/question_screen_test.dart`
Expected: FAIL (screen still reads `dailyContentProvider`; no "Next question" control exists).

- [ ] **Step 3: Implement**

In `lib/features/daily/presentation/question_screen.dart`:

- Read the question from `ref.watch(currentQuestionProvider)` instead of `dailyContentProvider`.
- Compute `final bothAnswered = myAnswer != null && spouseAnswer != null;`
- Wrap the existing composer block in `if (myAnswer == null)` (it already is) — no change needed, but **verify** that once `myAnswer != null` no edit affordance remains anywhere on the screen.
- When `bothAnswered`, render a "Next question" `LovButton` below the two answers whose `onPressed` calls `ref.invalidate(currentQuestionProvider)`.
- When `currentQuestionProvider` resolves to `null`, render an "all caught up" empty state instead of the question card.

⚠️ **The next question must load only on that explicit tap** — never automatically when the second answer arrives, or the user never gets to read their partner's answer.

Also in `lib/features/daily/presentation/question_card.dart` (the home-screen card):

- Line 19 reads `ref.watch(dailyContentProvider).asData?.value` and takes `content?.question`, but line 23 already reads `questionAnswersProvider` — which Task 4 repointed at the queue. **These are now two different questions**, so the card's `myAnswered`/`spouseAnswered`/`bothAnswered` badges are computed from answers to a question the card isn't showing. Repoint the card's question to `ref.watch(currentQuestionProvider).asData?.value` so both halves describe the same question.
- The existing `if (q == null) return const SizedBox.shrink();` already covers queue exhaustion for the card — no empty state needed here, the card just disappears. Keep that.
- Remove the `daily_content_providers.dart` import if nothing else in the file uses it.

This file was missing from the original plan's file list; it was caught after Task 4 by tracing every remaining `dailyContentProvider` consumer.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/daily/question_screen_test.dart`
Expected: PASS (3 tests).

If any widget test hangs >30s, stop and report — this project's sandbox has a known `Image.file` hang (see `test/features/chat/photo_viewer_screen_test.dart`), though this screen shouldn't touch it.

- [ ] **Step 5: Commit**

```bash
git add lib/features/daily/presentation/question_screen.dart lib/features/daily/presentation/question_card.dart test/features/daily/question_screen_test.dart
git commit -m "feat(daily): question screen reads the queue, locks after reveal, advances on tap"
```

---

### Task 6: Edge function — pure logic

**Files:**
- Create: `supabase/functions/generate-questions/logic.ts`
- Create: `supabase/functions/generate-questions/logic.test.ts`

**Interfaces:**
- Produces: `SYSTEM_PROMPT`, `QUESTION_SCHEMA`, `parseGenerated(raw: unknown): GeneratedQuestion[]`, `type GeneratedQuestion = { question: string; category: string }`.

Pure/testable logic lives here so `logic.test.ts` can run under `deno test` without importing `index.ts` (whose top-level `Deno.serve` needs `--allow-net`) — the same split `push-dispatch` uses.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/generate-questions/logic.test.ts`:

```ts
import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseGenerated, QUESTION_SCHEMA, SYSTEM_PROMPT } from "./logic.ts";

Deno.test("parseGenerated accepts a well-formed batch", () => {
  const out = parseGenerated({
    questions: [
      { question: "What made you smile today?", category: "playful" },
      { question: "Which sunnah do you want to build together?", category: "deen" },
    ],
  });
  assertEquals(out.length, 2);
  assertEquals(out[0].category, "playful");
});

Deno.test("parseGenerated rejects an unknown category", () => {
  assertThrows(() =>
    parseGenerated({ questions: [{ question: "x", category: "spicy" }] })
  );
});

Deno.test("parseGenerated rejects an empty or blank question", () => {
  assertThrows(() => parseGenerated({ questions: [{ question: "   ", category: "deen" }] }));
});

Deno.test("parseGenerated rejects a non-array payload", () => {
  assertThrows(() => parseGenerated({ questions: "nope" }));
});

Deno.test("schema and prompt are wired for the four app categories", () => {
  const cats = QUESTION_SCHEMA.properties.questions.items.properties.category.enum;
  assertEquals(cats.sort(), ["deen", "future", "playful", "reflective"]);
  // The prompt must carry the app's frame, not generic couple-quiz copy.
  assertEquals(SYSTEM_PROMPT.includes("Muslim"), true);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `deno test supabase/functions/generate-questions/logic.test.ts`
Expected: FAIL — `logic.ts` does not exist.

- [ ] **Step 3: Implement**

Create `supabase/functions/generate-questions/logic.ts`:

```ts
// supabase/functions/generate-questions/logic.ts
//
// Pure, testable pieces of the question generator: the system prompt, the
// structured-output JSON schema, and validation of what came back. No
// network and no Deno.serve here so logic.test.ts can import it under a
// plain `deno test` -- same split as push-dispatch/logic.ts.

export const CATEGORIES = ["playful", "reflective", "future", "deen"] as const;
export type Category = (typeof CATEGORIES)[number];

export type GeneratedQuestion = { question: string; category: Category };

export const SYSTEM_PROMPT = `
You write the "question of the day" for Lovinity, an app used by married
Muslim couples to stay close.

Write questions that:
- a husband and wife would each answer in two or three sentences, then enjoy
  reading each other's answer
- sit naturally inside an Islamic marriage: warm, affectionate, and modest
- span everyday life, memories, hopes, gratitude, and faith practised together
- assume the couple is already married; never frame anything as dating

Avoid: anything explicit; anything that presumes children, wealth, or living
in the same country; therapy-speak; questions with a single factual answer;
questions that could start a fight.

Assign each question one category:
- playful     — light, fun, easy to answer
- reflective  — about feelings, memories, or the relationship so far
- future      — hopes, plans, what you're building together
- deen        — faith practised together: worship, character, gratitude to Allah
`.trim();

// Structured-output schema. Note the Claude API's structured outputs do not
// support array length constraints (minItems/maxItems), so the batch size is
// requested in the user message and validated in parseGenerated instead.
export const QUESTION_SCHEMA = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          question: { type: "string" },
          category: { type: "string", enum: [...CATEGORIES] },
        },
        required: ["question", "category"],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false,
} as const;

/// Validates a parsed model response. Throws on anything malformed -- the
/// caller turns that into a non-2xx so a bad batch is never inserted.
export function parseGenerated(raw: unknown): GeneratedQuestion[] {
  const questions = (raw as { questions?: unknown })?.questions;
  if (!Array.isArray(questions)) {
    throw new Error("payload.questions is not an array");
  }
  return questions.map((q, i) => {
    const question = (q as { question?: unknown })?.question;
    const category = (q as { category?: unknown })?.category;
    if (typeof question !== "string" || question.trim().length === 0) {
      throw new Error(`questions[${i}].question is empty or not a string`);
    }
    if (typeof category !== "string" || !CATEGORIES.includes(category as Category)) {
      throw new Error(`questions[${i}].category is not one of ${CATEGORIES.join(", ")}`);
    }
    return { question: question.trim(), category: category as Category };
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `deno test supabase/functions/generate-questions/logic.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/generate-questions/logic.ts supabase/functions/generate-questions/logic.test.ts
git commit -m "feat(daily): add generate-questions prompt, schema, and validation"
```

---

### Task 7: Edge function — handler

**Files:**
- Create: `supabase/functions/generate-questions/index.ts`

**Interfaces:**
- Consumes: `logic.ts` (Task 6), `daily_questions.status` (Task 1).

- [ ] **Step 1: Implement**

Create `supabase/functions/generate-questions/index.ts`:

```ts
// supabase/functions/generate-questions/index.ts
//
// Edge Function: generate-questions
//
// Tops up the daily_questions pool when approved questions run low, using the
// Claude API with structured outputs. Everything it writes lands as
// status='pending' -- a human approves in the Supabase dashboard before any
// couple sees it (see the design spec). This function must never write
// status='approved'.
//
// Pure logic (prompt, schema, validation) lives in ./logic.ts so it can be
// unit tested without --allow-net; same split as push-dispatch.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.70.0";
import {
  parseGenerated,
  QUESTION_SCHEMA,
  SYSTEM_PROMPT,
} from "./logic.ts";

const THRESHOLD = 20; // top up when approved questions fall below this
const BATCH = 20;

Deno.serve(async () => {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    // Fail loudly: a silent no-op here would let the queue drain unnoticed.
    console.error("ANTHROPIC_API_KEY is not set");
    return new Response("ANTHROPIC_API_KEY is not set", { status: 500 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { count, error: countError } = await supabase
    .from("daily_questions")
    .select("id", { count: "exact", head: true })
    .eq("status", "approved");
  if (countError) {
    console.error("count failed", countError);
    return new Response(countError.message, { status: 500 });
  }

  if ((count ?? 0) >= THRESHOLD) {
    return Response.json({ generated: 0, approved_pool: count });
  }

  const client = new Anthropic({ apiKey });
  const response = await client.messages.create({
    model: "claude-opus-5",
    max_tokens: 8000,
    system: SYSTEM_PROMPT,
    output_config: { format: { type: "json_schema", schema: QUESTION_SCHEMA } },
    messages: [{
      role: "user",
      content:
        `Write ${BATCH} new questions. Vary the categories and don't repeat ` +
        `phrasings or themes within the batch.`,
    }],
  });

  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") {
    console.error("no text block in response", response.stop_reason);
    return new Response("model returned no text block", { status: 502 });
  }

  let rows;
  try {
    rows = parseGenerated(JSON.parse(text.text));
  } catch (e) {
    console.error("invalid generated payload", e);
    return new Response(`invalid generated payload: ${e}`, { status: 502 });
  }

  const { error: insertError } = await supabase.from("daily_questions").insert(
    rows.map((r) => ({
      question: r.question,
      category: r.category,
      language: "en",
      status: "pending", // never 'approved' -- a human reviews first
      source: "generated",
    })),
  );
  if (insertError) {
    console.error("insert failed", insertError);
    return new Response(insertError.message, { status: 500 });
  }

  return Response.json({ generated: rows.length, approved_pool: count });
});
```

- [ ] **Step 2: Verify it type-checks**

Run: `deno check supabase/functions/generate-questions/index.ts`
Expected: no errors. (Network access is needed to resolve the `esm.sh` imports the first time; if the sandbox blocks it, report that rather than editing the imports to something unpinned.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/generate-questions/index.ts
git commit -m "feat(daily): add generate-questions edge function"
```

---

### Task 8: Final verification

**Files:** none (verification only).

- [ ] **Step 1:** `flutter analyze` → 10 pre-existing info lints, 0 errors.
- [ ] **Step 2:** `flutter test --exclude-tags integration` → all pass (baseline 239 + the new widget tests).
- [ ] **Step 3:** `flutter test --tags integration` → all pass (baseline 15 + the new repository test).
- [ ] **Step 4:** `deno test supabase/functions/generate-questions/logic.test.ts` → 5 pass.
- [ ] **Step 5:** SQL suite:
  ```bash
  PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -f supabase/tests/question_queue_test.sql
  ```
- [ ] **Step 6:** Report any deployment steps left for the human — specifically: setting the `ANTHROPIC_API_KEY` edge-function secret, deploying `generate-questions`, pushing the migration to cloud, and scheduling the function. Do **not** deploy or push to the user's cloud project as part of this plan.
