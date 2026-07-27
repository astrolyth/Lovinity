# Sakīnah — Roles, Cycle Tracking, Prayer Scoring & Care Dashboards

**Date:** 2026-07-15
**Status:** Design approved, pending spec review
**Depends on:** Phase 0 foundation (`2026-07-12-foundation-design.md`)

## Summary

This phase adds five interlocking modules to Sakīnah, built in dependency order:

1. **Roles & onboarding** — capture gender at registration, derive husband/wife role.
2. **Cycle tracker** — the wife logs her menstrual cycle; predictions from history.
3. **Cycle-aware prayer scoring** — a fair, gamified consistency competition that pauses correctly during the wife's cycle.
4. **Role-specific Cycle Care Dashboards** — care/wellbeing guidance tailored to husband vs wife, with sourced Islamic + scientific references.
5. **Settings tab** — an extensible settings foundation; first home of the cycle-privacy toggle.

The modules are dependent, not independent: role gates the cycle feature; the cycle gates the scoring pause and the care dashboards; privacy settings govern what the spouse sees. They are therefore designed as one spec with clean module boundaries and a fixed build order.

## Guiding constraints

These shape every decision below and are non-negotiable:

- **Care content is comfort/wellbeing, never medical treatment.** No diagnosis, no "treatment" language. A visible disclaimer accompanies health content: *"General guidance, not medical advice; consult a doctor for health concerns."*
- **Religious content must be authentic and sourced.** Every Islamic reference ships with its source (sūrah:āyah, or ḥadīth collection + number). No ḥadīth is fabricated or paraphrased from memory into seed data. All drafted religious content is stored behind a `pending_review` flag and surfaced with a *"verify with a qualified scholar"* note until verified.
- **Cycle data is sensitive and private by default.** The husband sees only a neutral "resting/paused" state unless the wife explicitly shares a cycle. RLS enforces this at the database level, not just the UI.
- **The app assists; it does not issue fiqh rulings.** Madhhab-aware suggestions (e.g. max menstruation duration) are gentle guidance, never enforced.

## Existing state (relevant)

- `users` — has `display_name`, `timezone`, `madhhab` (`shafi`/`hanafi`), `calc_method`, lat/long. **No gender/role.**
- `couples` — `member_a`/`member_b` linked by UUID order; no husband/wife notion.
- `prayer_logs` — `(couple_id, user_id, date, prayer, status)`, status `prayed`/`missed`/`skipped`. **No scoring.**
- `cycle_records` — `(user_id, couple_id, started_on, ended_on, visibility['private'|'shared'], note)`. Minimal placeholder from the Phase 4 schema.
- Content-library pattern already exists (`verses`, `hadiths`, `duas_library`): world-readable, admin-writable seed tables.
- `core/time/prayer_engine.dart` + timezone bootstrap already compute prayer times per user.

---

## Architectural decision: where the score is computed

**Chosen: derive in Postgres via an RPC (`get_couple_scoreboard`).** Score (%, streaks, cycle-exemptions) is computed on demand from `prayer_logs` + `cycle_records`. Rationale:

- Single source of truth — no stored-score drift, no divergence between the two partners' devices.
- The fairness math (excluding cycle-exempt prayers) lives in SQL right next to both source tables.
- Data volume for a two-person app is tiny; recompute cost is irrelevant.
- Matches the existing RLS/RPC pattern.

Rejected: client-side computation (duplicated logic across two clients, drift risk on exactly the math that must stay consistent); stored score table + triggers (overkill, real trigger complexity for two users).

---

## Module 1 — Roles & onboarding

### Data model

- Add `gender text check (gender in ('male','female'))` to `users`, nullable until onboarding completes.
- **Role is derived, never stored:** in a couple, the `male` member is the husband, the `female` member is the wife.

### Behaviour

- **Onboarding screen** after first sign-in collects: display name, gender, madhhab, location. Router guard: `gender IS NULL` → onboarding (added alongside existing auth + pairing guards).
- **Pairing validation:** `accept_pairing_invite` RPC rejects two same-gender users with `raise exception 'same_gender_pairing'`. The join/invite UI surfaces a clear message.
- **Gender lock:** editable during onboarding and while unpaired; **locked once paired** (changing it would invalidate the couple's role model).

### Code

- `UserProfile` model gains `gender`.
- `roleOf(userId)` helper (on `Couple` or a provider) returning `husband`/`wife`.
- `features/onboarding/` module (screen + controller), or extend `features/auth/`.

---

## Module 2 — Cycle tracker (`features/cycle`, wife only)

### Data model

- `cycle_records` is the source of truth. Predictions are derived, not stored.
- Tighten RLS (see Privacy & RLS section).

### Behaviour

- **Actions:** *Start* creates a record (`started_on = today`, `ended_on = null` ⇒ active); *End* sets `ended_on`.
- **Madhhab-aware max:** after the madhhab's typical maximum (Hanafi ~10 days, Shafi ~15), gently suggest ending — a warning, never enforced.
- **Predictions:** average cycle length (start-to-start) and period length from the last N records → next-period estimate + optional local-notification reminder. Hidden until ≥2 cycles logged.
- **Active cycle ⇒ exemption:** while today falls within an active record, the wife's prayer tiles are hidden/greyed and those slots are excluded from scoring.
- **Wife-only:** the cycle UI is gated by gender; the husband never sees the tracker.

### Providers

`activeCycleProvider`, `cycleHistoryProvider`, `cyclePredictionProvider`.

### Edge cases

- No history → predictions hidden.
- Wife who never logs → plain prayer tracking, no exemptions.
- Istihāḍah / irregular cycles → not enforced; the wife controls start/end; madhhab-aware guidance only.

---

## Module 3 — Cycle-aware prayer scoring (`features/scoring`)

### Definitions

- A prayer slot is **due** for a user on a date if its time has passed (per that user's timezone + `prayer_engine`) **and** the user is not cycle-exempt that day.
- **Completion %** = `prayed ÷ due`, computed all-time and over rolling 7-day / 30-day windows.
- **Streak** = consecutive days with all due prayers prayed. Cycle-exempt days are **frozen**: they neither break nor extend the streak; it resumes across the gap.

### Fairness model

Exempt prayers leave the wife's denominator entirely — never a penalty, and her % stays comparable to the husband's over months. His % and streak hold only if he keeps praying. This is the long-term-fair model (chosen over cumulative points, which would drift the husband permanently ahead).

### RPC

`get_couple_scoreboard(window)` → per member: `prayed`, `due`, `pct`, `current_streak`, `longest_streak`, `today_prayed`, `today_due`. Cycle exclusion via a `left join` to `cycle_records` in SQL.

### Retroactive logging

Logging/correction allowed for **today and yesterday** only (covers a late Isha logged next morning) — keeps score recompute predictable.

### Gamification tone — encouraging + gentle rivalry

- Home: side-by-side progress rings (his / hers), a this-week comparison line ("you're both at 95% — mā shāʾ Allāh"), a shared/combined streak, and supportive nudges ("help each other catch Fajr").
- Light milestone badges: 7 / 30 / 40-day streaks, on-time Fajr runs.
- During the wife's cycle her card reads **"Resting — scoring paused 🤍"** with a frozen-streak indicator.
- Framing avoids pure score-chasing to respect ikhlāṣ (sincerity in worship): accountability and mutual encouragement over leaderboard aggression.

### Providers

`scoreboardProvider(window)` calling the RPC; invalidated on prayer log / cycle change.

---

## Module 4 — Role-specific Cycle Care Dashboards

### Purpose

Reachable from the cycle section and surfaced contextually on home during an active cycle. Renders a different experience per role.

### Wife's self-care view (tabs)

- **Physical** — rest, hydration, iron-rich nutrition, warmth for cramps, gentle movement, sleep.
- **Emotional** — normalizing mood shifts, self-compassion, lowering the productivity bar.
- **Spiritual** — reassurance that exemption from ṣalāh/fasting is a mercy, not a deficiency; what she *can* still do (dhikr, duʿā, listening to Qurʾān, seeking knowledge, ṣadaqah); the reminder to make up missed fasts later.

### Husband's care & support view

- **Support** — patience, emotional presence, practical help (chores, comfort foods, warmth); anchored in the Prophetic example ﷺ of gentleness during menses.
- **What's permitted** — the intimacy ruling (abstain from intercourse per Qurʾān 2:222, while affection/companionship remain), stated plainly and non-graphically.
- **Empathy** — a short, plain explanation of cramps/PMS; a duʿā for her wellbeing.

### Content model

Seed library table `cycle_care_tips` (world-readable, admin-writable, like `verses`/`hadiths`):

| column | notes |
|---|---|
| `id` | uuid pk |
| `audience` | `'wife'` \| `'husband'` |
| `category` | `'physical'`\|`'emotional'`\|`'spiritual'`\|`'support'`\|`'intimacy'`\|`'empathy'` |
| `title` | text |
| `body` | text |
| `islamic_reference` | text, sourced (sūrah:āyah or collection + number), nullable |
| `scientific_reference` | text / citation, nullable |
| `source_url` | text, nullable |
| `review_status` | `'pending_review'` \| `'verified'`, default `'pending_review'` |
| `language` | text, default `'en'` |

### Content sourcing (launch)

I draft the seed tips with proper citations; **every religious reference ships `pending_review`** and is surfaced with a "verify with a qualified scholar" note until confirmed. Nothing unverified is presented as authoritative. A visible medical disclaimer accompanies all health content.

### Code

`features/care/` — repository over `cycle_care_tips`, providers filtered by `audience`/`category`, and the two role-specific dashboard screens (gated by role).

---

## Module 5 — Settings tab (`features/settings`)

### Architecture

A **section registry**: each feature module can contribute its own settings panel, so settings grow over time without a monolithic hardcoded screen.

### Sections at launch

- **Profile** — name, madhhab, calc method, location (gender editable only while unpaired).
- **Privacy & Sharing** — the **cycle visibility toggle** (wife-only): shared ↔ private, changeable anytime, plus control over the current active cycle. Primary home of the privacy request.
- **Notifications** — prayer reminders, cycle reminders, gentle nudges.
- **Security** *(stub, grows later)* — app lock/biometric, E2E key info (ties into existing `key_vault`/`signal_keys`).
- **About / Account** — sign out, etc.

### Data model

`user_preferences (user_id uuid pk references users, prefs jsonb not null default '{}', updated_at timestamptz)`, with typed Dart accessors. Jsonb keeps settings open-ended (no migration per new setting). The cycle-sharing default lives here; per-record `visibility` on `cycle_records` still governs individual cycles.

---

## Privacy & RLS

- **`cycle_records` RLS tightened:** a user always reads/writes their own rows; a spouse may read another member's cycle rows **only when `visibility = 'shared'`**. (Current policy allows any couple-member to read all rows — this must change.)
- **`user_preferences` RLS:** read/write own row only.
- **`cycle_care_tips`:** world-readable (no user data), admin-writable — same pattern as `verses`.
- Husband's UI shows only "resting/paused" for a private cycle; dates/predictions never leave the wife's device unless she shares.

## Data flow

- Prayer logged → `prayer_logs` insert (existing repo) → `scoreboardProvider` invalidated → home rings update.
- Cycle start/end → `cycle_records` → scoreboard recomputes exemptions on next read; care dashboard surfaces on home.
- Privacy toggle → `user_preferences` / `cycle_records.visibility` → husband's visible state changes.

## Migration

One migration `20260715000001_roles_cycle_scoring.sql`:

- `users.gender` column.
- Updated `accept_pairing_invite` (same-gender rejection).
- Tightened `cycle_records` RLS (visibility-aware spouse read).
- `get_couple_scoreboard` RPC(s).
- `cycle_care_tips` table + world-readable RLS + seed content (religious rows `pending_review`).
- `user_preferences` table + own-row RLS.

## Testing

- **SQL/RPC:** scoreboard with vs without cycle exemption; streak-freeze across a cycle; timezone day-boundary; same-gender pairing rejection; cycle-records visibility RLS (spouse cannot read a private cycle).
- **Dart unit:** prediction math (avg cycle/period length), role derivation, due-prayer determination, preferences accessors.
- **Widget:** onboarding gender gate; wife-only cycle UI; husband's "paused" view; role-correct care dashboard; settings privacy toggle round-trip.

## Build order

1. Roles & onboarding (+ migration for `users.gender`, pairing RPC).
2. Cycle tracker (+ RLS tightening).
3. Cycle-aware scoring (+ scoreboard RPC).
4. Care dashboards (+ `cycle_care_tips` + seed).
5. Settings tab (+ `user_preferences`).

## Out of scope (YAGNI for this phase)

- Full health tracker (symptoms, flow intensity, fertility/ovulation).
- Aggressive leaderboard / points-and-penalties economy.
- Security section beyond a stub (biometric lock, key management UI) — later phase.
