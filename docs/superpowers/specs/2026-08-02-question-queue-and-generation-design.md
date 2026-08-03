# Question Queue + AI Question Generation — design

**Date:** 2026-08-02
**Status:** Design approved
**Builds on:** daily content (`get_daily_content`), question answers, notification inbox

## Summary

Two changes that together remove the daily question's dependence on calendar
dates:

1. **Queue + reveal (Option A).** The question of the day stops being "the
   question assigned to today's date" and becomes "the couple's current
   question." It stays current until **both** partners answer; then their
   answers reveal to each other and the next question unlocks.
2. **AI-generated question supply.** A scheduled edge function tops up
   `daily_questions` using the Claude API when the approved pool runs low.
   Generated questions land in a **review queue** and only enter circulation
   once approved.

## Why

The daily question is a *joint* activity — both partners must see the same
question and each other's answers. Tying it to a calendar date created a class
of bug that was already fixed once at the client layer (each device sending its
own local date; see `2026-08-01` partner-sync work) but remains structurally
possible: a couple in different timezones, or either partner crossing midnight,
can disagree about which day it is. A queue has no date to disagree about, so
the bug class disappears rather than being managed.

Separately, the pool is 14 hardcoded questions. A couple answering one per
sitting exhausts it in two weeks.

## Prior art

`question_answers` is already keyed `(couple_id, question_id, author_id)` — by
**question**, not by date. The queue model needs no migration for existing
answers. The date coupling lives entirely in `daily_content`, which maps
`(couple_id, date) → question_id`.

`question_screen.dart` already implements the reveal: `_AnswerBlock` takes
`hidden` and `pending` flags and blurs the spouse's answer until you've
answered. This spec keeps that widget and changes what feeds it.

## Part 1 — Queue + reveal

### Question selection

A new `get_current_question()` RPC replaces the question half of
`get_daily_content` for the question feature. It returns the first question, in
a per-couple deterministic order, that the couple has **not both answered**:

```
first approved question q, ordered by (deterministic per-couple seq),
where (count of question_answers for this couple + q) < 2
```

Ordering is deterministic per couple — derived from `hashtext(couple_id ||
question_id)` — so both partners resolve the same question with no stored
cursor, and different couples see a different sequence.

The verse and hadith stay date-based and keep using `get_daily_content`
unchanged. Only the question moves to the queue; a verse has no "both partners
answered" state to advance on, and being passive content it has no sync bug to
fix.

### Reveal semantics

- Before you answer: your partner's answer is **hidden** (existing blur), and
  the block reads "Naziha has answered" when they have — the anticipation
  signal, and what the current `pending` flag already distinguishes.
- Once both have answered: both answers show.
- **Answers are final once revealed.** No edit after the reveal — this keeps
  the reveal meaningful (nobody rewrites after seeing their partner's answer).
  The existing `question_answers` upsert stays, but the UI stops offering an
  edit path once both answers exist.

### Queue exhaustion

With Part 2 supplying questions this should not happen, but the RPC must still
return a defined result when every approved question has been answered by the
couple. It returns null, and the UI shows an "all caught up" state rather than
an error. This is the fallback, not the expected path.

## Part 2 — AI question generation

### Data model

`daily_questions` gains three columns:

- `status` text not null default `'pending'` — `'pending' | 'approved' | 'rejected'`
- `source` text not null default `'generated'` — `'seed' | 'generated'`
- `created_at` timestamptz not null default `now()`

The 14 existing rows are backfilled to `status = 'approved'`, `source =
'seed'`, preserving current behavior exactly. **Only `status = 'approved'`
questions enter the queue** — this is enforced in the RPC, not client-side.

### Generation

A new Supabase edge function `generate-questions`, sibling to the existing
`push-dispatch`:

1. Counts `daily_questions` where `status = 'approved'`.
2. If below a threshold (20), calls the Claude API for a batch of 20 new
   questions.
3. Inserts them with `status = 'pending'`.

Model: `claude-opus-5` via `@anthropic-ai/sdk`. Cost is roughly two cents per
batch, so the strongest model is used for tone quality rather than economizing
on a call that runs at most monthly. Uses **structured outputs**
(`output_config.format` with a JSON schema) so the response is guaranteed
parseable — no string-parsing of model output.

The system prompt carries the app's voice and values: questions for a married
Muslim couple, appropriate to an Islamic marriage frame, spanning the existing
`category` values (`playful`, `reflective`, `future`, `deen`), answerable in a
few sentences by both partners.

Scheduling: `pg_cron`, monthly. The function is also safe to invoke manually.

### Review queue

Generated questions are **not** visible to couples until approved. Approval is
done directly in the Supabase dashboard (flip `status` to `'approved'` or
`'rejected'`) — no admin UI is built in this pass. This is a deliberate scope
limit: the volume is a handful of rows per month, and building an admin surface
for it would be more work than the review itself.

RLS: `daily_questions` is currently world-readable (`for select using (true)`),
which is correct for approved questions. The new columns don't change that —
but the queue RPC filters to `status = 'approved'`, so pending questions are
never selected into a couple's queue even though the rows are readable.

## Non-goals

- No admin approval UI (dashboard is sufficient at this volume).
- No per-couple question customization or difficulty tuning.
- Verse and hadith stay date-based and untouched.
- No editing answers after reveal.
- No backfill or migration of existing `question_answers` (none needed —
  already question-keyed).

## Testing

- **RPC:** SQL tests — returns the same question for both partners of a couple;
  advances only when both have answered; skips `status != 'approved'`; returns
  null when exhausted; two different couples get different orderings.
- **Reveal:** widget tests for the three states (neither answered, one
  answered, both answered) and that the edit path disappears after reveal.
- **Edge function:** a test that the generated payload validates against the
  schema, and that generated rows land as `status = 'pending'` (never
  `'approved'`).
- **Regression:** the existing question notification pump must still fire when
  the partner answers, now keyed on the queue's current question rather than a
  date-derived one.

## Rollout notes

- The migration is additive (three nullable-with-default columns + a backfill
  of 14 rows) and safe on the live cloud database.
- `get_daily_content` is **not** modified — verse/hadith keep working
  unchanged. The question field it returns simply stops being read by the
  question feature.
- `ANTHROPIC_API_KEY` must be set as a Supabase edge-function secret before
  `generate-questions` is deployed; the function should fail loudly (not
  silently no-op) if it's missing.
