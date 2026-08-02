# In-App Notification Inbox v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persisted, on-device notification inbox (bell icon + screen) surfacing partner activity — pairing, prayer check-ins, shared cycle updates, daily question answers, shared duas, and revealed gratitude notes. Chat messages/reactions are deliberately excluded (they already have their own unread badge on the chat button) and never write here.

**Architecture:** A new `AppNotifications` Drift table lives in the existing `SignalDb` (the same local database chat already uses, so it's covered by the existing account-switch wipe). A `NotificationStore` wraps it. Six independent best-effort pump providers each diff a Supabase realtime/stream snapshot against its previous emission to detect genuinely-new partner activity, and write into the store. A bell icon + badge on the home screen opens a new `/home/notifications` screen. Along the way, a real pre-existing privacy bug in `GratitudeRepository.watchAll` (streams a partner's still-private note body to the client) is fixed as a prerequisite for the gratitude source.

**Tech Stack:** Flutter, Riverpod, Drift (existing `SignalDb`), Supabase realtime streams (existing + one new repository method's worth), go_router.

## Global Constraints

- Every notification-write call site is best-effort: wrapped so a failure can never break the feature it observes (matches `ChatService.sendReaction`'s existing swallow-and-continue pattern).
- The `AppNotifications` table (not `Notifications`) — Drift would otherwise generate a row class literally named `Notification`, which collides with `package:flutter/widgets.dart`'s own `Notification` class wherever both are imported. Keep this name throughout.
- Chat messages/reactions never write to `AppNotifications` — do not add a chat event source. This is a deliberate scope exclusion, not an oversight.
- Cycle and duas notifications only ever fire for `visibility == 'shared'` records, checked client-side even though RLS/the query shape already enforces it (defense in depth, matches the original spec's posture for cycle).
- Gratitude notifications rely on `GratitudeRepository.watchAll`'s query-level fix (Task 10) to only ever receive a partner row once it's genuinely visible — do not add a redundant `revealToSpouse` filter as the *only* guard; the query fix is the actual guarantee.
- `SignalDb.wipeAll()` must clear `appNotifications` too — same cross-account-leak protection every other table already has.
- `SignalDb.schemaVersion` is currently `4` (bumped by unrelated prior work). This plan bumps it to `5` — do not reuse `4`.
- Match existing patterns: Riverpod `Provider`/`StreamProvider`, repository pattern, Drift table conventions, best-effort error swallowing. No new state-management or database libraries.
- `flutter analyze` must stay clean and `flutter test` must stay green after every task.

---

### Task 1: `AppNotifications` table in `SignalDb`

**Files:**
- Modify: `lib/core/storage/signal_db.dart`
- Modify: `test/core/storage/signal_db_test.dart` (currently one test, `'stores and reads a session row'`; add the new test into its `main()` block, don't replace the existing one)

**Interfaces:**
- Produces: `AppNotifications` Drift table (fields: `id` text pk, `kind` text, `title` text, `body` text nullable, `route` text, `createdAt` datetime, `readAt` datetime nullable, `seq` int) and its generated `AppNotification` row class / `AppNotificationsCompanion`. `SignalDb.wipeAll()` now also clears it. `SignalDb.schemaVersion` is `5`.

**Note on `seq`:** a prior implementation attempt of this same feature (on an abandoned branch) shipped this table without `seq`, then needed two follow-up fixes: Drift's `DateTimeColumn` maps to SQL with only *second* precision, so two notifications inserted within the same second sorted non-deterministically under a plain `ORDER BY createdAt DESC`; the first fix added a monotonic `seq` column computed as `max(seq) + 1` per insert, but that read-then-insert was itself racy under concurrent callers (two inserts could read the same max and collide). Build the table with `seq` from the start (below) and give `NotificationStore.insert` (Task 2) the transaction-wrapped atomic version directly — do not ship the naive version and rediscover these two bugs.

- [ ] **Step 1: Add the table to `lib/core/storage/signal_db.dart`**

Add this class after `ChatReactions`:

```dart
/// Persisted local activity feed: pairing, prayer check-ins, shared cycle
/// updates, daily question answers, shared duas, and revealed gratitude
/// notes (see docs/superpowers/specs/2026-08-01-notification-inbox-v2-design.md).
/// Deliberately excludes chat messages/reactions -- those already have their
/// own unread badge on the chat button. Named `AppNotifications`, not
/// `Notifications` -- Drift would otherwise generate a row class literally
/// called `Notification`, colliding with `package:flutter/widgets.dart`'s own
/// `Notification` class wherever this table and Flutter widgets are imported
/// together.
///
/// Uses `seq` as a monotonic insertion sequence number to provide stable
/// ordering among notifications created in the same second (Drift's
/// DateTimeColumn maps to second-precision SQL, not millisecond precision) --
/// see `NotificationStore.insert`/`watchAll` (Task 2) for how it's used.
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'pairing'|'prayer'|'cycle'|'question'|'dua'|'gratitude'
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  TextColumn get route => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();
  IntColumn get seq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
```

Update the `@DriftDatabase` annotation to include it:

```dart
@DriftDatabase(tables: [
  SignalSessions,
  SignalPrekeys,
  SignalSignedPrekeys,
  SignalIdentities,
  SignalIdentityChanges,
  SignalMeta,
  ChatMessages,
  ChatReactions,
  AppNotifications,
])
```

Bump the schema version and add the migration step. The current file has
`schemaVersion => 4` and an `onUpgrade` ending with an `if (from < 4) { ... }`
block (attachment columns) — leave that block exactly as-is and add a new
`if (from < 5)` block after it:

```dart
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(signalMeta);
          if (from < 3) {
            await m.createTable(chatMessages);
            await m.createTable(chatReactions);
          }
          if (from < 4) {
            await m.addColumn(chatMessages, chatMessages.attachmentKind);
            await m.addColumn(chatMessages, chatMessages.mimeType);
            await m.addColumn(chatMessages, chatMessages.sizeBytes);
            await m.addColumn(chatMessages, chatMessages.width);
            await m.addColumn(chatMessages, chatMessages.height);
            await m.addColumn(chatMessages, chatMessages.durationMs);
            await m.addColumn(chatMessages, chatMessages.storageKey);
            await m.addColumn(chatMessages, chatMessages.encKey);
            await m.addColumn(chatMessages, chatMessages.nonce);
            await m.addColumn(chatMessages, chatMessages.thumbnailBytes);
            await m.addColumn(chatMessages, chatMessages.localMediaPath);
            await m.addColumn(chatMessages, chatMessages.downloadStatus);
          }
          if (from < 5) await m.createTable(appNotifications);
        },
      );
```

(Keep whatever the `if (from < 4)` block's exact existing column list is —
the above reproduces it for context; do not alter it. Only add the new
`if (from < 5)` line.)

Add the delete to `wipeAll()` (find the existing method and add one line):

```dart
  Future<void> wipeAll() async {
    await transaction(() async {
      await delete(chatMessages).go();
      await delete(chatReactions).go();
      await delete(appNotifications).go();
      await delete(signalSessions).go();
      await delete(signalPrekeys).go();
      await delete(signalSignedPrekeys).go();
      await delete(signalIdentities).go();
      await delete(signalIdentityChanges).go();
      await delete(signalMeta).go();
    });
  }
```

- [ ] **Step 2: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes without error; `lib/core/storage/signal_db.g.dart` is rewritten and now defines `AppNotification`, `AppNotificationsCompanion`, and an `appNotifications` table getter on `_$SignalDb`.

- [ ] **Step 3: Add the wipe test**

Add a second test into `test/core/storage/signal_db_test.dart`'s existing `main()` block — do not replace the existing test. Add `import 'dart:typed_data';` if not already present (the existing test uses `Uint8List`, so it should already be there):

```dart
  test('wipeAll clears appNotifications along with chat/signal tables', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);

    await db.into(db.appNotifications).insert(
          AppNotificationsCompanion.insert(
            id: 'n1',
            kind: 'pairing',
            title: "You're connected",
            route: '/home',
            createdAt: DateTime(2026),
          ),
        );
    expect(await db.select(db.appNotifications).get(), hasLength(1));

    await db.wipeAll();

    expect(await db.select(db.appNotifications).get(), isEmpty);
  });
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/core/storage/signal_db_test.dart`
Expected: PASS, 2 tests (the pre-existing one plus the new wipe test).

- [ ] **Step 5: Run the full non-integration suite**

Run: `flutter test --exclude-tags integration`
Expected: PASS — the schema bump/migration addition must not break anything relying on `SignalDb` (chat, etc.).

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart test/core/storage/signal_db_test.dart
git commit -m "feat(notifications): add AppNotifications table to SignalDb (schema v5), wired into wipeAll"
```

---

### Task 2: `NotificationStore`

**Files:**
- Create: `lib/core/notifications/notification_store.dart`
- Test: `test/core/notifications/notification_store_test.dart`

**Interfaces:**
- Consumes: `SignalDb` (Task 1), specifically `db.appNotifications`, `AppNotificationsCompanion`.
- Produces: `NotificationRow` (typedef for `AppNotification`), `NotificationStore` with:
  - `Future<void> insert({required String kind, required String title, String? body, required String route})`
  - `Stream<List<NotificationRow>> watchAll()`
  - `Stream<int> watchUnreadCount()`
  - `Future<void> markRead(String id)`
  - `Future<void> markAllRead()`

- [ ] **Step 1: Write the failing test**

Create `test/core/notifications/notification_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late NotificationStore store;
  setUp(() {
    db = SignalDb.memory();
    store = NotificationStore(db);
  });
  tearDown(() => db.close());

  test('insert then watchAll returns newest first, deterministically even within the same second',
      () async {
    // No artificial delay between inserts: two notifications created in the
    // same wall-clock second must still order deterministically via `seq`,
    // not by relying on createdAt happening to differ (Drift's
    // DateTimeColumn is second-precision, not millisecond).
    await store.insert(
        kind: 'pairing', title: 'first', body: 'a', route: '/home');
    await store.insert(
        kind: 'prayer', title: 'second', body: 'b', route: '/home/prayer');

    final rows = await store.watchAll().first;
    expect(rows.map((r) => r.title).toList(), ['second', 'first']);
  });

  test('concurrent inserts never collide on seq (no duplicate ordering position)',
      () async {
    // Regression test for a real race: reading max(seq) then inserting is
    // only safe if serialized. Firing several inserts concurrently (not
    // awaited one at a time) must still produce N distinct, correctly
    // ordered rows -- if the transaction wrapping were missing, two of these
    // could read the same max(seq) and collide.
    await Future.wait([
      store.insert(kind: 'prayer', title: 'a', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'b', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'c', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'd', route: '/home/prayer'),
      store.insert(kind: 'prayer', title: 'e', route: '/home/prayer'),
    ]);

    final rows = await store.watchAll().first;
    expect(rows, hasLength(5));
    expect(rows.map((r) => r.title).toSet(), {'a', 'b', 'c', 'd', 'e'});
  });

  test('watchUnreadCount counts unread; markRead clears one; markAllRead clears all',
      () async {
    await store.insert(kind: 'prayer', title: 'a', route: '/home/prayer');
    await store.insert(kind: 'prayer', title: 'b', route: '/home/prayer');
    expect(await store.watchUnreadCount().first, 2);

    final firstId = (await store.watchAll().first)
        .firstWhere((r) => r.title == 'a')
        .id;
    await store.markRead(firstId);
    expect(await store.watchUnreadCount().first, 1);

    await store.markAllRead();
    expect(await store.watchUnreadCount().first, 0);
  });

  test('insert persists kind/title/body/route exactly', () async {
    await store.insert(
      kind: 'pairing',
      title: "You're connected",
      body: null,
      route: '/home',
    );
    final row = (await store.watchAll().first).single;
    expect(row.kind, 'pairing');
    expect(row.title, "You're connected");
    expect(row.body, isNull);
    expect(row.route, '/home');
    expect(row.readAt, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/notifications/notification_store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:lovinity/core/notifications/notification_store.dart'`

- [ ] **Step 3: Implement `NotificationStore`**

Create `lib/core/notifications/notification_store.dart`:

```dart
// lib/core/notifications/notification_store.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../storage/signal_db.dart';

typedef NotificationRow = AppNotification;

class NotificationStore {
  NotificationStore(this._db);
  final SignalDb _db;

  /// Wrapped in a transaction so the "read max(seq), then insert" pair is
  /// atomic -- without this, two concurrent inserts could both read the same
  /// max and write the same `seq`, reintroducing the same-second ordering
  /// tie this column exists to prevent.
  Future<void> insert({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) async {
    await _db.transaction(() async {
      final maxSeqExpr = _db.appNotifications.seq.max();
      final result = await (_db.selectOnly(_db.appNotifications)
            ..addColumns([maxSeqExpr]))
          .getSingleOrNull();
      final maxSeq = result?.read(maxSeqExpr) ?? 0;
      final nextSeq = maxSeq + 1;

      await _db.into(_db.appNotifications).insert(
            AppNotificationsCompanion.insert(
              id: const Uuid().v4(),
              kind: kind,
              title: title,
              body: Value(body),
              route: route,
              createdAt: DateTime.now(),
              seq: Value(nextSeq),
            ),
          );
    });
  }

  Stream<List<NotificationRow>> watchAll() {
    return (_db.select(_db.appNotifications)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.seq),
          ]))
        .watch();
  }

  Stream<int> watchUnreadCount() {
    final count = _db.appNotifications.id.count();
    final q = _db.selectOnly(_db.appNotifications)
      ..addColumns([count])
      ..where(_db.appNotifications.readAt.isNull());
    return q.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<void> markRead(String id) {
    return (_db.update(_db.appNotifications)..where((t) => t.id.equals(id)))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> markAllRead() {
    return (_db.update(_db.appNotifications)
          ..where((t) => t.readAt.isNull()))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/notifications/notification_store_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/notifications/notification_store.dart test/core/notifications/notification_store_test.dart
git commit -m "feat(notifications): add NotificationStore over AppNotifications, with atomic seq ordering"
```

---

### Task 3: Riverpod providers for the store

**Files:**
- Modify: `lib/core/notifications/notification_providers.dart`

**Interfaces:**
- Consumes: `NotificationStore` (Task 2), `signalDbProvider` (from `lib/core/crypto/crypto_providers.dart`), `authSessionProvider` (from `lib/features/auth/domain/auth_controller.dart`).
- Produces: `notificationStoreProvider` (`Provider<NotificationStore>`), `unreadNotificationCountProvider` (`StreamProvider<int>`), `notificationsListProvider` (`StreamProvider<List<NotificationRow>>`).

- [ ] **Step 1: Add the providers**

`lib/core/notifications/notification_providers.dart` currently only has `pushServiceProvider`. Replace its full contents with:

```dart
// lib/core/notifications/notification_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../crypto/crypto_providers.dart';
import 'notification_store.dart';
import 'push_service.dart';

/// Singleton [PushService] for the app. Constructing it does nothing
/// Firebase-related by itself (`init()` is what actually touches Firebase,
/// and is fully guarded).
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});

/// Singleton [NotificationStore] over the same local DB chat uses, so it's
/// covered by the same account-switch wipe (`SignalDb.wipeAll()`).
final notificationStoreProvider = Provider<NotificationStore>((ref) {
  return NotificationStore(ref.watch(signalDbProvider));
});

/// Live count of unread in-app notifications, for the home bell badge.
/// Emits 0 when signed out.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return Stream.value(0);
  return ref.watch(notificationStoreProvider).watchUnreadCount();
});

/// Full notification history, newest first, for the notifications screen.
final notificationsListProvider =
    StreamProvider<List<NotificationRow>>((ref) {
  return ref.watch(notificationStoreProvider).watchAll();
});
```

Note: `crypto_providers.dart` already imports this same file (for `pushServiceProvider`), so this creates a two-file import cycle. That's fine in Dart (regular `import` cycles, as opposed to `part of` cycles, are supported) and this codebase already relies on it in the other direction — confirm with `flutter analyze` in Step 2.

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/notifications/notification_providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/notifications/notification_providers.dart
git commit -m "feat(notifications): add notification store/count/list providers"
```

---

### Task 4: Shared partner-activity diff helpers

**Files:**
- Create: `lib/core/notifications/activity_detectors.dart`
- Test: `test/core/notifications/activity_detectors_test.dart`

**Interfaces:**
- Produces:
  - `void Function(List<T> rows) newRowDetector<T>({required String Function(T row) keyOf, required void Function(T row) onNew})`
  - `bool pairingJustActivated(String? previousStatus, String? nextStatus)`

These are pure functions (no Riverpod, no Drift) used by every pump provider in Tasks 5-10.

- [ ] **Step 1: Write the failing tests**

Create `test/core/notifications/activity_detectors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/activity_detectors.dart';

void main() {
  group('newRowDetector', () {
    test('never fires on the first emission (existing history, not new activity)', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']);
      expect(fired, isEmpty);
    });

    test('fires only for keys new since the previous emission', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']); // baseline, no fire
      detector(['a', 'b', 'c']); // c is new
      expect(fired, ['c']);
    });

    test('a removed-then-readded key fires again', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a']);
      detector([]); // a removed
      detector(['a']); // a reappears
      expect(fired, ['a']);
    });

    test('unrelated churn with no new keys does not fire', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']);
      detector(['b', 'a']); // same set, different order
      expect(fired, isEmpty);
    });
  });

  group('pairingJustActivated', () {
    test('null -> active is a fresh pairing', () {
      expect(pairingJustActivated(null, 'active'), isTrue);
    });

    test('pending -> active is a fresh pairing', () {
      expect(pairingJustActivated('pending', 'active'), isTrue);
    });

    test('active -> active does not refire', () {
      expect(pairingJustActivated('active', 'active'), isFalse);
    });

    test('active -> null does not fire', () {
      expect(pairingJustActivated('active', null), isFalse);
    });

    test('null -> null does not fire', () {
      expect(pairingJustActivated(null, null), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/notifications/activity_detectors_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:lovinity/core/notifications/activity_detectors.dart'`

- [ ] **Step 3: Implement the helpers**

Create `lib/core/notifications/activity_detectors.dart`:

```dart
// lib/core/notifications/activity_detectors.dart
//
// Pure helpers that turn a Supabase realtime stream's "full snapshot on
// every change" emissions into partner-activity notifications, without a
// server-side event feed. No Riverpod/Drift dependency so they're testable
// in isolation; see docs/superpowers/specs/2026-08-01-notification-inbox-v2-design.md.

/// Returns a stream-listener callback that invokes [onNew] once for every
/// element present in a new emission that wasn't present in the previous
/// one (keyed by [keyOf]). Never fires on the very first emission -- that's
/// existing state the stream loads on subscribe, not new activity.
void Function(List<T> rows) newRowDetector<T>({
  required String Function(T row) keyOf,
  required void Function(T row) onNew,
}) {
  Set<String>? previousKeys;
  return (rows) {
    final current = {for (final row in rows) keyOf(row): row};
    if (previousKeys != null) {
      for (final entry in current.entries) {
        if (!previousKeys!.contains(entry.key)) onNew(entry.value);
      }
    }
    previousKeys = current.keys.toSet();
  };
}

/// True when pairing just became active -- [previousStatus] was not
/// `'active'` and [nextStatus] is. Pass `couple?.status` at each stream
/// emission (null when unpaired/no couple row yet).
bool pairingJustActivated(String? previousStatus, String? nextStatus) {
  final wasActive = previousStatus == 'active';
  final isActive = nextStatus == 'active';
  return !wasActive && isActive;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/notifications/activity_detectors_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/notifications/activity_detectors.dart test/core/notifications/activity_detectors_test.dart
git commit -m "feat(notifications): add pure partner-activity diff helpers"
```

---

### Task 5: Pairing pump

**Files:**
- Modify: `lib/features/pairing/domain/pairing_providers.dart`

**Interfaces:**
- Consumes: `pairingJustActivated` (Task 4), `notificationStoreProvider` (Task 3), `pairingRepositoryProvider.watchCurrentCouple` (existing), `authSessionProvider` (existing).
- Produces: `pairingNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

- [ ] **Step 1: Add the provider**

In `lib/features/pairing/domain/pairing_providers.dart`, add imports:

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
```

Append this provider at the end of the file:

```dart
/// Writes a "You're connected" notification the moment pairing becomes
/// active. Mirrors the `inboxPumpProvider`/`receiptPumpProvider` shape in
/// chat_providers.dart: a Provider<void> that owns a raw stream
/// subscription rather than composing StreamProviders, so it can track the
/// previous emission itself. Watched once from HomeScreen.
final pairingNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  String? previousStatus;
  final sub = ref
      .read(pairingRepositoryProvider)
      .watchCurrentCouple(selfId)
      .listen((couple) {
    if (pairingJustActivated(previousStatus, couple?.status)) {
      unawaited(store.insert(
        kind: 'pairing',
        title: "You're connected",
        body: 'You and your partner are now paired 💛',
        route: '/home',
      ));
    }
    previousStatus = couple?.status;
  });
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/pairing/`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/pairing/domain/pairing_providers.dart
git commit -m "feat(notifications): pairing-activated notification pump"
```

---

### Task 6: Prayer log pump

**Files:**
- Modify: `lib/features/prayer_log/domain/prayer_log_providers.dart`

**Interfaces:**
- Consumes: `newRowDetector` (Task 4), `notificationStoreProvider` (Task 3), `prayerLogRepositoryProvider.watchDay` (existing), `currentCoupleProvider`/`authSessionProvider` (existing).
- Produces: `prayerNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

- [ ] **Step 1: Add the provider**

In `lib/features/prayer_log/domain/prayer_log_providers.dart`, add imports:

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
```

Append this provider at the end of the file:

```dart
/// Writes a notification when the spouse logs a prayer today. Diffs
/// `watchDay`'s snapshots (keyed by user+prayer -- the stream is already
/// scoped to one date) so only genuinely new check-ins fire, never the
/// existing history a fresh subscription loads, and never the user's own
/// check-ins. Watched once from HomeScreen.
final prayerNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (authSession == null || couple == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<PrayerLogEntry>(
    keyOf: (e) => '${e.userId}:${e.prayer.dbName}',
    onNew: (entry) {
      if (entry.userId == selfId) return;
      if (entry.status != PrayerStatus.prayed) return;
      unawaited(store.insert(
        kind: 'prayer',
        title: 'Your partner logged ${entry.prayer.displayName}',
        route: '/home/prayer',
      ));
    },
  );

  final sub = ref
      .read(prayerLogRepositoryProvider)
      .watchDay(coupleId: couple.id, date: DateTime.now())
      .listen(detector);
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/prayer_log/`
Expected: `No issues found!` (this file already imports `shared/models/prayer_log.dart` for `PrayerLogEntry`/`PrayerStatus` and `core/time/prayer_engine.dart` for `Prayer.displayName`/`dbName`; if either is missing add it, matching the existing file's header pattern)

- [ ] **Step 3: Commit**

```bash
git add lib/features/prayer_log/domain/prayer_log_providers.dart
git commit -m "feat(notifications): partner prayer check-in notification pump"
```

---

### Task 7: Cycle pump

**Files:**
- Modify: `lib/features/cycle/data/cycle_repository.dart`
- Modify: `lib/features/cycle/domain/cycle_providers.dart`

**Interfaces:**
- Produces: `CycleRepository.watchCoupleShared({required String coupleId}) -> Stream<List<CycleRecord>>`; `cycleNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

- [ ] **Step 1: Add `watchCoupleShared` to `CycleRepository`**

In `lib/features/cycle/data/cycle_repository.dart`, add this method (e.g. after `watchOwn`):

```dart
  /// Both this user's own cycle records AND the spouse's `visibility:
  /// 'shared'` records for [coupleId]. RLS (see
  /// supabase/migrations/20260715000002_cycle_rls.sql) already restricts
  /// what this query can return to exactly that set -- a spouse's private
  /// record is never returned at the database layer.
  Stream<List<CycleRecord>> watchCoupleShared({required String coupleId}) {
    return _client
        .from('cycle_records')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) =>
            [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r))]);
  }
```

- [ ] **Step 2: Add the pump provider**

In `lib/features/cycle/domain/cycle_providers.dart`, add imports (this file already imports `../../auth/domain/auth_controller.dart` for `authSessionProvider` — confirm, don't duplicate):

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
```

Append this provider at the end of the file:

```dart
/// Writes a notification when the spouse shares a cycle update. Diffs
/// `watchCoupleShared`'s snapshots by record id. Client-side filters to
/// `visibility == 'shared' && userId != self` as defense in depth even
/// though RLS already guarantees a private spouse record never reaches this
/// stream at all. Deliberately non-clinical wording. Watched once from
/// HomeScreen.
final cycleNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (authSession == null || couple == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<CycleRecord>(
    keyOf: (r) => r.id,
    onNew: (record) {
      if (record.userId == selfId) return;
      if (record.visibility != 'shared') return;
      unawaited(store.insert(
        kind: 'cycle',
        title: 'Your partner shared a cycle update',
        route: '/home/cycle',
      ));
    },
  );

  final sub = ref
      .read(cycleRepositoryProvider)
      .watchCoupleShared(coupleId: couple.id)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/features/cycle/`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/cycle/data/cycle_repository.dart lib/features/cycle/domain/cycle_providers.dart
git commit -m "feat(notifications): shared cycle update notification pump"
```

---

### Task 8: Daily question pump

**Files:**
- Modify: `lib/features/daily/domain/question_providers.dart`

**Interfaces:**
- Consumes: `newRowDetector` (Task 4), `notificationStoreProvider` (Task 3), the *existing* `questionAnswersProvider` (already a live stream of today's `QuestionAnswer` rows for the couple — no repository change needed), `authSessionProvider` (existing).
- Produces: `questionNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

- [ ] **Step 1: Add the provider**

In `lib/features/daily/domain/question_providers.dart`, add imports:

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../auth/domain/auth_controller.dart';
```

(`../../pairing/domain/pairing_providers.dart` is already imported for `currentCoupleProvider`, per the existing `questionAnswersProvider` in this same file — don't duplicate it.)

Append this provider at the end of the file:

```dart
/// Writes a notification when the spouse answers today's question. Diffs
/// the existing `questionAnswersProvider`'s snapshots (already scoped to
/// today's question for this couple) by author id, so it fires only for a
/// genuinely new partner answer -- never the user's own, never on the
/// first emission (existing history). Watched once from HomeScreen.
final questionNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<QuestionAnswer>(
    keyOf: (a) => a.authorId,
    onNew: (answer) {
      if (answer.authorId == selfId) return;
      unawaited(store.insert(
        kind: 'question',
        title: "Your partner answered today's question",
        route: '/home/question',
      ));
    },
  );

  final sub = ref.watch(questionAnswersProvider.stream).listen(detector);
  ref.onDispose(sub.cancel);
});
```

Note: this watches `questionAnswersProvider.stream` (the raw stream), not `ref.watch(questionAnswersProvider)` (the `AsyncValue`) — `.stream` gives a plain `Stream<List<QuestionAnswer>>` that `.listen(detector)` can subscribe to directly, matching `detector`'s `void Function(List<T>)` shape from `newRowDetector`.

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/daily/`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/daily/domain/question_providers.dart
git commit -m "feat(notifications): daily question answer notification pump"
```

---

### Task 9: Duas pump

**Files:**
- Modify: `lib/features/duas/domain/dua_providers.dart`

**Interfaces:**
- Consumes: `newRowDetector` (Task 4), `notificationStoreProvider` (Task 3), the *existing* `duasProvider` (`lib/features/duas/domain/dua_providers.dart` — already a `StreamProvider<List<Dua>>` filtered to `visibility == 'shared' || authorId == me`, no repository change needed), `authSessionProvider` (existing, already imported in this file).
- Produces: `duaNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

- [ ] **Step 1: Add the provider**

In `lib/features/duas/domain/dua_providers.dart`, add imports (the file already imports `authSessionProvider` and `currentCoupleProvider` — don't duplicate those):

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
```

Append this provider at the end of the file:

```dart
/// Writes a notification when the spouse adds a new SHARED dua. Diffs the
/// existing `duasProvider`'s snapshots by id -- that provider already
/// filters to `visibility == 'shared' || authorId == me`, so any
/// partner-authored row reaching this detector is, by construction, a
/// shared one; the `authorId == selfId` check below is what's actually
/// needed (to skip the user's own duas), kept as the one guard here for
/// defense in depth. Watched once from HomeScreen.
final duaNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<Dua>(
    keyOf: (d) => d.id,
    onNew: (dua) {
      if (dua.authorId == selfId) return;
      unawaited(store.insert(
        kind: 'dua',
        title: 'Your partner added a dua',
        body: dua.title,
        route: '/home/duas',
      ));
    },
  );

  final sub = ref.watch(duasProvider.stream).listen(detector);
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/duas/`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/duas/domain/dua_providers.dart
git commit -m "feat(notifications): shared dua notification pump"
```

---

### Task 10: Fix the gratitude privacy leak, then add the gratitude pump

**Files:**
- Modify: `lib/features/gratitude/data/gratitude_repository.dart`
- Modify: `lib/features/gratitude/domain/gratitude_providers.dart`
- Test: `test/features/gratitude/gratitude_repository_test.dart` (new — integration test, this repository talks straight to Supabase with no seam to unit-test against, matching this codebase's `_pairCouple`-based integration test convention used elsewhere, e.g. `test/features/chat/chat_repository_test.dart`)

**Interfaces:**
- Modifies: `GratitudeRepository.watchAll(String coupleId)` → `GratitudeRepository.watchAll({required String coupleId, required String selfUserId})`, filtering server-side to `author_id = selfUserId OR reveal_to_spouse = true`. Every call site must be updated.
- Produces: `gratitudeNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 12.

This is a **real, pre-existing privacy bug**, not a new feature: `watchAll` currently streams every `gratitude_notes` row for the couple with no filter, so a partner's still-private note body is already delivered to the other partner's device (`gratitude_screen.dart`'s `_NoteTile` merely chooses not to *render* `note.body` when `hidden`). See `docs/superpowers/specs/2026-08-01-notification-inbox-v2-design.md` for the full analysis. Fixing the query is a prerequisite for the notification source below — without it, a naive "partner wrote a gratitude note" pump would fire on creation of a still-private note, making the leak's symptom worse, not better.

- [ ] **Step 1: Write the failing integration test**

Create `test/features/gratitude/gratitude_repository_test.dart`, following the exact pairing/cleanup pattern from `test/features/chat/chat_repository_test.dart` (real local Supabase, two throwaway users paired via `create_pairing_invite`/`accept_pairing_invite`):

```dart
// test/features/gratitude/gratitude_repository_test.dart
//
// Integration test against LOCAL Supabase (Docker). Same pairing/cleanup
// pattern as test/features/chat/chat_repository_test.dart.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/gratitude/data/gratitude_repository.dart';

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

Future<({String userA, String userB, String coupleId})> _pairCouple(
  SupabaseClient clientA,
  SupabaseClient clientB,
  int stamp,
) async {
  final signUpA = await clientA.auth.signUp(
    email: 'gratitude-a-$stamp@test.local',
    password: 'password123',
  );
  final signUpB = await clientB.auth.signUp(
    email: 'gratitude-b-$stamp@test.local',
    password: 'password123',
  );
  final userA = signUpA.user!.id;
  final userB = signUpB.user!.id;

  addTearDown(() => adminClient.auth.admin.deleteUser(userA));
  addTearDown(() => adminClient.auth.admin.deleteUser(userB));

  await clientA.from('users').update({'gender': 'male'}).eq('id', userA);
  await clientB.from('users').update({'gender': 'female'}).eq('id', userB);

  final inviteRes = await clientA.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  final code = inviteRow['code'] as String;
  await clientB.rpc('accept_pairing_invite', params: {'p_code': code});

  final coupleId = await clientA.rpc('current_couple') as String;
  return (userA: userA, userB: userB, coupleId: coupleId);
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test(
      'watchAll never returns a partner\'s unrevealed note, but does return one\'s own and a revealed one',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pairing = await _pairCouple(clientA, clientB, stamp);

    final repoA = GratitudeRepository(clientA);
    final repoB = GratitudeRepository(clientB);

    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      body: 'A private note from A',
      revealToSpouse: false,
    );
    await repoA.add(
      coupleId: pairing.coupleId,
      userId: pairing.userA,
      body: 'A revealed note from A',
      revealToSpouse: true,
    );

    // B's view: sees the revealed note's real body, and must NOT receive
    // the private note at all (not even a redacted placeholder row).
    final bView = await repoB
        .watchAll(coupleId: pairing.coupleId, selfUserId: pairing.userB)
        .first;
    expect(bView.map((n) => n.body), ['A revealed note from A']);

    // A's own view: sees BOTH of their own notes regardless of reveal state.
    final aView = await repoA
        .watchAll(coupleId: pairing.coupleId, selfUserId: pairing.userA)
        .first;
    expect(
      aView.map((n) => n.body).toSet(),
      {'A private note from A', 'A revealed note from A'},
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (requires `supabase start`):
```bash
flutter test --tags integration test/features/gratitude/gratitude_repository_test.dart
```
Expected: FAIL — `watchAll` doesn't accept a `selfUserId` named parameter yet (compile error), or if it does compile against the old positional signature, the assertion on `bView` fails because the private note is still present.

- [ ] **Step 3: Fix `GratitudeRepository.watchAll`**

In `lib/features/gratitude/data/gratitude_repository.dart`, change:

```dart
  Stream<List<GratitudeNote>> watchAll(String coupleId) {
    return _client
        .from('gratitude_notes')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                GratitudeNote.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }
```

to:

```dart
  /// Own notes plus the spouse's `reveal_to_spouse: true` notes only -- a
  /// still-private spouse note must never reach this device at all (fixes
  /// a real leak: the previous unfiltered query relied on the UI alone to
  /// hide `note.body`, but the raw text was already delivered to the
  /// client). Supabase's `.or(...)` filter expresses this server-side.
  Stream<List<GratitudeNote>> watchAll({
    required String coupleId,
    required String selfUserId,
  }) {
    return _client
        .from('gratitude_notes')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                GratitudeNote.fromRow(Map<String, dynamic>.from(r)),
            ])
        .map((notes) => [
              for (final n in notes)
                if (n.authorId == selfUserId || n.revealToSpouse) n,
            ]);
  }
```

Note: the `.or('author_id.eq.$selfUserId,reveal_to_spouse.eq.true')` form
would push the filter into Postgres directly (marginally more efficient),
but `.stream()` builders in this version of `supabase_flutter` compose
`.eq`/`.order` before terminal execution and a second `.or` here has a real
risk of being dropped/malformed depending on the installed
`postgrest`/`realtime` client version. Filtering the already-fetched list
in a second `.map(...)` (as above) is unconditionally correct regardless of
that version question, and the row count here (one couple's notes) is small
enough that the extra client-side pass has no meaningful cost. If you
independently confirm the installed package version's `.stream()` builder
supports `.or(...)` cleanly, using it instead is fine -- but do not guess;
verify by reading the installed `supabase_flutter`/`postgrest` package
source or an existing `.or(...)` usage elsewhere in this codebase first
(`lib/features/pairing/data/pairing_repository.dart`'s `fetchCurrentCouple`
uses `.or(...)` on a one-shot `.select()`, not a `.stream()` — check whether
`.stream()` supports it identically before relying on it there).

- [ ] **Step 4: Update the call site**

In `lib/features/gratitude/domain/gratitude_providers.dart`, update:

```dart
final gratitudeNotesProvider =
    StreamProvider<List<GratitudeNote>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (couple == null) return const Stream.empty();
  return ref.read(gratitudeRepositoryProvider).watchAll(couple.id);
});
```

to:

```dart
final gratitudeNotesProvider =
    StreamProvider<List<GratitudeNote>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (couple == null || session == null) return const Stream.empty();
  return ref.read(gratitudeRepositoryProvider).watchAll(
        coupleId: couple.id,
        selfUserId: session.user.id,
      );
});
```

Add `import '../../auth/domain/auth_controller.dart';` if not already present in this file (check first — `authSessionProvider` is used elsewhere in the codebase from this same import path).

- [ ] **Step 5: Run the integration test to verify it passes**

Run: `flutter test --tags integration test/features/gratitude/gratitude_repository_test.dart`
Expected: PASS (1 test)

- [ ] **Step 6: Run the full non-integration suite + analyze**

Run: `flutter analyze lib/features/gratitude/` then `flutter test --exclude-tags integration`
Expected: both clean/PASS — this confirms `gratitude_screen.dart`'s existing usage of `gratitudeNotesProvider` still compiles (it only reads the provider, doesn't call `watchAll` directly, so it's unaffected by the signature change).

- [ ] **Step 7: Add the gratitude notification pump**

In `lib/features/gratitude/domain/gratitude_providers.dart`, add imports:

```dart
import 'dart:async';

import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
```

Append this provider at the end of the file:

```dart
/// Writes a notification the moment a partner's gratitude note becomes
/// visible to you. Diffs `gratitudeNotesProvider`'s snapshots by id -- since
/// the query fix above guarantees a partner row only ever appears here once
/// it's genuinely visible (created-and-revealed immediately, or revealed
/// later), a plain new-row diff already means "revealed," with no separate
/// reveal-transition tracking needed. Watched once from HomeScreen.
final gratitudeNotificationPumpProvider = Provider<void>((ref) {
  final authSession = ref.watch(authSessionProvider).asData?.value;
  if (authSession == null) return;
  final selfId = authSession.user.id;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<GratitudeNote>(
    keyOf: (n) => n.id,
    onNew: (note) {
      if (note.authorId == selfId) return;
      unawaited(store.insert(
        kind: 'gratitude',
        title: 'Your partner shared something they\'re grateful for',
        route: '/home/gratitude',
      ));
    },
  );

  final sub = ref.watch(gratitudeNotesProvider.stream).listen(detector);
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 8: Verify it compiles**

Run: `flutter analyze lib/features/gratitude/`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/features/gratitude/data/gratitude_repository.dart lib/features/gratitude/domain/gratitude_providers.dart test/features/gratitude/gratitude_repository_test.dart
git commit -m "fix(gratitude): stop leaking unrevealed partner notes; add reveal notification pump"
```

---

### Task 11: `NotificationsScreen` + route

**Files:**
- Create: `lib/features/notifications/presentation/notifications_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/notifications/notifications_screen_test.dart`

**Interfaces:**
- Consumes: `notificationsListProvider`, `notificationStoreProvider` (Task 3), `NotificationRow` (Task 2).
- Produces: `NotificationsScreen` widget; route `/home/notifications`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/notifications/notifications_screen_test.dart`, following the exact override pattern from `test/features/chat/chat_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/notification_providers.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/notifications/presentation/notifications_screen.dart';

void main() {
  testWidgets('renders notifications and marks them read on open', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = NotificationStore(db);
    await store.insert(
      kind: 'pairing',
      title: "You're connected",
      body: 'You and your partner are now paired 💛',
      route: '/home',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationStoreProvider.overrideWithValue(store),
        notificationsListProvider.overrideWith((ref) => store.watchAll()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pump();

    expect(find.text("You're connected"), findsOneWidget);
    expect(find.text('You and your partner are now paired 💛'), findsOneWidget);

    // Opening the screen marks it read.
    await tester.pump();
    expect(await store.watchUnreadCount().first, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shows an empty state with no notifications', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = NotificationStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationStoreProvider.overrideWithValue(store),
        notificationsListProvider.overrideWith((ref) => store.watchAll()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pump();

    expect(find.text('No notifications yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications/notifications_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:lovinity/features/notifications/presentation/notifications_screen.dart'`

- [ ] **Step 3: Implement `NotificationsScreen`**

Create `lib/features/notifications/presentation/notifications_screen.dart`:

```dart
// lib/features/notifications/presentation/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_store.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen marks everything currently unread as read.
    ref.read(notificationStoreProvider).markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsListProvider);

    return LovScaffold(
      title: 'Notifications',
      padded: false,
      child: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load notifications',
              style: theme.textTheme.bodyMedium),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(LovSpace.xl),
                child: Text(
                  'No notifications yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: LovSpace.md),
            itemCount: items.length,
            itemBuilder: (context, index) => _NotificationTile(item: items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final NotificationRow item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = item.readAt == null;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LovSpace.lg, vertical: LovSpace.xs),
      child: LovCard(
        variant: LovCardVariant.tonal,
        onTap: () => context.go(item.route),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: LovSpace.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notifications/notifications_screen_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Add the route**

In `lib/core/router/app_router.dart`, add the import:

```dart
import '../../features/notifications/presentation/notifications_screen.dart';
```

Add a new `GoRoute` under `/home`'s `routes:` list (next to the `chat`/`gratitude`/`duas`/`cycle` routes):

```dart
          GoRoute(
            path: 'notifications',
            builder: (_, _) => const NotificationsScreen(),
          ),
```

- [ ] **Step 6: Verify it compiles**

Run: `flutter analyze lib/core/router/ lib/features/notifications/`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/notifications/presentation/notifications_screen.dart lib/core/router/app_router.dart test/features/notifications/notifications_screen_test.dart
git commit -m "feat(notifications): add NotificationsScreen and /home/notifications route"
```

---

### Task 12: Home screen bell icon + mount all six pumps

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`

**Interfaces:**
- Consumes: `unreadNotificationCountProvider` (Task 3), `pairingNotificationPumpProvider` (Task 5), `prayerNotificationPumpProvider` (Task 6), `cycleNotificationPumpProvider` (Task 7), `questionNotificationPumpProvider` (Task 8), `duaNotificationPumpProvider` (Task 9), `gratitudeNotificationPumpProvider` (Task 10).

- [ ] **Step 1: Add imports**

In `lib/features/home/presentation/home_screen.dart`, add:

```dart
import '../../../core/notifications/notification_providers.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../daily/domain/question_providers.dart';
import '../../duas/domain/dua_providers.dart';
import '../../gratitude/domain/gratitude_providers.dart';
import '../../prayer_log/domain/prayer_log_providers.dart';
```

(`../../pairing/domain/pairing_providers.dart` is already imported.)

- [ ] **Step 2: Mount the six new pumps**

In `HomeScreen.build`, alongside the existing:

```dart
    ref.watch(inboxPumpProvider);
    ref.watch(receiptPumpProvider);
```

add:

```dart
    ref.watch(pairingNotificationPumpProvider);
    ref.watch(prayerNotificationPumpProvider);
    ref.watch(cycleNotificationPumpProvider);
    ref.watch(questionNotificationPumpProvider);
    ref.watch(duaNotificationPumpProvider);
    ref.watch(gratitudeNotificationPumpProvider);
```

- [ ] **Step 3: Add the bell icon next to Settings**

Find this block (the top row with the settings `IconButton`):

```dart
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Settings',
                        onPressed: () => context.go('/home/settings'),
                      ),
```

Replace it with a bell icon (with unread badge) followed by the existing settings button:

```dart
                      _NotificationBell(),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Settings',
                        onPressed: () => context.go('/home/settings'),
                      ),
```

Add this widget class in the same file (e.g. near `_ChatFab`):

```dart
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final button = IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: 'Notifications',
      onPressed: () => context.go('/home/notifications'),
    );
    if (count <= 0) return button;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      offset: const Offset(-6, 6),
      child: button,
    );
  }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/features/home/`
Expected: `No issues found!`

There is no existing `home_screen_test.dart` in this repo (HomeScreen's dependency graph is large — prayer/cycle/scoring/location — and isn't widget-tested directly today), so this task doesn't add one; that matches existing precedent (the already-existing `_ChatFab` badge isn't widget-tested either).

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/presentation/home_screen.dart
git commit -m "feat(notifications): add home screen bell icon + badge, mount all notification pumps"
```

---

### Task 13: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full analyzer**

Run: `flutter analyze`
Expected: `No issues found!` (aside from any pre-existing, unrelated info-level lints already present before this plan — do not treat those as new failures; only investigate issues that name a file this plan touched)

- [ ] **Step 2: Run the full non-integration test suite**

Run: `flutter test --exclude-tags integration`
Expected: all tests PASS (the pre-existing suite plus every test added in Tasks 1, 2, 4, 11)

- [ ] **Step 3: Run the full integration suite (requires `supabase start`)**

Run: `flutter test --tags integration`
Expected: all tests PASS, including the new gratitude repository test from Task 10.

- [ ] **Step 4: If anything fails, fix forward**

Do not skip or delete a failing test to make this green — either the implementation or the test has a bug from an earlier task; find and fix it, re-run, and only proceed once this is clean.

- [ ] **Step 5: Manual smoke-test note**

This plan cannot be fully verified by automated tests alone: the six pump providers each depend on a live Supabase realtime stream reacting to a genuine partner-side change (someone else logging a prayer, answering the question, etc.), which the automated suite exercises only at the pure-diff-logic level (Task 4's tests) and the repository-query level (Task 10's integration test) — not as a live two-device end-to-end flow. Recommend an on-device pass with two paired accounts before considering this fully done: log a prayer as partner A, confirm partner B's bell badge increments and the notification appears with the right title/route; repeat for cycle (shared visibility only), the daily question, a shared dua, and a revealed gratitude note; confirm a *private* dua and an *unrevealed* gratitude note produce no notification at all.

- [ ] **Step 6: Final commit (if Step 4 required fixes)**

```bash
git add -A
git commit -m "fix(notifications): address full-suite verification findings"
```
