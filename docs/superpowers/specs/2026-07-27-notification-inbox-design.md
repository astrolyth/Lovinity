# Lovinity — In-App Notification Inbox

**Date:** 2026-07-27
**Status:** Design approved
**Builds on:** E2E text chat, floating chat button + unread badge, push notifications (phase 1)

## Summary

A persisted, on-device notification inbox surfacing your partner's activity — new
messages/reactions, pairing, prayer check-ins, and shared cycle updates — as a
real scrollable list, not just an unread count. This exists independently of OS
push (which stays content-free and iOS/Android-only): the inbox is a local
activity log, built entirely from data the app already has locally or can read
under existing RLS.

## Why

Today the only signal of partner activity is the unread-count badge on the
floating chat button (`lib/features/home/presentation/home_screen.dart:437`) —
there is nowhere to see *what* happened, only that something is unread, and
only for chat. There is no record of past notifications at all.

## Scope

**In scope (v1):** chat messages + reactions, pairing (couple becomes active),
prayer log check-ins, shared cycle updates.

**Explicitly out of scope:** a "care" activity feed — `CareRepository` is
static, read-only tip content today (fetched by audience), not something one
partner shares with the other. Notifying on it would require designing and
building a care-sharing feature first; that's a separate project.

## Data model

New Drift table added to `SignalDb` (`lib/core/storage/signal_db.dart`) — the
same local database chat already uses, not a new database:

```dart
class Notifications extends Table {
  TextColumn get id => text()();              // uuid, client-generated
  TextColumn get kind => text()();             // 'message' | 'reaction' | 'pairing' | 'prayer' | 'cycle'
  TextColumn get title => text()();            // e.g. "New message from Amina"
  TextColumn get body => text().nullable()();  // e.g. the message preview text
  TextColumn get route => text()();            // deep-link target, e.g. '/home/chat'
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Rationale for reusing `SignalDb` rather than a new database: `SignalDb.wipeAll()`
already clears all chat + Signal tables on account-switch
(`lib/core/crypto/signal_registration.dart:126`, `guardAccountSwitch`) — the
fix for a real prior leak where a new account signing in on a shared device
saw the previous account's data. A separate database would need to
independently reimplement that same wipe, and a missed call would silently
reintroduce the leak for notifications specifically. Adding the table to
`SignalDb` means `wipeAll()` covers it automatically; `wipeAll()` is extended
to `delete(notifications)` alongside the existing table deletes.

## Components

### 1. `NotificationStore` (`lib/core/notifications/notification_store.dart`)

Mirrors `ChatStore`'s shape, wrapping the `Notifications` table:

- `Future<void> insert({required kind, required title, body, required route})` — generates the id/createdAt, `readAt` starts null.
- `Stream<List<NotificationRow>> watchAll()` — newest first.
- `Stream<int> watchUnreadCount()`.
- `Future<void> markRead(String id)`.
- `Future<void> markAllRead()`.

### 2. Event sources → `NotificationStore.insert`

All four writes are **best-effort** (try/catch, swallow) — a notification-write
failure must never break the feature it's observing. Same posture as
`ChatService.sendReaction`'s existing error handling.

- **Chat** — `ChatService._handleInboxRow` (`lib/features/chat/domain/chat_service.dart`),
  in the `TextPayload`/`ReactionPayload` branches, when `senderId != selfUserId`:
  insert `kind: 'message'`/`'reaction'`, `body` is the real decrypted preview
  text (safe — this is on-device only, same trust boundary as the existing
  `chat_messages` table; never transmitted), `route: '/home/chat'`.
- **Pairing** — a new `pairingNotifierProvider`-adjacent listener on
  `currentCoupleProvider` (`lib/features/pairing/domain/pairing_providers.dart`)
  that detects the transition into `status == 'active'` and inserts
  `kind: 'pairing'`, `route: '/home'`.
- **Prayer log** — a new watcher diffing `PrayerLogRepository.watchDay`
  (`lib/features/prayer_log/data/prayer_log_repository.dart`) against the
  last-seen snapshot of row ids; a newly-appeared row with `user_id != self`
  inserts `kind: 'prayer'`, `route: '/home/prayer'`. Never fires for rows
  present on the very first emission (that's existing history, not new
  activity) or for the user's own check-ins.
- **Cycle** — new `CycleRepository.watchCoupleShared({required coupleId})`
  method: `.from('cycle_records').stream(primaryKey: ['id']).eq('couple_id', coupleId)`.
  RLS (`supabase/migrations/20260715000002_cycle_rls.sql`) already restricts
  what this returns to the caller's own rows plus the partner's
  `visibility = 'shared'` rows — a private partner row is never returned at
  the database layer. The same new-row diffing as prayer log applies, filtered
  additionally to `userId != self && visibility == 'shared'` client-side as a
  second check. Inserts `kind: 'cycle'`, `route: '/home/cycle'`, with
  deliberately non-clinical wording (e.g. "Your partner shared a cycle
  update").

### 3. `unreadNotificationCountProvider` (`StreamProvider<int>`)

Wraps `NotificationStore.watchUnreadCount()`, `0` when signed out — same
pattern as `unreadChatCountProvider`.

### 4. Home screen bell icon

Next to the existing Settings `IconButton` in `HomeScreen`
(`lib/features/home/presentation/home_screen.dart`): a bell `IconButton`
wrapped in `Badge` (same `Badge`/count-capping treatment as the chat FAB),
navigating to a new route.

### 5. `NotificationsScreen` (`lib/features/notifications/presentation/notifications_screen.dart`)

New route `/home/notifications`. Lists `NotificationStore.watchAll()`, newest
first, unread rows visually distinguished. On mount, calls
`markAllRead()` (matches the "opening the screen marks them read" decision).
Tapping a row navigates to its `route`.

## Data flow

Partner activity (chat envelope decrypted / couple flips to active / prayer
row appears / shared cycle row appears) → the relevant event source calls
`NotificationStore.insert` → `NotificationsScreen` (via `watchAll()`) and the
home bell badge (via `unreadNotificationCountProvider`) update live, the same
way `watchUnreadCount` already drives the chat FAB badge today.

## Error handling

- Every `NotificationStore.insert` call site is wrapped so a failure never
  propagates into the feature being observed (chat still decrypts/displays,
  prayer/cycle streams keep working) — consistent with `sendReaction`'s
  existing best-effort pattern.
- `markRead`/`markAllRead` failures are non-fatal; retried next time the
  screen opens (same posture as chat's server-side `markRead`).

## Testing

- `NotificationStore`: insert/watchAll ordering, `watchUnreadCount`,
  `markRead`, `markAllRead` — same test shape as `chat_store_test.dart`.
- Prayer/cycle diff logic: pure-function tests — two snapshots in, asserting
  a notification fires only for a genuinely new partner row, never for the
  first emission (existing history) and never for the user's own rows; cycle
  additionally never fires for `visibility: 'private'`.
- Chat: a spouse `TextPayload`/`ReactionPayload` through `_handleInboxRow`
  results in one `NotificationStore.insert` call with the right preview/kind;
  a self-authored (own-device-sync) message does not.
- Pairing: `currentCoupleProvider` transitioning to `active` triggers exactly
  one insert (not on every subsequent emission while already active).
- `SignalDb.wipeAll()`: extended test asserting `notifications` rows are
  cleared on account-switch, matching the existing chat-tables wipe test.
- Widget: `NotificationsScreen` renders the list, marks-read on open; bell
  badge shows/hides per unread count.

## Out of scope

- OS push notifications on macOS (explicitly deferred — this inbox is the
  chosen alternative for now).
- A care-sharing feature (see Scope above).
- Notification preferences/muting per category.
- Cross-device sync of read state (read state is local-device only, same as
  everything else in `SignalDb`).
