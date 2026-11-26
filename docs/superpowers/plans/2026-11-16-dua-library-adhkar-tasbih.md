# Dua Library, Daily Adhkar, Tasbih Together & Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Duas section gains these features:
- A searchable, referenced dua library with "send to spouse" and "add to our list".
- Daily morning, evening and after-salah adhkar, with a completion your spouse can
  see.
- Live "tasbih together" counters.
- A home card suggesting a dua by mood, weekday and calendar.

**Architecture:**
- **Content:** a one-time Dart import script turns fitrahive/dua-dhikr (MIT) JSON
  into a SQL migration in our own `duas_library`. Referenced rows are approved and
  the rest pending. The app reads only approved rows over Supabase.
- **Adhkar:** completions are one row per set per day.
- **Tasbih:** live taps go over a Realtime broadcast channel and are saved in batches
  to the existing `dhikr_contributions`.
- **Suggestions:** a pure on-device rules function over tags.

**Tech Stack:** Flutter, Riverpod 3, go_router, supabase_flutter (Postgres RLS,
Realtime broadcast and presence), flutter_secure_storage (device-local state),
package:http (import script only).

**Spec:** `docs/superpowers/specs/2026-11-16-dua-library-adhkar-tasbih-design.md`.
Its "Decisions after review" section overrides the earlier sections.

## Global Constraints

- **Free tier only:**
  - No paid API calls.
  - No runtime calls to any third-party Islamic API.
  - No new server function.
  - No per-tap DB writes.
- **Content:**
  - Content comes only from fitrahive/dua-dhikr (MIT), sets `daily-dua`,
    `selected-dua`, `morning-dhikr`, `evening-dhikr` and `dhikr-after-salah`, file
    `en.json`.
  - Raw base: `https://raw.githubusercontent.com/fitrahive/dua-dhikr/main/data/dua-dhikr/<set>/en.json`.
  - A row with a non-empty `source` is imported as `status='approved'`. A row
    without one is imported as `status='pending'`.
  - Couples can read only `status='approved'` rows.
  - No AI-generated religious text, anywhere.
- **Mood:** never leaves the device. No table, no network.
- **Copy tone:** gentle, with no guilt or streak shaming. A missed adhkar set is never
  mentioned.
- **Sharing a dua:**
  - **Send to spouse** uses the existing `ChatService.sendText` (E2E). Do not change
    the chat payload format.
  - **Add to our list** uses the existing `DuaRepository.add` with
    `visibility: 'shared'`.
- **Tasbih limits:**
  - Batch saves happen every 5 s, on app pause, and on leaving the screen.
  - Broadcast sends are throttled to at most one every 250 ms (about 4 per second).
- **Migrations:**
  - Number them `20261116000004_*` (schema) and `20261116000005_*` (generated
    content).
  - Apply them locally with
    `PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -f <file>`,
    then
    `insert into supabase_migrations.schema_migrations(version,name) values ('<version>','<name>')`.
    `supabase migration up` fails on this DB.
- **Tests:** Flutter tests run with `flutter test --concurrency=1`. SQL tests are
  plain psql scripts in `supabase/tests/` (DO-block asserts, `begin … rollback`,
  `set local request.jwt.claim.sub`), the same as
  `supabase/tests/letters_gender_guards_test.sql`.
- **Reuse, don't re-invent:**
  - `LovScaffold`, `LovCard`, `LovSpace`.
  - `newRowDetector` (`lib/core/notifications/activity_detectors.dart`).
  - `notificationStoreProvider.insertBestEffort(kind,title,body,route)`.
  - `dayKey` / `localDayAt` (`lib/core/time/local_day.dart`).
  - `ownProfileProvider` / `spouseProfileProvider` (`lib/features/home/domain/home_providers.dart`;
    `UserProfile.timezone`).
  - `currentCoupleProvider`, `authSessionProvider`.
  - `upcomingEventsProvider` (`List<UpcomingEvent>` with `.event` and `.date`;
    `CalendarEvent.kind` is `CalendarEventKind {event, anniversary, birthday, islamic}`).
  - `secureStorageProvider`.

## Review Focus

1. **App killed or backgrounded mid-tasbih with unflushed taps.** Taps are saved on
   pause, and at most 5 s of taps can be lost to a hard kill. Pinned in Task 6 (batcher
   flush-on-pause test).
2. **Offline while tapping.** A failed save keeps the count and retries on the next
   flush, so no taps are lost. Pinned in Task 6.
3. **Search with diacritics, case and several words.** "ṣabāḥ", "SABAH" and
   "eating food" all match the right duas. Pinned in Task 3.
4. **No approved library rows yet (fresh DB, offline first open).**
   - The Library tab shows "Duas are on their way".
   - The Adhkar tab shows the same empty state.
   - The suggestion card hides; it doesn't crash.
   
   Pinned in Tasks 3, 5 and 7.
5. **Day rollover in the user's own timezone.** Adhkar progress and today's mood reset
   at local midnight in `UserProfile.timezone`, not device UTC. Pinned in Tasks 5 and 7.

---

### Task 1: Schema: library review columns, adhkar completions, tasbih totals

**Files:**
- Create: `supabase/migrations/20261116000004_dua_library_adhkar_tasbih.sql`
- Test: `supabase/tests/dua_library_adhkar_tasbih_test.sql`

**Interfaces:**
- **Produces, columns:** `duas_library` gains these columns, and existing rows are
  updated to `status='approved'`, `source='seed'`, `source_id=id::text`:

| Column | Type | Default |
|---|---|---|
| `status` | text, check in `pending`/`approved`/`rejected` | `pending` |
| `source` | text | `'seed'` |
| `source_id` | text | |
| `repeat_count` | int not null | 1 |
| `benefit` | text | |
| `tags` | text[] not null | `'{}'` |
| `sort_order` | int not null | 0 |

- **Produces, constraints and access:**
  - A unique index on `(source, source_id)`.
  - Policy `duas_library_read` becomes `using (status = 'approved')`.
- **Produces, `public.adhkar_completions`:**
  - Columns: `id uuid pk default gen_random_uuid()`, `couple_id uuid not null → couples
    on delete cascade`, `user_id uuid not null → users on delete cascade`,
    `local_date date not null`, `set text not null check in
    ('morning','evening','after_prayer')`, `completed_at timestamptz not null
    default now()`.
  - Unique key: `(user_id, local_date, set)`.
  - RLS: select `is_couple_member(couple_id)`; insert `with check (user_id =
    auth.uid() and is_couple_member(couple_id))`; delete `using (user_id =
    auth.uid())`; no update policy.
  - Grants: select, insert, delete to authenticated. Add it to the
    `supabase_realtime` publication.
- **Produces, `public.dhikr_counter_totals(p_counter_id uuid) returns table(user_id
  uuid, total bigint)`:**
  - Security invoker, stable.
  - Sums `dhikr_contributions.count` for the counter within the current period:
    - `once`: since `starts_at`.
    - Otherwise, the window is `starts_at + floor((now()-starts_at)/len)*len`, where
      `len` is 1 day, 7 days or 30 days for daily, weekly and monthly.
  - Grant execute to authenticated. RLS on the underlying tables keeps it
    couple-scoped.

- [ ] **Step 1: Write the failing SQL test.**
  - **Fixtures:** couple A+B, an outsider C, all with `77777777-…`-style ids but a
    new prefix `88888888-`. One pending and one approved library row.
  - **Asserts, each raising `FAIL:` / noticing `PASS:`:**
    1. As A, `select count(*) from duas_library where source_id='t-pending'` = 0, and
       `'t-approved'` = 1.
    2. A inserts their own morning completion. A second identical insert raises
       `unique_violation`.
    3. A inserting a completion with `user_id` = B raises an RLS error
       (`insufficient_privilege` / new-row violation).
    4. B can read A's completion. C (another couple) reads 0 rows.
    5. A updating `completed_at` affects 0 rows (no update policy).
    6. Counter period `weekly` with `starts_at = now() - interval '10 days'`. A
       contribution 9 days ago (count 5) and one 1 day ago (count 7) give
       `dhikr_counter_totals` total 7 for A. For a `once` counter the same two give
       12.

- [ ] **Step 2: Run the test to verify it fails.**
  Run: `PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f supabase/tests/dua_library_adhkar_tasbih_test.sql`
  Expected: an ERROR, because column `status` or relation `adhkar_completions` does
  not exist.

- [ ] **Step 3: Write the migration with exactly the interfaces above.** Apply it
  locally and record it in `schema_migrations` (see Global Constraints).

- [ ] **Step 4: Run the new test plus every existing `supabase/tests/*.sql`.**
  Expected: all PASS, no ERROR.

- [ ] **Step 5: Commit.**
  `git add supabase/migrations/20261116000004_dua_library_adhkar_tasbih.sql supabase/tests/dua_library_adhkar_tasbih_test.sql && git commit -m "feat(duas): library review columns, adhkar completions, tasbih totals"`

---

### Task 2: Content import script, tags file, generated content migration, attribution

**Files:**
- Create:
  - `tool/content_import.dart` (pure functions)
  - `tool/import_islamic_content.dart` (CLI: fetch, then write SQL)
  - `tool/content_tags.json`
  - `supabase/migrations/20261116000005_islamic_content.sql` (generated)
  - `assets/licenses/fitrahive-dua-dhikr.txt` (the MIT text from the repo's LICENSE)
- Modify:
  - `pubspec.yaml`: add the asset.
  - `lib/main.dart`: `LicenseRegistry.addLicense` for `fitrahive/dua-dhikr`.
  - `lib/features/settings/presentation/settings_screen.dart`: a "Content sources"
    tile. Its subtitle is "Duas & adhkar: fitrahive/dua-dhikr (MIT)", and tapping it
    calls `showLicensePage`.
- Test: `test/tool/content_import_test.dart`

**Interfaces:**
- **Produces in `tool/content_import.dart`:**
  - `int parseRepeatCount(String? notes)`: the first `(\d+)\s*x` (case-insensitive),
    else 1.
  - `class ImportRow { String source; String sourceId; String title; String arabic;
    String? transliteration; String translation; String? reference; String category;
    int repeatCount; String? benefit; List<String> tags; int sortOrder; String status; }`
  - `List<ImportRow> rowsForSet(String set, List<Map<String,dynamic>> items,
    Map<String,dynamic> tagsJson)`. The field mapping:

| Row field | Comes from |
|---|---|
| `source` | `'fitrahive'` |
| `sourceId` | `'$set/$index'` |
| `transliteration` | `latin` |
| `reference` | `source` |
| `benefit` | `fawaid ?? benefits` |
| `status` | `'approved'` if the trimmed source is non-empty, else `'pending'` |
| `sortOrder` | the index |

  - **Category for adhkar sets:** `morning-dhikr`→`morning`, `evening-dhikr`→`evening`
    and `dhikr-after-salah`→`after_prayer`, with tags `['dhikr', <category>]` plus any
    override.
  - **Category for `daily-dua` and `selected-dua`:** category and tags come from
    `tagsJson['$set/$index']`. A missing entry throws `StateError('untagged: $set/$index')`.
  - `String toSqlUpsert(List<ImportRow> rows)`:
    - Writes one `insert into public.duas_library (...) values ... on conflict
      (source, source_id) do update set <all content columns>`.
    - Text is single-quoted with `'` doubled, `null` is written as `null`, and
      `text[]` as `array['a','b']::text[]`.
    - **The conflict update must not touch `status`.** A re-import never re-approves a
      row a human rejected.
- **`tool/content_tags.json` shape:** `{ "daily-dua/0": {"category":"sleep","tags":["sleep"]}, ... }`.
  - It covers every index of `daily-dua` (38) and `selected-dua` (8).
  - Required: every tag the Task 7 rules use (`distress`, `protection`, `grief`,
    `gratitude`, `sleep`, `dhikr`, `fasting`, `travel`, `marriage`) appears on at
    least one row. `illness` is optional, because fitrahive has no illness dua outside
    the morning adhkar. The rule falls through to `distress`.
  - Suggested mappings:
    - Calamity → `grief` and `distress`.
    - Debt and anxiety → `distress`.
    - Breaking the fast → `fasting`.
    - The traveller duas → `travel` and `protection`.
    - "Seeking Good In This World And In The Hereafter" → `marriage` and `gratitude`.
    - Good news → `gratitude`.
    - Protection from harm → `protection`.

- [ ] **Step 1: Write the failing tests** in `test/tool/content_import_test.dart`
  (import with the relative path `../../tool/content_import.dart`):
  - `parseRepeatCount('Recite 3x') == 3`
  - `parseRepeatCount('Read 100X a day') == 100`
  - `parseRepeatCount(null) == 1`
  - `parseRepeatCount('Recite once') == 1`
  - `rowsForSet('morning-dhikr', [{title:'T', arabic:'ع', latin:'l', translation:'t',
    notes:'Recite 3x', fawaid:'f', source:'HR. Abu Dawud No. 4241'}], {})` gives one
    row with `category=='morning'`, `repeatCount==3`, `status=='approved'`,
    `sourceId=='morning-dhikr/0'` and `tags` containing `'morning'`.
  - The same row with `source: '  '` gives `status=='pending'`.
  - `rowsForSet('daily-dua', [<one item>], {})` throws `StateError`.
  - `toSqlUpsert` on a title `"Allah's mercy"` contains `'Allah''s mercy'`, contains
    `on conflict (source, source_id) do update`, and its `do update set` clause does
    not contain `status`.
  - The real `tool/content_tags.json` covers every rule tag listed above.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/tool/content_import_test.dart`
  Expected: a compile error (missing file).

- [ ] **Step 3: Implement `tool/content_import.dart`, then the CLI and the tags file.**
  - **The CLI:** `dart run tool/import_islamic_content.dart`.
    1. Fetch the five sets with `package:http`.
    2. Write `supabase/migrations/20261116000005_islamic_content.sql` with a header
       comment naming the source, the commit date and the MIT license.
    3. Print counts per set and status.
  - **Tags file:** write `tool/content_tags.json` by reading the fetched titles.

- [ ] **Step 4: Run the tests to verify they pass, then generate and apply.**
  1. `flutter test test/tool/content_import_test.dart`. Expected: PASS.
  2. `dart run tool/import_islamic_content.dart`. Expected: about 97 rows, about 3
     pending.
  3. Apply `20261116000005` locally (Global Constraints).
  4. Check: `select status, count(*) from duas_library group by 1` shows `approved`
     about 100 (including the 6 seed rows) and `pending` about 3.
  5. Run `supabase/tests/*.sql`. Expected: all PASS.

- [ ] **Step 5: Wire the license and the settings tile.**
  Run `flutter analyze`. Expected: no new issues.

- [ ] **Step 6: Commit** all files listed in this task, with the message
  `feat(duas): import referenced duas & adhkar from fitrahive/dua-dhikr (MIT)`.

---

### Task 3: Library data, providers and search

**Files:**
- Create:
  - `lib/features/duas/data/dua_library_repository.dart`
  - `lib/features/duas/domain/dua_library_providers.dart`
  - `lib/features/duas/domain/dua_search.dart`
- Test:
  - `test/features/duas/dua_search_test.dart`
  - `test/features/duas/dua_library_repository_test.dart`

**Interfaces:**
- **Produces, the model:** `class LibraryDua`:
  - Fields: `{String id, String title, String arabic, String? transliteration, String
    translation, String? reference, String? category, int repeatCount, String?
    benefit, List<String> tags, int sortOrder}`.
  - Constructor: `factory LibraryDua.fromRow(Map<String,dynamic>)`. DB column names:
    `arabic_text`, `transliteration`, `translation`, `reference`, `category`,
    `repeat_count`, `benefit`, `tags`, `sort_order`.
- **Produces, the repository:** `class DuaLibraryRepository(SupabaseClient)` with
  `Future<List<LibraryDua>> fetchApproved()`:
  - It does `.eq('status','approved')` as defense in depth.
  - It orders by `category`, then `sort_order`.
- **Produces, the providers:**
  - `final duaLibraryRepositoryProvider = Provider<DuaLibraryRepository>`.
  - `final duaLibraryProvider = FutureProvider<List<LibraryDua>>`, with
    `ref.keepAlive()` after success.
- **Produces, search:**
  - `String normalizeForSearch(String s)`: lowercase. It strips Latin diacritics,
    mapping each of `āáàâä ēéèêë īíìîï ōóòôö ūúùûü ṣ ḥ ṭ ḍ ẓ ʿ ʾ ' ’` to its base letter
    or removing it.
  - `List<LibraryDua> searchLibrary(List<LibraryDua> all, String query, {String? category})`:
    - Splits the normalized query on whitespace. Every term must appear in the
      normalized `title + translation + transliteration + category + tags` (AND).
    - An empty query returns `all`, filtered by category if one is given.
  - `const adhkarCategories = {'morning','evening','after_prayer'}`.

- [ ] **Step 1: Write the failing tests.**
  - **`dua_search_test`:**
    - `normalizeForSearch('Ṣabāḥ') == 'sabah'`.
    - `searchLibrary` over three fixtures (titles "Supplication Before Eating",
      "Travel Supplication", "Upon Entering The Morning"; the third has
      transliteration "aṣbaḥnā"):
      - query `'EATING'` → [eating]
      - `'eating before'` → [eating]
      - `'eating travel'` → []
      - `'asbahna'` → [morning]
      - `''` with category `'travel'` → [travel]
    - The empty list in gives the empty list out.
  - **`dua_library_repository_test`:** `LibraryDua.fromRow` maps every column. A
    missing `tags` gives `[]`, and a missing `repeat_count` gives 1.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/features/duas/dua_search_test.dart test/features/duas/dua_library_repository_test.dart`
  Expected: a compile error.

- [ ] **Step 3: Implement the three files with exactly the interfaces above.**

- [ ] **Step 4: Run the tests to verify they pass.** Expected: PASS.

- [ ] **Step 5: Commit** with the message
  `feat(duas): library repository, providers and diacritic-insensitive search`.

---

### Task 4: Duas screen tabs, Library tab, dua detail sheet with share actions

**Files:**
- Modify: `lib/features/duas/presentation/dua_list_screen.dart`. Wrap the existing
  body in a `DefaultTabController` with three tabs: "Our list" (the existing content,
  unchanged), "Library" and "Adhkar". The Adhkar tab is a placeholder `SizedBox` until
  Task 5. The FAB shows only on "Our list". The title stays "Our duas".
- Create:
  - `lib/features/duas/presentation/library_tab.dart`
  - `lib/features/duas/presentation/library_dua_sheet.dart`
  - `lib/features/duas/domain/dua_share.dart`
- Test:
  - `test/features/duas/library_tab_test.dart`
  - `test/features/duas/dua_share_test.dart`

**Interfaces:**
- **Consumes:** `duaLibraryProvider`, `searchLibrary`, `adhkarCategories` (Task 3).
  Also `chatServiceProvider` (a `FutureProvider<ChatService?>`; send with `await
  (await ref.read(chatServiceProvider.future))?.sendText(body)`), and
  `duaRepositoryProvider.add(coupleId:, userId:, title:, body:, visibility:'shared')`.
- **Produces:**
  - `String formatDuaForChat(LibraryDua d)`: the lines below, joined by `\n`, with
    null lines omitted.
    ```
    🤲 <title>
    <arabic>
    <transliteration>
    "<translation>"
    — <reference>
    ```
  - `String duaListBody(LibraryDua d)`: `arabic`, a blank line, `translation`, a blank
    line, then `— reference` if present.
  - `Future<void> showLibraryDuaSheet(BuildContext, LibraryDua)`:
    - Shows Arabic (RTL, large), transliteration, translation, reference, "Repeat
      N×" when N > 1, and the benefit.
    - **"Send to spouse":** on success, a SnackBar "Sent to your spouse". If the chat
      service is null or throws, a SnackBar "Couldn't send — try again from chat".
    - **"Add to our list":** a SnackBar "Added to your shared list".
- **Library tab:**
  - A search `TextField` (hint "Search: eating, travel, rain…").
  - A horizontal row of category `ChoiceChip`s, built from the distinct non-adhkar
    categories, with "All" first.
  - A list of title and first line of translation. Tapping a row opens the sheet.
- **Library tab states:**
  - **Empty library:** centered "Duas are on their way."
  - **Search with no match:** "No duas match "<q>"."
  - **Loading:** the existing `_ListSkeleton` pattern.
  - **Error:** "Could not load".

- [ ] **Step 1: Write the failing tests.**
  - **`dua_share_test`:** `formatDuaForChat` with all fields contains the title, the
    Arabic, the quoted translation and `— ref`. With a null transliteration and
    reference, it has no `null` text and no `—` line.
  - **`library_tab_test`** (override `duaLibraryProvider` with fixtures):
    - Typing "eating" leaves 1 row.
    - Tapping the "travel" chip shows only travel.
    - An empty library shows "Duas are on their way."
    - Tapping a row then "Send to spouse" calls a fake `ChatService.sendText` once,
      with `formatDuaForChat(dua)`.
    - "Add to our list" calls a fake `DuaRepository.add` with `visibility: 'shared'`
      and `body: duaListBody(dua)`.
    - Use mocktail fakes, the same as the existing tests in `test/features/duas/`.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/features/duas/library_tab_test.dart test/features/duas/dua_share_test.dart`
  Expected: FAIL (compile).

- [ ] **Step 3: Implement the tabs, the Library tab, the sheet and `dua_share.dart`.**

- [ ] **Step 4: Run the tests, plus the existing `test/features/duas/`.**
  Expected: all PASS.

- [ ] **Step 5: Commit** with the message
  `feat(duas): library tab with search, categories and share to spouse`.

---

### Task 5: Daily adhkar: progress, completion, spouse notification

**Files:**
- Create:
  - `lib/features/duas/data/adhkar_repository.dart`
  - `lib/features/duas/data/adhkar_progress_store.dart`
  - `lib/features/duas/domain/adhkar_providers.dart`
  - `lib/features/duas/presentation/adhkar_tab.dart`
- Modify:
  - `lib/features/duas/presentation/dua_list_screen.dart` (the Adhkar tab →
    `AdhkarTab`).
  - `lib/features/home/presentation/home_screen.dart`: watch
    `adhkarNotificationPumpProvider` next to the existing pump watches (around line
    58).
- Test:
  - `test/features/duas/adhkar_progress_store_test.dart`
  - `test/features/duas/adhkar_tab_test.dart`

**Interfaces:**
- **Produces, the set enum:** `enum AdhkarSet { morning, evening, afterPrayer }`, with
  `String get dbValue` ('morning' | 'evening' | 'after_prayer') and `String get
  label` ('Morning' | 'Evening' | 'After salah').
- **Produces, the completion model:** `class AdhkarCompletion { String userId; String
  localDate; AdhkarSet set; DateTime completedAt; }`.
- **Produces, the repository:** `class AdhkarRepository(SupabaseClient)` with:
  - `Stream<List<AdhkarCompletion>> watchRecent(String coupleId)`: stream on
    `adhkar_completions` `.eq('couple_id')`, ordered by `completed_at` descending,
    `.limit(20)`.
  - `Future<void> complete({required String coupleId, required String userId, required
    String localDate, required AdhkarSet set})`: an upsert with `onConflict:
    'user_id,local_date,set'` and `ignoreDuplicates: true`.
- **Produces, the local progress store:** `class AdhkarProgressStore(FlutterSecureStorage)`
  with:
  - `Future<Map<String,int>> load(String dayKey, AdhkarSet set)`
  - `Future<void> save(String dayKey, AdhkarSet set, Map<String,int> countsByDuaId)`
  - The key is `adhkar:<dayKey>:<dbValue>` holding a JSON map. On load, it deletes
    keys whose `dayKey` isn't today's.
- **Produces, the providers:**
  - `final adhkarTodayKeyProvider = Provider<String>`: `dayKey(localDayAt(ownProfile.timezone, DateTime.now()))`,
    falling back to `'UTC'` when the profile isn't loaded.
  - `final adhkarCompletionsProvider = StreamProvider<List<AdhkarCompletion>>`.
  - `final adhkarNotificationPumpProvider = Provider<void>`: `newRowDetector` keyed by
    `'${userId}|${localDate}|${set.dbValue}'`. When the spouse completes, it calls
    `insertBestEffort(kind: 'adhkar', title: 'Your partner finished ${set.label.toLowerCase()} adhkar', body: null, route: '/home/duas')`.
    Narrow the ids with `.select`, the same as `duaNotificationPumpProvider`.
- **Adhkar tab:**
  - Three expandable `LovCard`s, one per set. Items are `duaLibraryProvider`, filtered
    by `category == set.dbValue` and sorted by `sortOrder`.
  - Each item has a tap target with a progress ring `n / repeatCount`. Tapping
    increments it, up to `repeatCount`, and saves.
  - When every item in a set is at its repeat count, it calls `complete(...)` once and
    the card header shows "Done — may Allah accept".
  - The header also shows "<Spouse> finished" when a spouse completion exists for
    today's key.
  - **Empty state:** "Adhkar are on their way."

- [ ] **Step 1: Write the failing tests.**
  - **`adhkar_progress_store_test`** (an in-memory fake of FlutterSecureStorage):
    - Save, then load, round-trips.
    - Loading for a new dayKey returns `{}` and deletes the old day's key.
  - **`adhkar_tab_test`:**
    - A morning set of two fixtures with repeatCount 1 and 3. Tapping item 1 once and
      item 2 three times calls the fake `AdhkarRepository.complete` exactly once, with
      `set: AdhkarSet.morning`. A 4th tap on item 2 does nothing.
    - A spouse completion row for today's key shows "finished".
    - An empty library shows "Adhkar are on their way."
    - `adhkarTodayKeyProvider` with profile tz `Pacific/Auckland`, at a fixed UTC
      instant 2026-11-16T12:30Z, gives `'2026-11-17'`. Inject the clock through a
      `nowProvider` override if the file has none; add `final nowProvider =
      Provider<DateTime Function()>((_) => DateTime.now)` in `adhkar_providers.dart`.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/features/duas/adhkar_progress_store_test.dart test/features/duas/adhkar_tab_test.dart`
  Expected: FAIL (compile).

- [ ] **Step 3: Implement it.**

- [ ] **Step 4: Run the tests, plus the existing `test/features/duas/` and
  `test/features/home/` if present.** Expected: PASS.

- [ ] **Step 5: Commit** with the message
  `feat(duas): daily adhkar with tap counts and spouse completion`.

---

### Task 6: Tasbih together

**Files:**
- Create:
  - `lib/features/duas/data/tasbih_repository.dart`
  - `lib/features/duas/data/tasbih_channel.dart`
  - `lib/features/duas/domain/tap_batcher.dart`
  - `lib/features/duas/domain/tasbih_providers.dart`
  - `lib/features/duas/presentation/tasbih_list_screen.dart`
  - `lib/features/duas/presentation/tasbih_session_screen.dart`
- Modify:
  - `lib/core/router/app_router.dart`: under `/home`, add `GoRoute(path: 'tasbih', …TasbihListScreen)`
    with a child `GoRoute(path: ':id', …TasbihSessionScreen(counterId: state.pathParameters['id']!))`.
  - `dua_list_screen.dart`: an app-bar action `IconButton(Icons.radio_button_checked,
    tooltip: 'Tasbih together')` → `context.push('/home/tasbih')`.
- Test:
  - `test/features/duas/tap_batcher_test.dart`
  - `test/features/duas/tasbih_session_screen_test.dart`

**Interfaces:**
- **Produces, the counter model:** `class DhikrCounter { String id; String title; String?
  arabicText; int target; String period /* daily|weekly|monthly|once */; DateTime
  startsAt; }` with `fromRow`.
- **Produces, the totals model:** `class CounterTotals { int mine; int spouse; int get
  total => mine + spouse; }`.
- **Produces, the repository:** `class TasbihRepository(SupabaseClient)` with:
  - `Stream<List<DhikrCounter>> watchCounters(String coupleId)`
  - `Future<void> create({required String coupleId, required String title, String?
    arabicText, required int target, required String period})`
  - `Future<void> addContribution({required String counterId, required String
    coupleId, required String userId, required int count})`
  - `Future<CounterTotals> totals(String counterId, {required String selfId})`: calls
    the RPC `dhikr_counter_totals` and splits the rows by `user_id == selfId`.
- **Produces, the batcher:** `class TapBatcher({required Duration flushEvery, required
  Future<void> Function(int count) save})`:
  - `void tap()` and `int get pending`.
  - `Future<void> flushNow()`: takes `pending` and calls `save`. On an exception it
    adds the count back to `pending` and does not rethrow.
  - `void dispose()`: cancels the timer.
  - **Timer:** starts on the first tap after idle, and fires `flushNow` every
    `flushEvery` while `pending > 0`.
- **Produces, the live channel:** `class TasbihChannel({required SupabaseClient
  supabase, required String coupleId, required String selfId})`:
  - **Channel and payload:** channel `tasbih:<coupleId>`, event `tap`, payload
    `{'user_id': selfId, 'delta': n}`.
  - **`void tap()`:** accumulates, and sends at most once every 250 ms (a trailing
    send carries the remainder).
  - **`Stream<int> spouseDeltas`:** ignores its own `user_id`.
  - **Presence:** `channel.track({'user_id': selfId})` on subscribe.
    `Stream<bool> spouseHere` comes from presence sync (any presence whose `user_id
    != selfId`).
  - **`dispose`:** sends the remainder, then untrack and unsubscribe.
  - **Pattern:** modelled on `lib/features/chat/data/typing_channel.dart`.
- **Produces, the providers:**
  - `final tasbihRepositoryProvider`.
  - `final tasbihCountersProvider = StreamProvider<List<DhikrCounter>>`.
  - `final counterTotalsProvider = FutureProvider.family<CounterTotals, String>`.
- **Session screen:**
  - **Tap target:** a large circular target. Each tap triggers
    `HapticFeedback.selectionClick()`, then `batcher.tap()` and `channel.tap()`.
  - **Display:** `total = dbTotals.total (fetched on open) + mineSinceOpen +
    spouseDeltasSinceOpen`, as a `LinearProgressIndicator` against `target`, with the
    text "N / target". A presence dot labelled "<Spouse> is here".
  - **Saving:**
    - The batcher has `flushEvery: Duration(seconds: 5)`.
    - It is a `WidgetsBindingObserver`, and `didChangeAppLifecycleState(paused or
      inactive)` calls `flushNow()`.
    - `dispose` calls `flushNow()` and then disposes both.
    - The batcher's `save` calls `addContribution`.
  - **Goal reached:** when the displayed total first crosses `target`, it calls
    `insertBestEffort(kind:'tasbih', title:'Goal reached: <title>', body:'Together
    you reached <target>. Alhamdulillah.', route:'/home/tasbih')`, once per screen
    instance.
- **List screen:**
  - Each counter shows its title, Arabic, `LinearProgressIndicator` and "You N · <Spouse> M".
  - Pull to refresh invalidates `counterTotalsProvider`.
  - A FAB "New goal" opens a sheet:
    - Title (required).
    - Arabic (optional).
    - Target: an int > 0, with presets 33, 100, 1000.
    - Period, one of Daily, Weekly, Monthly or Once. Default Weekly.
  - **Empty state:** "Set a shared dhikr goal — like 1,000 salawat this week."

- [ ] **Step 1: Write the failing tests.**
  - **`tap_batcher_test`** (use `fakeAsync`):
    - 3 taps, then 5 s → `save(3)` once, and `pending == 0`.
    - When `save` throws: after 5 s `pending == 3`. The next successful flush saves 3
      plus any new taps (no loss).
    - `flushNow` with `pending == 0` doesn't call `save`.
    - `dispose` cancels the timer (no `save` after it).
  - **`tasbih_session_screen_test`** (fakes for the repository and channel):
    - With dbTotals mine 10 and spouse 5, target 20: 2 taps plus a spouse delta of 3
      shows "20 / 20", and the notification store gets one `'tasbih'` insert.
    - Sending `AppLifecycleState.paused` through `tester.binding.handleAppLifecycleStateChanged`
      makes the fake repository receive `addContribution(count: 2)`.
    - Popping the route with 1 pending tap saves 1.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/features/duas/tap_batcher_test.dart test/features/duas/tasbih_session_screen_test.dart`
  Expected: FAIL (compile).

- [ ] **Step 3: Implement it.** `TasbihChannel` is injected through a provider family,
  `tasbihChannelProvider(counterId)`, so tests can override it.

- [ ] **Step 4: Run the tests, plus `flutter analyze`.** Expected: PASS, no new issues.

- [ ] **Step 5: Commit** with the message
  `feat(duas): tasbih together with live taps and batched saves`.

---

### Task 7: Suggestions: mood check-in and the "Dua for you today" home card

**Files:**
- Create:
  - `lib/features/duas/domain/dua_suggestions.dart` (pure)
  - `lib/features/duas/data/mood_store.dart`
  - `lib/features/duas/domain/suggestion_providers.dart`
  - `lib/features/duas/presentation/dua_for_today_card.dart`
- Modify: `lib/features/home/presentation/home_screen.dart`: insert `const
  DuaForTodayCard()` right after `const VerseCard()` (around line 212), with the same
  spacing as its neighbours.
- Test:
  - `test/features/duas/dua_suggestions_test.dart`
  - `test/features/duas/dua_for_today_card_test.dart`

**Interfaces:**
- **Produces, the mood enum:** `enum Mood { grateful, anxious, sad, tired, unwell }`,
  with `String get label` ('Grateful', 'Anxious', 'Sad', 'Tired', 'Unwell').
- **Produces, the mood store:** `class MoodStore(FlutterSecureStorage)` with
  `Future<Mood?> read(String dayKey)` and `Future<void> write(String dayKey, Mood?)`.
  The key is `mood:<dayKey>`. Writing null deletes the key, and loading deletes other
  days' mood keys.
- **Produces, the suggestion model:** `class DuaSuggestion { LibraryDua dua; String
  reason; }`.
- **Produces, the rules function:** `List<DuaSuggestion> suggestDuas({Mood? mood,
  required DateTime today, required List<UpcomingEvent> events, required bool
  spouseAway, required List<LibraryDua> library, required String seed})`. Its rules:
  - **Library rows used:** only non-adhkar rows (`category ∉ adhkarCategories`).
  - **Triggers, in priority order.** Each produces `(tags, reason)`:
    1. **Calendar, today or tomorrow:**
       - A title matching `/travel|trip|flight|journey/i` → `['travel']`, "For the
         journey on <weekday>".
       - Kind `anniversary` → `['marriage']`, "For your anniversary".
       - Kind `birthday` → `['gratitude']`, "For <title>".
    2. **`spouseAway`** → `['protection','travel']`, "While you're apart".
    3. **Mood:**
       - anxious → `['distress','protection']`
       - sad → `['grief','distress']`
       - grateful → `['gratitude']`
       - unwell → `['illness','distress']`
       - tired → `['sleep','dhikr']`
       
       The reason is "Because you're feeling <label lowercase>".
    4. **Weekday:**
       - Friday → `['dhikr']`, "It's Jumu'ah — read Surah Al-Kahf and send salawat".
       - Monday or Thursday → `['fasting']`, "Monday & Thursday are Sunnah fasting
         days".
    5. **Fallback** → `['dhikr']`, "A dua for today".
  - **Picking:** for each trigger, the candidates are library rows whose `tags`
    intersect. A trigger with no candidates (or only already-chosen ones) is skipped
    without a reason. Pick index `fnv1a32('$seed|${dayKey(today)}|${tags.join(",")}') %
    candidates.length`, skipping duas already chosen.
  - **Result:** at most 3 distinct duas. An empty library gives `[]`.
  - `int fnv1a32(String s)`: the standard 32-bit FNV-1a over UTF-8, so the pick is the
    same on every platform.
- **Produces, the providers:**
  - `final todayMoodProvider = AsyncNotifierProvider<TodayMood, Mood?>`, with `set(Mood?)`.
    Today's key comes from `adhkarTodayKeyProvider` (Task 5).
  - `final duaSuggestionsProvider = Provider<List<DuaSuggestion>>`:
    - `library` comes from `duaLibraryProvider` (`[]` while loading).
    - `seed` is the own user id.
    - `spouseAway` is `spouse.timezone != own.timezone` (false if either is unknown).
    - `events` come from `upcomingEventsProvider`.
- **The card:**
  - A `LovCard` titled "A dua for you today", showing the first suggestion's title
    and reason, and a one-line translation preview. Tapping it calls
    `showLibraryDuaSheet` (Task 4).
  - Below it, a `Wrap` of 5 `ChoiceChip`s, one per Mood label. Tapping the selected
    one clears it.
  - A trailing text button "Tasbih together" → `/home/tasbih`.
  - The card renders `SizedBox.shrink()` when suggestions are empty.

- [ ] **Step 1: Write the failing tests** (`dua_suggestions_test`; the library
  fixtures each carry one of the rule tags):
  - Mood anxious on a Tuesday with no events → the first reason is "Because you're
    feeling anxious", and the dua has `distress` or `protection`.
  - A Friday with no mood → the first reason starts "It's Jumu'ah".
  - Monday → `fasting`.
  - An event titled "Flight to Dubai" tomorrow plus mood sad → the first suggestion is
    travel and the second is grief or distress.
  - An `anniversary` today → `marriage`.
  - `spouseAway: true` → "While you're apart".
  - With the same inputs, the result is identical across two calls (stable). With a
    different `today`, the result may differ (do not assert that it differs).
  - An empty library → `[]`.
  - Mood unwell with a library that has no `illness` tag but one `distress` row →
    that distress dua. Its reason is "Because you're feeling unwell".
  - It never returns an adhkar-category dua, and never more than 3.
  - `fnv1a32('a') == 0xE40C292C`.
  - **`dua_for_today_card_test`:**
    - An empty suggestion list renders nothing.
    - Tapping "Anxious" calls the fake `MoodStore.write(<todayKey>, Mood.anxious)`,
      and the card re-renders with the anxious reason.
    - Tapping it again writes null.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `flutter test test/features/duas/dua_suggestions_test.dart test/features/duas/dua_for_today_card_test.dart`
  Expected: FAIL (compile).

- [ ] **Step 3: Implement it.**

- [ ] **Step 4: Run the full suite.**
  1. `flutter test --concurrency=1`. Expected: all PASS.
  2. `flutter analyze`. Expected: no new issues.
  3. Run all `supabase/tests/*.sql`. Expected: all PASS.

- [ ] **Step 5: Commit** with the message
  `feat(duas): mood/weekday/calendar dua suggestions on home`.
