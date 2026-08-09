# Seven Couple Features — Implementation Roadmap

> **For agentic workers:** Each feature below is its own delivery unit (schema → repository → providers → UI → tests). Build them in the order given; do not start a later feature before the previous one is green. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship seven features — co-studied lessons, an OS home-screen widget, a Hijri/Gregorian shared calendar, a Gottman-style "how well do you know your spouse" game, halal date ideas, sealed future letters, and weekly meal/grocery/recipe planning.

**Key finding:** `20260712000002_full_schema.sql` already creates tables for six of the seven. There is no application code for any of them — `lib/features/` contains none of these directories. So the work is overwhelmingly Dart + targeted schema corrections, not greenfield modelling.

## Status (updated 2026-08-08)

| Item | State |
|---|---|
| F0 realtime publication | **Done** — 7 tables published, verified against `pg_publication_tables` |
| #3 Shared calendar | **Done** — 41 tests (23 Hijri, 14 resolution, 4 integration) |
| #7 Weekly plan / groceries / recipes | **Done** — 22 tests, incl. the concurrent-tick regression |
| #6 Future letters | **Done** — 18 tests, incl. server-side seal verified via the recipient's own JWT |
| #1 Co-studied lessons | Not started — needs `questions` column + hand-authored content |
| #4 Love map | Not started — needs `love_map_truths` (feature cannot work without it) |
| #5 Date ideas | Not started — needs new schema |
| #2 OS widget | Not started — native track |

Suite: **390 passing**, analyze clean, all migrations apply from a clean `supabase db reset`.

Two bugs found and fixed while building, both worth remembering:

* `nextGregorianOccurrence` returned the start date before validating `FREQ`, so an
  unsupported recurrence rule behaved like a valid one.
* Letter ciphertext was written as bare hex, copying `ChatRepository`'s convention.
  That convention only works because `send_message` calls `decode(..., 'hex')`
  explicitly; a direct PostgREST insert needs the `\x` prefix or Postgres parses the
  string as legacy *escape* format and stores the ASCII of the hex digits. The symptom
  was a GCM authentication failure — i.e. it looked like tampering, not encoding.

## Decisions taken

| Decision | Choice |
|---|---|
| Feature #2 scope | Real OS widget (iOS WidgetKit + Android Glance) — a native track |
| Content sourcing | Hybrid by risk: fiqh/seerah/names hand-authored with citations; love-map questions and date ideas AI-generated behind the existing approval gate |
| Future-letter seal | Server-side RLS gate **and** E2E encryption |
| Build order | Content-independent first: #3 → #7 → #6, then #1 → #4 → #5, with #2 as a parallel native track |

## Global constraints

- **Per-person day anchoring is now law.** `lib/core/time/local_day.dart` exists and the prayer log resolves each spouse's day against their own zone. Any new feature that renders a date for both spouses must use it. Never resolve two people against one date key.
- Every new couple-scoped table is already covered by the bulk `is_couple_member(couple_id)` RLS loop at `20260712000002_full_schema.sql:645`. Verify with `pg_policies` before assuming; do not hand-write a duplicate policy.
- **No target table is in the `supabase_realtime` publication.** Every feature needs its tables added — see Foundation F0. Precedent: `20260716000001_realtime_missing_tables.sql`.
- Follow the established feature shape exactly: `data/<x>_repository.dart` (model with `fromRow` + repository), `domain/<x>_providers.dart` (repository provider, `StreamProvider`, derived providers, `<x>NotificationPumpProvider`), `presentation/<x>_card.dart` + `<x>_screen.dart`. Reference: `lib/features/gratitude/`.
- Notification pumps are watched **once** from `HomeScreen` and must narrow to scalar ids (`.select((c) => c.asData?.value?.id)`) so token refreshes and realtime reconnects don't re-baseline the detector.
- Content that makes a religious claim (a ruling, a seerah fact, a name of Allah and its meaning) must carry a `reference` and be hand-authored. AI may generate prompts and suggestions only.

---

## Foundation F0: realtime publication for all new tables

**Files:** Create `supabase/migrations/20260807000001_realtime_feature_tables.sql`

None of `calendar_events`, `meal_plans`, `recipes`, `grocery_lists`, `future_letters`, `learning_progress`, `love_map_answers` are published for realtime, so `.stream()` would silently never emit an update — the failure looks like "the app is just slow", which is why it must be done up front rather than debugged per feature.

- [ ] Add each table to `supabase_realtime`, guarding with the same `if not exists` loop pattern used in `20260716000001`.
- [ ] Set `replica identity full` where a delete needs to reach the client (grocery items, calendar events).
- [ ] Verify: `select tablename from pg_publication_tables where pubname='supabase_realtime'` lists all of them.

---

## Feature #3 — Shared calendar, Hijri + Gregorian (FIRST)

**Table:** `calendar_events` exists — `title`, `description`, `starts_at timestamptz`, `ends_at`, `all_day bool`, `recurrence text` (iCal RRULE), `hijri_anchor text`, `kind` (`event|anniversary|birthday|islamic`), `reminder_offsets integer[]`.

**The trap:** `starts_at` is `timestamptz`, but an anniversary is a *calendar date*, not an instant. Stored as an instant and rendered in each spouse's zone, "14 March" displays as 13 March for one of them — the exact falsehood class just fixed in the prayer log. All-day events must be written at UTC midnight and rendered from their **date fields without zone conversion**; only timed events convert to the viewer's zone.

**Hijri:** the `hijri` package is already a dependency and `toHijri()` already exists in `lib/core/time/prayer_engine.dart`. `hijri_anchor` holds a Hijri `YYYY-MM-DD` so an Islamic-calendar anniversary recurs on its Hijri date and drifts against the Gregorian one, which is the whole point of the column.

**Files**
| File | Change |
|---|---|
| `supabase/migrations/20260807000002_calendar_indexes.sql` | New — index `(couple_id, starts_at)`; `replica identity full` |
| `lib/features/calendar/data/calendar_repository.dart` | New — `CalendarEvent` model, `watchRange`, `create`, `update`, `delete` |
| `lib/core/time/hijri_dates.dart` | New — Hijri conversion + next-occurrence for Hijri-anchored and RRULE events |
| `lib/features/calendar/domain/calendar_providers.dart` | New — providers + `calendarNotificationPumpProvider` |
| `lib/features/calendar/presentation/calendar_screen.dart` | New — month grid, dual date labels |
| `lib/features/calendar/presentation/event_editor_sheet.dart` | New — create/edit, all-day toggle, Hijri anchor toggle |
| `lib/features/calendar/presentation/calendar_card.dart` | New — "next up" home card |
| `lib/core/router/app_router.dart` | Add `/home/calendar` |
| `lib/features/home/presentation/home_screen.dart` | Mount card + pump |

- [ ] `hijri_dates.dart` pure module first, with tests: Gregorian↔Hijri round-trip, Hijri-anchored next occurrence across a Gregorian year boundary, RRULE yearly recurrence, all-day date stability across two zones.
- [ ] Repository + providers, then screen.
- [ ] Reminders use `flutter_local_notifications` (already a dependency) scheduled from `reminder_offsets`; server push for reminders is **out of scope** for this feature.

**Tests:** `test/core/time/hijri_dates_test.dart`, `test/features/calendar/calendar_repository_test.dart` (integration, tagged), all-day cross-timezone rendering test.

---

## Feature #7 — Weekly plan, live shopping list, saved recipes (SECOND)

**Tables:** `meal_plans(week_starting date, slots jsonb)`, `recipes(title, source_url, ingredients jsonb, steps jsonb, halal_notes)`, `grocery_lists(title, items jsonb)`.

**The trap:** `grocery_lists.items` is a **jsonb array mutated by two people at once**. "Live shopping list" means both spouses tick items in the same minute; a read-modify-write of the whole array means the second writer silently destroys the first writer's tick. That is a lost update, and it is guaranteed to happen in a shopping aisle.

**Fix:** normalise to a `grocery_items` row-per-item table so realtime and RLS operate per item and two ticks can never collide. Keep `grocery_lists` as the list header.

**Files**
| File | Change |
|---|---|
| `supabase/migrations/20260807000003_grocery_items.sql` | New — `grocery_items` table, RLS, realtime, backfill from `items` jsonb |
| `lib/features/planning/data/meal_plan_repository.dart` | New |
| `lib/features/planning/data/grocery_repository.dart` | New — per-item add/toggle/delete |
| `lib/features/planning/data/recipe_repository.dart` | New |
| `lib/features/planning/domain/planning_providers.dart` | New |
| `lib/features/planning/presentation/week_plan_screen.dart` | New — 7×slots grid |
| `lib/features/planning/presentation/grocery_list_screen.dart` | New — live ticking |
| `lib/features/planning/presentation/recipe_*.dart` | New — list + detail + save-from-feed |
| `lib/core/router/app_router.dart` | Add `/home/plan`, `/home/groceries`, `/home/recipes` |

- [ ] Week anchoring uses `local_day.dart`; `week_starting` is a date, resolved in the user's own zone.
- [ ] "Save recipes from the feed": `feed_items` → `recipes` insert; keep `source_url`.

**Tests:** concurrent-tick test proving two clients toggling different items both persist (the lost-update regression), meal-plan week boundary test.

---

## Feature #6 — Future letters, sealed until a date (THIRD)

**Table:** `future_letters(author_id, recipient_id, body_ciphertext bytea, unlock_at, unlocked_at)`.

**Two-layer seal, as decided:**

1. **Server:** replace the blanket `ALL is_couple_member(couple_id)` policy with a `SELECT` policy that returns the row only to the author, or to anyone once `unlock_at <= now()`. The recipient cannot fetch the ciphertext early even with a modified client.
2. **Client:** the body stays E2E-encrypted. The Signal double-ratchet used by chat is **wrong here** — it rotates keys continuously and a letter may sit for years. Use the `AES-256-GCM` helper already in `lib/core/crypto/attachment_crypto.dart` with a long-lived couple letter-key held in `flutter_secure_storage`, established once and shared via the existing Signal session.

**Files**
| File | Change |
|---|---|
| `supabase/migrations/20260807000004_future_letters_seal.sql` | New — drop blanket policy, add author/unlock-gated SELECT + INSERT/UPDATE policies |
| `supabase/tests/future_letters_seal_test.sql` | New — recipient SELECT returns 0 rows before `unlock_at`, 1 row after |
| `lib/features/letters/data/letter_repository.dart` | New |
| `lib/core/crypto/letter_key.dart` | New — long-lived couple letter key, established + stored |
| `lib/features/letters/domain/letter_providers.dart` | New — includes an unlock pump that notifies on the day |
| `lib/features/letters/presentation/*.dart` | New — compose, sealed list, unlock reveal |

**Tests:** RLS seal test (must fail if the policy is reverted — verify by reverting), crypto round-trip, unlock-day notification.

---

## Feature #1 — Co-studied lessons with a 2-question check-in (FOURTH)

**Tables:** `learning_lessons(title, category, language, body, arabic_body, reference)`, `learning_progress(user_id, lesson_id, answers jsonb, completed_at)` — unique on `(couple_id, user_id, lesson_id)`.

**Schema gap:** `learning_lessons` has **no questions column**, so the "2-question check-in" has nothing to render. Add `questions jsonb` (exactly two prompts) with a check constraint on length.

**Reveal:** mirror the daily-question flow — each spouse answers independently, neither sees the other's answer until both have submitted. Enforce server-side; a client-side hide is not a hide.

**Content (hand-authored, cited):** fiqh of marriage, seerah, names of Allah. Ships as seed migrations with a `reference` on every row. No AI generation for this feature.

**Files:** `20260807000005_learning_questions.sql`, `20260807000006_seed_lessons_*.sql`, `lib/features/learning/**`, route `/home/learn`.

---

## Feature #4 — "How well do you know your spouse?" (FIFTH)

**Tables:** `love_map_quizzes(question, category)`, `love_map_answers(quiz_id, guesser_id, guess, is_correct, played_at)`.

**Schema gap — this feature cannot work as modelled.** `love_map_answers` stores a *guess* and an `is_correct` flag, but **nothing stores the spouse's actual answer**, so there is nothing to compare a guess against and no way to compute `is_correct`. Add a `love_map_truths(couple_id, quiz_id, subject_id, answer)` table: the subject answers about themselves, the partner guesses, and grading compares the two.

**Round flow:** subject answers privately → partner guesses → reveal both → partner self-grades or exact-matches → score. "Twist toward deen and future dreams" is carried by `category` (`deen`, `dreams`, `history`, `preferences`).

**Content:** AI-generated behind an approval gate — add `approved boolean not null default false` to `love_map_quizzes` and serve only approved rows, exactly as `20260803000001_daily_content_approved_only.sql` does.

**Files:** `20260807000007_love_map_truths.sql`, `20260807000008_love_map_approved.sql`, `lib/features/lovemap/**`, route `/home/lovemap`.

---

## Feature #5 — Halal date ideas, incl. virtual dates (SIXTH)

**No table exists.** Create `date_ideas(id, title, description, setting text check (setting in ('home','out','virtual')), effort, cost_band, category, approved boolean default false)` plus `date_idea_saves(couple_id, idea_id, saved_by, planned_for, completed_at)`.

Long-distance/virtual dates reuse the existing `watch_together_sessions` table (synchronised media position) rather than inventing a second mechanism.

**Content:** AI-generated behind the approval gate.

**Files:** `20260807000009_date_ideas.sql`, `lib/features/dates/**`, route `/home/dates`.

---

## Feature #2 — OS home-screen widget (PARALLEL NATIVE TRACK)

Shows next prayer, both spouses' check-in status, today's verse.

**Approach:** use the `home_widget` package for the Dart↔native bridge rather than hand-rolling an App Group + MethodChannel on each platform.

- **iOS:** SwiftUI WidgetKit extension in `ios/LovinityWidget/`, App Group container shared with the host app, `TimelineProvider` refreshing at prayer boundaries.
- **Android:** Glance `AppWidget` in `android/app/src/main/kotlin/.../widget/`, updated via `home_widget`'s background callback.
- **Dart:** a `widget_snapshot.dart` that serialises `{nextPrayer, ownCount, spouseCount, verseText, ownTz, spouseTz}` and writes it whenever those providers change.

**Why the widget can stay accurate offline:** prayer times are computed locally from lat/long/timezone (`prayer_engine.dart`), so the widget recomputes the next prayer itself and only needs the network for check-in status and the verse.

**Constraint:** both spouses' check-in counts must be written using the per-person day anchoring from `local_day.dart` — a widget is exactly where a stale or mis-anchored "0 of 5" would be most misleading.

**Files:** `pubspec.yaml` (+`home_widget`), `lib/features/widget/widget_snapshot.dart`, `ios/LovinityWidget/**`, `android/**/widget/**`, plus Xcode project and Android manifest changes.

---

## Sequencing summary

```
F0 realtime publication        ← do first, unblocks everything
 ├─ #3 calendar                ← start here
 ├─ #7 planning/groceries/recipes
 ├─ #6 future letters
 ├─ #1 lessons        (hand-authored content)
 ├─ #4 love map       (schema fix + AI content + approval)
 └─ #5 date ideas     (AI content + approval)

#2 OS widget — parallel native track, depends on nothing above
```
