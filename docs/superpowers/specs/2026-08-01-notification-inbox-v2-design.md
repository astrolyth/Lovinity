# Lovinity — In-App Notification Inbox v2 (amends 2026-07-27 design)

**Date:** 2026-08-01
**Status:** Design approved
**Amends:** `docs/superpowers/specs/2026-07-27-notification-inbox-design.md` — that
design was written and approved but never implemented (only
`push_service.dart`/`notification_providers.dart`'s `pushServiceProvider`
exist in code). This spec carries its architecture forward with a scope
change and three additions, described below.

## What changed from the 2026-07-27 design

1. **Chat messages/reactions are removed from the bell inbox entirely.**
   The original design's Task 4 wrote a bell notification for every spouse
   chat message/reaction. Product decision: chat already has its own unread
   signal (the floating chat button's badge, `unreadChatCountProvider`) and
   the message/reaction itself is visible the moment you open chat — showing
   it a second time in the bell is redundant. Chat continues to notify
   exactly as it does today (chat bubble + FAB badge) and never writes to
   `AppNotifications`.
2. **Three sources added:** daily question answers, shared duas, and
   gratitude notes (the last pairs with a real fix — see below).
3. **Schema version bump changes.** The original design assumed
   `SignalDb.schemaVersion` was at 3, bumping to 4. Since then, unrelated
   work (chat photo/video attachments) already took version 4. This design
   bumps to **5**.
4. **A real pre-existing bug found and fixed alongside the gratitude
   source**, described below — not something the original design could have
   known about, since gratitude wasn't in its scope.

## Scope

**In scope (v2):** pairing (couple becomes active), prayer log check-ins,
shared cycle updates, daily question answers, shared duas, gratitude notes
(revealed only).

**Explicitly out of scope:** chat messages/reactions (see above — has its
own signal already). A "care" activity feed (`CareRepository` is static,
read-only tip content, not partner-authored — unchanged conclusion from the
original spec). Scoring (`ScoreboardRepository` has no independent stream —
it's a computed view over prayer check-ins and other already-covered
sources; nothing new to notify on there).

## Gratitude: a real bug found during scoping, fixed here

`GratitudeRepository.watchAll` (`lib/features/gratitude/data/gratitude_repository.dart`)
streams **every** `gratitude_notes` row for the couple, with no filter on
`reveal_to_spouse`. The "private until revealed" behavior
(`gratitude_screen.dart`'s `_NoteTile`, `hidden = !isOwn && !note.revealToSpouse`)
is enforced only by the widget choosing not to *render* `note.body` — the
raw text of a partner's still-private note is already delivered to the
partner's device today. This is the same class of leak the cycle feature's
dedicated RLS migration (`20260715000002_cycle_rls.sql`) was built to
prevent; gratitude never got the equivalent treatment (the table's RLS is
still just the blanket `couple_id` policy from
`20260712000002_full_schema.sql`'s generic per-table loop).

**Fix:** `watchAll` gains a required `selfUserId` parameter and filters
server-side to rows where `author_id = selfUserId OR reveal_to_spouse =
true` (a Supabase `.or(...)` filter — no RLS/migration change needed, since
`is_couple_member` already permits the couple to read the table; this is a
query-shape fix, not a permissions fix). `gratitude_providers.dart`'s
`gratitudeNotesProvider` passes the signed-in user's id. Consequence (a
correct, expected side effect of the fix, not a regression): a partner's
not-yet-revealed note no longer appears in the list at all — previously it
appeared as a "Kept for now." placeholder row hinting a note exists; now
there's no evidence of an unrevealed note whatsoever, which is what
"private until revealed" is actually supposed to mean. `_NoteTile`'s
`hidden`/lock-icon rendering path becomes dead code for the partner's own
notes case (it can no longer receive a partner row with `revealToSpouse:
false`) but is left in place — it still correctly handles the ordering
edge case where a realtime delta briefly includes a row the client hasn't
re-filtered yet, and removing it is not required to fix the leak.

The gratitude **notification** itself piggybacks on this fix for free: once
`watchAll` only ever returns a partner row at the moment it's visible
(created-and-revealed immediately, or revealed later), the standard
`newRowDetector` diff pattern already used for prayer/cycle fires exactly
once, exactly when a partner's note first becomes visible to you — which is
precisely "revealed," with no separate reveal-transition tracking needed.

## Data model

Unchanged from the original design, restated for completeness. New Drift
table in `SignalDb` (`lib/core/storage/signal_db.dart`):

```dart
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'pairing'|'prayer'|'cycle'|'question'|'dua'|'gratitude'
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  TextColumn get route => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Named `AppNotifications` (not `Notifications`) to avoid colliding with
`package:flutter/widgets.dart`'s own `Notification` class. `wipeAll()`
clears it, same as every other table (already-covered account-switch leak
protection).

## Components (unchanged shape from the original design)

- `NotificationStore` (`lib/core/notifications/notification_store.dart`):
  `insert`/`watchAll`/`watchUnreadCount`/`markRead`/`markAllRead`.
- `newRowDetector<T>`/`pairingJustActivated` pure helpers
  (`lib/core/notifications/activity_detectors.dart`).
- Six **best-effort** pump providers (try/catch swallow around every
  `insert` — a notification-write failure must never break the feature it's
  observing): pairing, prayer, cycle (all as originally designed), plus
  **daily question, duas, gratitude** (new, this design):
  - **Daily question** — a new `questionNotificationPumpProvider` reusing
    the *existing* `questionAnswersProvider`
    (`lib/features/daily/domain/question_providers.dart`, already a live
    stream of today's `QuestionAnswer` rows for the couple — no repository
    change needed). Diffs by `authorId`, fires for `authorId != self`.
    `kind: 'question'`, `route: '/home/question'`.
  - **Duas** — a new `duaNotificationPumpProvider` over the existing
    `DuaRepository.watch(coupleId)`. Diffs by `id`, fires for `authorId !=
    self && visibility == 'shared'` (client-side filter as defense in
    depth, matching the cycle pump's existing posture — `watch` itself is
    not modified, since a private dua's mere existence isn't the same class
    of leak gratitude has: the repository already returns all rows to
    support the owner managing their own private ones, and this pump simply
    declines to notify on them). `kind: 'dua'`, `route: '/home/duas'`.
  - **Gratitude** — a new `gratitudeNotificationPumpProvider` over the
    *fixed* `GratitudeRepository.watchAll`. Diffs by `id`, fires for
    `authorId != self` (the query fix already guarantees only-visible rows
    reach this point, so no extra `revealToSpouse` check is needed here —
    though the pump still reads `revealToSpouse` for clarity, since a
    self-authored note's own reveal state is irrelevant, only partner rows
    matter). `kind: 'gratitude'`, `route: '/home/gratitude'`.
- `unreadNotificationCountProvider` (`StreamProvider<int>`).
- Home screen bell `IconButton` + `Badge`, next to the existing Settings
  button.
- `NotificationsScreen` at `/home/notifications`.

## Testing (adds to the original design's list)

- `GratitudeRepository.watchAll`: a repository-level test (or, since this
  repo talks straight to Supabase with no seam, an integration test
  matching this codebase's existing `_pairCouple`-based integration test
  pattern) asserting a partner's unrevealed note is absent from the stream
  and a revealed one is present.
- Daily/duas/gratitude pumps: same pure-diff-logic test shape as the
  prayer/cycle pumps (two snapshots in, notification fires only for a
  genuinely new, own-excluded, visibility-appropriate row).

## Out of scope (unchanged)

OS push notifications on macOS, a care-sharing feature, notification
preferences/muting per category, cross-device sync of read state.
