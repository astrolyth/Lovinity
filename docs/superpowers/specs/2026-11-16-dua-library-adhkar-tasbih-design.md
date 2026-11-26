# Dua Library, Daily Adhkar, Tasbih Together & Suggestions — Design

Date: 2026-11-16 · Status: draft for approval

## Why

The deen side of the app is thin. The couple's own dua list exists, but
`duas_library` holds 6 seeded rows and no screen uses it. The `dhikr_counters` and
`dhikr_contributions` tables exist with no UI. The plan doc (Pillar A) promises a
categorized dua list, a shared dhikr goal, adhkar habits and "a du'a suggestion when
low". This work fills those promises with verified content, without breaking the
plan's rules: verified, referenced texts; a reviewer approves before couples see
anything; offline-first; private.

## Goals

1. **Dua library.** About 127 referenced duas in about 27 categories (morning, travel,
   distress, marriage, food, sleep …). You can search them by task or situation
   ("eating", "leaving home", "exam", "rain").
2. **Share a dua with your spouse** from the library, in two ways:
   - **Send in chat:** goes through the existing E2E chat as a text message (Arabic,
     translation, reference).
   - **Add to our list:** copies it into the couple's shared `duas` list, so it can be
     ticked off when answered.
3. **Daily adhkar.** Morning, evening and after-salah sets. Each item shows a tap
   counter for its repeat count (for example "3x"). When you finish a set, your spouse
   sees it ("Ayesha finished her morning adhkar").
4. **Tasbih together.** A shared dhikr goal (for example 1,000 salawat this week) on
   the existing counter tables, plus a live session. When both of you have it open,
   each tap shows on the other phone straight away.
5. **Suggestions.** "A dua for you today", picked on the device from the approved
   library using:
   - **Mood:** a one-tap "how are you today" check-in.
   - **Day of the week:** for example Friday brings salawat and Al-Kahf; Monday and
     Thursday bring a fasting reminder.
   - **Calendar:** travel, anniversary and birthday events on the shared calendar, and
     the spouse being away.

## Non-goals

- Hadith or verse expansion. The daily verse and hadith pool is a separate,
  later project.
- Hijri/Islamic-month suggestions beyond the weekday rules above.
- Audio recitation of duas.
- Translations other than English.
- AI anything. No text is generated. Suggestions are rules over approved rows.
- Calendar changes. The calendar is already built (screen, editor, home card,
  reminders). The user mentioned a "coming soon" calendar, but none was found in code.
  Out of scope until they point to it.

## Anti-goals (failure even if it works)

- Any dua or dhikr text shown to a couple that a human did not approve, or that has
  no source reference.
- The app calling third-party Islamic APIs at runtime. That leaks usage, breaks
  offline use, and those free hosts go down.
- Guilt. No "you missed your adhkar" streak shaming. Completion is celebrated, and a
  gap is never mentioned.
- Mood shown to the spouse without consent. In this project mood never leaves the
  device.

## Constraints

- **Free tier only.**
  - **Supabase free:** 500 MB database, 2 M realtime messages per month, 200
    concurrent realtime connections, and the project pauses after a week idle.
  - **No paid API calls.**
  - **Content size:** under 1 MB in total.
- **Existing review pattern.** `daily_questions` carries
  `status` pending/approved/rejected and a `source` column, and reads filter on
  `status='approved'`. Content tables follow the same pattern.
- **Existing patterns to reuse:**
  - Couple RLS on every couple table.
  - Riverpod stream providers.
  - `newRowDetector` notification pumps.
  - The realtime broadcast wrapper in `lib/features/chat/data/typing_channel.dart`.
  - `ChatService.sendText`.
- **Licensing:**
  - fitrahive/dua-dhikr is MIT: credit it in the settings "Sources" list.
  - UmmahAPI is "provided as sadaqah jariah". Before shipping, the user confirms that
    its terms allow redistribution, and it is credited.

## Approaches (chosen: A, A, A)

**Content in.** We considered:
- **(A, chosen):** a one-time import into our own tables, reviewed, then shipped in
  a migration.
- **(B):** a monthly sync edge function. It uses up free-tier allowance for content
  that barely changes.
- **(C):** live API calls from the app. This breaks privacy and offline use.

**Suggestions.** We considered:
- **(A, chosen):** rules on the device over tags. Free, instant and offline.
- **(B):** Claude picks the dua. It costs money per call and needs a network.

**Tasbih live.** We considered:
- **(A, chosen):** taps go over a realtime broadcast between the two phones. Each
  phone saves its count to the database every few seconds and when the session ends.
- **(B):** write every tap to the database. 1,000 taps would mean 1,000 writes plus
  1,000 realtime events.

## Design

### Data (one migration)

**`duas_library`** is extended rather than replaced. Six seeded rows already exist.
New columns:

| Column | Notes |
|---|---|
| `status` | `pending`/`approved`/`rejected`, default `pending` |
| `source` | `'ummahapi'`, `'fitrahive'`, `'seed'` |
| `source_id` | the upstream id |
| `repeat_count` | int, default 1 |
| `benefit` | `fawaid`/notes, nullable |
| `tags` | `text[]` |
| `sort_order` | int |

- **Existing rows:** the 6 seeded rows become `status='approved'`, `source='seed'`.
- **Read policy** becomes `status='approved'`. `service_role` keeps its full grant.
- **Uniqueness:** `(source, source_id)` is unique, so a re-import is an upsert.
- **Columns already present:** `category`, `reference` and the text columns. The
  category for adhkar items is `'morning'`, `'evening'` or `'after_prayer'`.

**`adhkar_completions`** is new and couple-scoped:

| Column | Notes |
|---|---|
| `couple_id` | |
| `user_id` | |
| `local_date` | |
| `set` | `morning`/`evening`/`after_prayer` |
| `completed_at` | |

- **Key:** `(user_id, local_date, set)` is unique.
- **RLS:** the couple can read; you can insert only your own row. No update. Delete
  your own.
- **Per-item tap counts** are not stored. They live on the device for the day. A
  completion row is all the spouse needs.

**Tasbih:**
- **Tables:** reuse `dhikr_counters` and `dhikr_contributions` as they are.
- **Read helper:** add an RPC (or view) `dhikr_counter_totals(counter_id)` that
  returns the total and each member's share for the current period. Then the client
  doesn't stream every contribution row.
- **Live channel:** a realtime **broadcast** channel `tasbih:<couple_id>`, with no
  DB writes per tap.

**Mood:** stored only on the device (local prefs keyed by date). No table.

### Import tooling

- **Script:** `tool/import_islamic_content.dart`, run by hand by a developer.
  1. Fetch UmmahAPI `/api/duas/categories` and each category.
  2. Fetch fitrahive `morning-dhikr`, `evening-dhikr` and `dhikr-after-salah` (en).
  3. Normalise the rows. For fitrahive, parse "Recite 3x" into `repeat_count`.
     Upstream adhkar "categories" map to our `category`.
  4. Attach `tags` from a **checked-in mapping file**,
     `tool/content_tags.json`. It holds category→tags plus per-item overrides.
  5. Write a migration file of upserts with `status='pending'`.
- **Review:** the reviewer approves rows in the Supabase dashboard (or with a bulk
  `update … set status='approved' where source=…` after reading them). The resulting
  approvals ship as a follow-up migration, so production gets exactly what was
  reviewed.
- **Rejects:** any row without a `reference`/`source` is rejected by the script, not
  imported.

### Suggestions engine

- **Code:** a pure Dart function
  `suggestDuas({mood, weekday, upcomingEvents, spouseAway, library, seed})` returns at
  most 3 duas, each with the reason it was picked ("Because you're travelling today").
- **Rules:** a table of `trigger → tags`.

| Trigger | Tags |
|---|---|
| Mood anxious | `distress`, `protection` |
| Mood sad | `grief`, `distress` |
| Mood grateful/happy | `gratitude` |
| Mood unwell | `illness` |
| Mood tired | `sleep`, `dhikr` |
| Weekday Friday | `salawat`, `dhikr` (plus a Kahf reminder line) |
| Weekday Mon/Thu | `fasting` |
| Calendar event today/tomorrow with "travel"/"trip"/"flight" in the title | `travel` |
| Calendar kind `anniversary` | `marriage` |
| Calendar kind `birthday` | `gratitude` |
| Spouse in a different timezone or away | `protection`, `travel` |

- **Pick:** from the matching approved duas, choose deterministically per day (seeded
  by date and user), so the card doesn't reshuffle on rebuild.
- **Fallback:** if nothing matches, a general `dhikr` dua.

### Screens

**Duas screen**, with tabs:
- **Our list:** the existing screen, unchanged.
- **Library:**
  - A search field. It matches title, translation, transliteration, category name and
    tags, case- and diacritic-insensitive, client-side over at most about 200 cached
    rows.
  - Category chips.
  - A detail sheet: Arabic, transliteration, translation, reference, repeat count, and
    the actions **Send to spouse** (chat) and **Add to our list**.
- **Adhkar:**
  - Morning, Evening and After-salah cards.
  - Each item shows a tap counter ring. It turns into a check at its repeat count.
  - The set completes when every item is done. That writes the completion row and
    shows a gentle "done" state.
  - Your spouse's completion is shown on the card.

**Home:** a "Dua for you today" card.
- Shows the top suggestion, its reason, and a mood row of 5 emoji-free labelled chips.
- Tapping the card opens the detail sheet.

**Tasbih:** from the Duas screen and a home entry.
- **Goal list:** counters with progress bars, a "mine vs spouse" split, and a create
  sheet (title, Arabic, target, period).
- **Session screen:**
  - A big tap area with haptics.
  - Live combined count.
  - A "spouse is here" presence dot.
  - Local taps are batched and saved to `dhikr_contributions` every 5 s, on pause, and
    on leave.
  - Broadcast deltas are throttled (at most about 4 per second) so it stays far under
    the free-tier message limits.

**Notifications:**
- **Pump:** reuse the `newRowDetector` pattern for spouse adhkar completions ("Your
  partner finished morning adhkar").
- **Counter goal:** a notification when the counter goal is reached.

**Settings:** a "Content sources" entry crediting UmmahAPI and fitrahive (MIT).

### Testing

- **SQL tests:**
  - A couple can't read pending library rows.
  - Adhkar completions: RLS for own and spouse, no cross-couple access, and the
    unique key holds.
  - The totals RPC.
- **Dart unit tests:**
  - The suggestion rules (each trigger, fallback, stable per day).
  - The search normaliser (diacritics).
  - Repeat-count parsing.
  - The tasbih batcher (flush on timer, pause and dispose; no lost taps).
- **Widget tests:**
  - Library search and filter.
  - Detail sheet actions call the chat and dua repositories.
  - Adhkar set completion writes one row.
  - The tasbih screen sums local and remote taps.

## Left to the builder

- Exact visual design, within the existing theme and motion helpers.
- Exact tag vocabulary and per-item overrides in `content_tags.json`.
- Chat message formatting for a shared dua.
- How the tasbih reconnect reconciles. The DB totals are the truth, and the broadcast
  is only for liveness.

## Decisions after review (2026-11-16) — these override anything above

- **Single source: fitrahive/dua-dhikr (MIT).** The user's rule: skip any API that
  does not allow copying. UmmahAPI publishes no license or terms (`/terms` is a 404;
  the footer says only "© UmmahAPI"), so it is **not used**. Naikiyah, IslamicAPI and
  Deenify stay unused.
  - **Library:** `daily-dua` (38) + `selected-dua` (8), so 46 duas, all with a
    `source`.
  - **Adhkar:** `morning-dhikr` (19) + `evening-dhikr` (19) + `dhikr-after-salah`
    (13, of which 10 have a source).
  - **Categories:** fitrahive has none, so `tool/content_tags.json` gives each library
    title a category plus tags (for example eating→`food`, rain→`weather`,
    calamity/debt→`distress`, traveller→`travel`).
  - **Size:** the library is smaller than the 127 first estimated. Library search
    covers all approved rows, adhkar included, so about 100 rows.
- **Approval: bulk-approve referenced rows.**
  - **Referenced rows:** any row with a non-empty `source` is written as
    `status='approved'` by the generated migration.
  - **Unreferenced rows** (for example the 3 after-salah surah items) are written as
    `pending`, for a human to approve by hand.
  - **Script behaviour:** the script no longer drops unreferenced rows.
- **Attribution:** the settings "Content sources" entry credits fitrahive/dua-dhikr
  (MIT) only. The MIT license text is kept at `assets/licenses/fitrahive-dua-dhikr.txt`
  and registered with Flutter's `LicenseRegistry`.

## Calls I made (check these)

- **Sharing:** "Send to spouse" uses plain chat text, not a new chat message kind.
  This avoids touching the E2E payload format.
- **Mood:** stays on the device only.
- **Adhkar progress:** per-item taps aren't synced, only set completion.
- **Sources:** UmmahAPI for the library and fitrahive for adhkar. Naikiyah,
  IslamicAPI and Deenify are not used: Naikiyah has no references, IslamicAPI needs a
  key, and Deenify is a demo host.
