# Lessons, Love Map & Date Ideas — Implementation Plan

Covers features #1, #4 and #5 from
`docs/superpowers/plans/2026-08-07-couple-features-roadmap.md`. Build in the
order given: each depends on schema the previous one does not touch, but the
shared "hidden until both have answered" rule is established in #1 and reused
in #4.

**Goal:** short co-studied lessons with a two-question check-in; a Gottman-style
"how well do you know your spouse?" round; and a halal date-idea library
including virtual dates for long-distance couples.

## The rule that shapes all three

Two of these features hinge on *not* being able to see your spouse's answer
before you commit your own. If you can read their answer first, a check-in
becomes copying and a guessing game becomes cheating — the feature still
renders, it just stops meaning anything.

**That must be enforced in RLS, not in the widget.** A client-side hide is not
a hide: the row is on the device, and anyone calling the REST endpoint sees it.

Note the existing precedent is the weaker one — `question_answers` carries only
the blanket `is_couple_member(couple_id)` policy, so the daily question's reveal
is client-side today. That is pre-existing and out of scope here, but these
features must not copy it. Flagged for a follow-up.

---

## Feature #1 — Co-studied lessons

**Tables:** `learning_lessons(title, category, language, body, arabic_body,
reference)` and `learning_progress(user_id, lesson_id, answers jsonb,
completed_at)`, unique on `(couple_id, user_id, lesson_id)`.

**Schema gap:** `learning_lessons` has nowhere to put the check-in questions, so
the feature has nothing to render.

### Migration `20260808000001_lessons_checkin.sql`

- Add `questions jsonb not null default '[]'::jsonb`, constrained to an array of
  0 or exactly 2 entries. Two is the product promise; allowing 3 or 1 silently
  would let content drift out of shape.
- Replace `learning_progress`'s blanket policy with a reveal-gated `select`:
  own rows always; the spouse's row only once **you** have completed that
  lesson. Insert/update stay self-scoped so nobody can write an answer as their
  partner.
- Index `(couple_id, lesson_id)`.

### Content — hand-authored, cited

Categories: `fiqh_marriage`, `seerah`, `names_of_allah`. Every row carries a
`reference`. **No AI generation for this feature** — these rows make religious
claims, and an invented ḥadīth or a mis-stated ruling is a real harm, not a
cosmetic bug.

Scope discipline for fiqh: stick to points of broad agreement (the mutual rights
of spouses, kindness in companionship, mahr as the wife's property), state that
madhhabs differ on detail, and say plainly that the app is not giving a fatwa.
Anything contested belongs in front of a scholar, not in a seed migration.

### Files

`lib/features/learning/data/lesson_repository.dart`,
`domain/learning_providers.dart`,
`presentation/{lesson_list_screen,lesson_screen,learning_card}.dart`,
route `/home/learn`.

---

## Feature #4 — "How well do you know your spouse?"

**Tables:** `love_map_quizzes(question, category)` and
`love_map_answers(quiz_id, guesser_id, guess, is_correct, played_at)`.

**This feature cannot work as modelled.** `love_map_answers` stores a *guess* and
an `is_correct` flag, but nothing stores the spouse's actual answer — so there is
nothing to compare against and no way to compute `is_correct`. It also lacks a
`subject_id`, so a guess doesn't record *who* it was about.

### Migration `20260808000002_love_map.sql`

- New `love_map_truths(couple_id, quiz_id, subject_id, answer)`, unique on
  `(couple_id, quiz_id, subject_id)` — what the subject says about themselves.
- Add `subject_id` to `love_map_answers` so a guess links to a truth.
- Reveal-gated RLS on `love_map_truths`: the subject always sees their own; the
  partner only after submitting a guess for that `(quiz_id, subject_id)`.
- Add `approved boolean not null default false` to `love_map_quizzes` and
  restrict the world-readable policy to approved rows, mirroring
  `20260803000001_daily_content_approved_only.sql`.

### Round flow

Subject answers about themselves → partner guesses → both revealed together →
partner self-grades (`is_correct`). Self-grading rather than string equality:
"what's her favourite surah?" has many correct spellings and a string compare
would call a right answer wrong.

Categories carry the deen/dreams twist: `deen`, `dreams`, `history`,
`preferences`.

### Files

`lib/features/lovemap/**`, route `/home/lovemap`.

---

## Feature #5 — Halal date ideas

**No table exists.**

### Migration `20260808000003_date_ideas.sql`

- `date_ideas(title, description, setting check in ('home','out','virtual'),
  category, effort, cost_band, approved boolean default false)` — world-readable
  when approved.
- `date_idea_saves(couple_id, idea_id, saved_by, planned_for, completed_at)` —
  couple-scoped, the usual `is_couple_member` policy.

Virtual dates reuse the existing `watch_together_sessions` table (synchronised
media position) rather than inventing a second mechanism for long-distance
couples.

### Files

`lib/features/dates/**`, route `/home/dates`.

---

## Verification

- Reveal gates proven with integration tests using the *partner's own JWT*: the
  truth/answer must be absent before committing, present after. A test that only
  checks the widget proves nothing.
- Approval gate proven: an unapproved quiz or idea is not returned to a normal
  client.
- `supabase db reset` applies the whole chain; full suite green.
