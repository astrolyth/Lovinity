# In-App Notification Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persisted, on-device notification inbox (bell icon + screen) surfacing partner chat messages/reactions, pairing, prayer check-ins, and shared cycle updates — an alternative to relying solely on the chat unread badge and OS push.

**Architecture:** A new `AppNotifications` Drift table lives in the existing `SignalDb` (the same local database chat already uses, so it's covered by the existing account-switch wipe). A `NotificationStore` wraps it. Four independent event sources write into it: the chat inbox handler (already decrypts everything), and three new "pump" providers that diff a Supabase realtime stream against its previous snapshot to detect genuinely-new partner activity (pairing, prayer, cycle). A bell icon + badge on the home screen opens a new `/home/notifications` screen.

**Tech Stack:** Flutter, Riverpod, Drift (existing `SignalDb`), Supabase realtime streams (existing repositories), go_router.

## Global Constraints

- Every notification-write call site is best-effort: wrapped so a failure can never break the feature it observes (matches `ChatService.sendReaction`'s existing swallow-and-continue pattern).
- The `AppNotifications` table (not `Notifications`) — Drift would otherwise generate a row class literally named `Notification`, which collides with `package:flutter/widgets.dart`'s own `Notification` class wherever both are imported. Keep this name throughout.
- Cycle notifications only ever fire for `visibility == 'shared'` records, checked client-side even though RLS already enforces it server-side (defense in depth, matches the spec).
- `SignalDb.wipeAll()` must clear `appNotifications` too — same cross-account-leak protection chat already has.
- Match existing patterns: Riverpod `Provider`/`StreamProvider`, repository pattern, Drift table conventions, best-effort error swallowing. No new state-management or database libraries.
- `flutter analyze` must stay clean and `flutter test` must stay green after every task.

---

### Task 1: `AppNotifications` table in `SignalDb`

**Files:**
- Modify: `lib/core/storage/signal_db.dart`
- Modify: `test/core/storage/signal_db_test.dart` (already exists — currently one test, `'stores and reads a session row'`; add the new test into its `main()` block, don't replace the existing one)

**Interfaces:**
- Produces: `AppNotifications` Drift table (fields: `id` text pk, `kind` text, `title` text, `body` text nullable, `route` text, `createdAt` datetime, `readAt` datetime nullable) and its generated `AppNotification` row class / `AppNotificationsCompanion`. `SignalDb.wipeAll()` now also clears it.

- [ ] **Step 1: Add the table to `lib/core/storage/signal_db.dart`**

Add this class after `ChatReactions` (around line 90):

```dart
/// Persisted local activity feed: partner chat messages/reactions, pairing,
/// prayer check-ins, and shared cycle updates (see
/// docs/superpowers/specs/2026-07-27-notification-inbox-design.md). Named
/// `AppNotifications`, not `Notifications` — Drift would otherwise generate
/// a row class literally called `Notification`, colliding with
/// `package:flutter/widgets.dart`'s own `Notification` class wherever this
/// table and Flutter widgets are imported together.
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'message'|'reaction'|'pairing'|'prayer'|'cycle'
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  TextColumn get route => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();

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

Bump the schema version and add the migration step:

```dart
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(signalMeta);
          if (from < 3) {
            await m.createTable(chatMessages);
            await m.createTable(chatReactions);
          }
          if (from < 4) await m.createTable(appNotifications);
        },
      );
```

Add the delete to `wipeAll()`:

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

`test/core/storage/signal_db_test.dart` already exists with one test (`'stores and reads a session row'`). Add a second test into its existing `main()` block — do not replace the existing test:

```dart
  test('wipeAll clears appNotifications along with chat/signal tables', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);

    await db.into(db.appNotifications).insert(
          AppNotificationsCompanion.insert(
            id: 'n1',
            kind: 'message',
            title: 'New message from your partner',
            route: '/home/chat',
            createdAt: DateTime(2026),
          ),
        );
    expect(await db.select(db.appNotifications).get(), hasLength(1));

    await db.wipeAll();

    expect(await db.select(db.appNotifications).get(), isEmpty);
  });
```

The file's existing imports (`package:drift/drift.dart`, `package:flutter_test/flutter_test.dart`, `package:lovinity/core/storage/signal_db.dart`) already cover everything this test needs — no new imports required.

- [ ] **Step 4: Run the test**

Run: `flutter test test/core/storage/signal_db_test.dart`
Expected: PASS, 2 tests (the pre-existing one plus the new wipe test) — build_runner already generated the needed classes in Step 2, so this should pass immediately; it exists to prove the wipe, not the schema.

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart test/core/storage/signal_db_test.dart
git commit -m "feat(notifications): add AppNotifications table to SignalDb, wired into wipeAll"
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

  test('insert then watchAll returns newest first', () async {
    await store.insert(
        kind: 'message', title: 'first', body: 'a', route: '/home/chat');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.insert(
        kind: 'message', title: 'second', body: 'b', route: '/home/chat');

    final rows = await store.watchAll().first;
    expect(rows.map((r) => r.title).toList(), ['second', 'first']);
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

  Future<void> insert({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) {
    return _db.into(_db.appNotifications).insert(
          AppNotificationsCompanion.insert(
            id: const Uuid().v4(),
            kind: kind,
            title: title,
            body: Value(body),
            route: route,
            createdAt: DateTime.now(),
          ),
        );
  }

  Stream<List<NotificationRow>> watchAll() {
    return (_db.select(_db.appNotifications)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
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
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/notifications/notification_store.dart test/core/notifications/notification_store_test.dart
git commit -m "feat(notifications): add NotificationStore over AppNotifications"
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
/// Firebase-related by itself (`init()` -- called by Task 4's boot/lifecycle
/// wiring -- is what actually touches Firebase, and is fully guarded).
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

### Task 4: Chat hook — messages & reactions

**Files:**
- Modify: `lib/features/chat/domain/chat_service.dart`
- Modify: `lib/features/chat/domain/chat_providers.dart`
- Modify: `test/features/chat/chat_service_test.dart`

**Interfaces:**
- Consumes: `NotificationStore.insert` (Task 2), `notificationStoreProvider` (Task 3).
- Produces: `ChatService` gains an optional `NotificationStore? notifications` constructor param (defaults to `null`, so every existing call site — including every other test in this file — keeps compiling unchanged).

- [ ] **Step 1: Write the failing tests**

In `test/features/chat/chat_service_test.dart`, add the import:

```dart
import 'package:lovinity/core/notifications/notification_store.dart';
```

Change the `setUp` block to also build a `NotificationStore` over the same device-1 DB and pass it into `chat`:

```dart
  late _FakeChatRepo repo;
  late ChatStore store;
  late NotificationStore notifications;
  late ChatService chat;

  setUp(() async {
    registry = <_Device>[];
    self1 = await _makeDevice(selfUserId, 1, registry);
    self2 = await _makeDevice(selfUserId, 2, registry);
    spouse1 = await _makeDevice(spouseUserId, 1, registry);
    registry.addAll([self1, self2, spouse1]);

    repo = _FakeChatRepo();
    store = ChatStore(self1.db);
    notifications = NotificationStore(self1.db);
    chat = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      notifications: notifications,
    );
  });
```

Add these test cases at the end of `main()`, before the closing `}`:

```dart
  test('handleInboxRow on a spouse TextPayload writes a notification with the real preview',
      () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const TextPayload(body: 'on my way home')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);
    final envelope = <String, dynamic>{
      'id': 'env-notif-1',
      'message_id': 'msg-notif-1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    final rows = await notifications.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'message');
    expect(rows.single.title, 'New message from your partner');
    expect(rows.single.body, 'on my way home');
    expect(rows.single.route, '/home/chat');
  });

  test('handleInboxRow on a spouse ReactionPayload (add) writes a notification',
      () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const ReactionPayload(
          targetMessageId: 'target-1', emoji: '❤️', add: true)),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);
    final envelope = <String, dynamic>{
      'id': 'env-notif-2',
      'message_id': 'msg-notif-2',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    final rows = await notifications.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'reaction');
    expect(rows.single.title, 'Your partner reacted to your message');
    expect(rows.single.body, '❤️');
  });

  test('handleInboxRow on a reaction REMOVAL does not write a notification',
      () async {
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(const ReactionPayload(
          targetMessageId: 'target-1', emoji: '❤️', add: false)),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);
    final envelope = <String, dynamic>{
      'id': 'env-notif-3',
      'message_id': 'msg-notif-3',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    expect(await notifications.watchAll().first, isEmpty);
  });

  test('handleInboxRow on a self-sync copy (own other device) does not write a notification',
      () async {
    final copies = await self2.service.encryptFor(
      recipientUserId: spouseUserId,
      plaintext: encodePayload(const TextPayload(body: 'sent from my other device')),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);
    final envelope = <String, dynamic>{
      'id': 'env-notif-4',
      'message_id': 'msg-notif-4',
      'sender_id': selfUserId,
      'sender_device_num': 2,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await chat.handleInboxRow(envelope);

    expect(await notifications.watchAll().first, isEmpty);
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL on the 4 new tests — `No named parameter with the name 'notifications'` (compile error), since `ChatService` doesn't have that param yet.

- [ ] **Step 3: Add the `notifications` param and `_notify` calls to `ChatService`**

In `lib/features/chat/domain/chat_service.dart`, add the import:

```dart
import '../../../core/notifications/notification_store.dart';
```

Update the constructor and add a field:

```dart
class ChatService {
  ChatService({
    required this.session,
    required this.repo,
    required this.store,
    required this.selfUserId,
    required this.spouseUserId,
    required this.selfDeviceNum,
    this.notifications,
  });

  final SignalSessionService session;
  final ChatRepository repo;
  final ChatStore store;
  final String selfUserId;
  final String spouseUserId;
  final int selfDeviceNum;

  /// Optional: when set, a spouse-authored message/reaction writes a row
  /// here (see docs/superpowers/specs/2026-07-27-notification-inbox-design.md).
  /// Null in most existing tests, which don't care about this side channel.
  final NotificationStore? notifications;
```

Add a private helper method (anywhere inside the class, e.g. just above `handleInboxRow`):

```dart
  /// Best-effort: a failure here must never break chat itself. No-op when
  /// [notifications] wasn't provided.
  Future<void> _notify({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) async {
    final store = notifications;
    if (store == null) return;
    try {
      await store.insert(kind: kind, title: title, body: body, route: route);
    } catch (_) {
      // best-effort; never break chat over a notification-write failure
    }
  }
```

Update the `switch (payload)` block inside `_handleInboxRow` from:

```dart
    switch (payload) {
      case TextPayload():
        await store.upsertMessage(
          id: messageId,
          senderId: senderId,
          body: payload.body,
          replyToMessageId: payload.replyToMessageId,
          createdAt: DateTime.parse(env['created_at'] as String),
          // Own-device sync copies are already-sent; spouse copies are delivered.
          status: senderId == selfUserId ? 'sent' : 'delivered',
        );
        if (senderId != selfUserId) await repo.markDelivered(messageId);
      case ReactionPayload():
        await store.applyReaction(
          messageId: payload.targetMessageId,
          reactorId: senderId,
          emoji: payload.emoji,
          add: payload.add,
        );
      case UnsupportedPayload():
        break; // skip, still delete the envelope below
    }
```

to:

```dart
    switch (payload) {
      case TextPayload():
        await store.upsertMessage(
          id: messageId,
          senderId: senderId,
          body: payload.body,
          replyToMessageId: payload.replyToMessageId,
          createdAt: DateTime.parse(env['created_at'] as String),
          // Own-device sync copies are already-sent; spouse copies are delivered.
          status: senderId == selfUserId ? 'sent' : 'delivered',
        );
        if (senderId != selfUserId) {
          await repo.markDelivered(messageId);
          await _notify(
            kind: 'message',
            title: 'New message from your partner',
            body: payload.body,
            route: '/home/chat',
          );
        }
      case ReactionPayload():
        await store.applyReaction(
          messageId: payload.targetMessageId,
          reactorId: senderId,
          emoji: payload.emoji,
          add: payload.add,
        );
        if (senderId != selfUserId && payload.add) {
          await _notify(
            kind: 'reaction',
            title: 'Your partner reacted to your message',
            body: payload.emoji,
            route: '/home/chat',
          );
        }
      case UnsupportedPayload():
        break; // skip, still delete the envelope below
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: PASS — all tests, including the 4 new ones (the shared `setUp` now wires `notifications`, and every other pre-existing test in the file simply doesn't touch it, so they're unaffected).

- [ ] **Step 5: Wire the real store into `chatServiceProvider`**

In `lib/features/chat/domain/chat_providers.dart`, add the import:

```dart
import '../../../core/notifications/notification_providers.dart';
```

Update `chatServiceProvider`'s `ChatService(...)` construction:

```dart
  return ChatService(
    session: session,
    repo: ref.read(chatRepositoryProvider),
    store: ref.read(chatStoreProvider),
    selfUserId: selfId,
    spouseUserId: couple.spouseOf(selfId),
    selfDeviceNum: deviceNum,
    notifications: ref.read(notificationStoreProvider),
  );
```

- [ ] **Step 6: Verify the full chat test suite + analyze**

Run: `flutter test test/features/chat/ && flutter analyze lib/features/chat/`
Expected: all PASS, `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/domain/chat_service.dart lib/features/chat/domain/chat_providers.dart test/features/chat/chat_service_test.dart
git commit -m "feat(notifications): write a notification on spouse chat messages/reactions"
```

---

### Task 5: Shared partner-activity diff helpers

**Files:**
- Create: `lib/core/notifications/activity_detectors.dart`
- Test: `test/core/notifications/activity_detectors_test.dart`

**Interfaces:**
- Produces:
  - `void Function(List<T> rows) newRowDetector<T>({required String Function(T row) keyOf, required void Function(T row) onNew})`
  - `bool pairingJustActivated(String? previousStatus, String? nextStatus)`

These are pure functions (no Riverpod, no Drift) used by the pairing/prayer/cycle pump providers in Tasks 6-8.

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
// in isolation; see docs/superpowers/specs/2026-07-27-notification-inbox-design.md.

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

### Task 6: Pairing pump

**Files:**
- Modify: `lib/features/pairing/domain/pairing_providers.dart`

**Interfaces:**
- Consumes: `pairingJustActivated` (Task 5), `notificationStoreProvider` (Task 3), `pairingRepositoryProvider.watchCurrentCouple` (existing), `authSessionProvider` (existing).
- Produces: `pairingNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 10.

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

### Task 7: Prayer log pump

**Files:**
- Modify: `lib/features/prayer_log/domain/prayer_log_providers.dart`

**Interfaces:**
- Consumes: `newRowDetector` (Task 5), `notificationStoreProvider` (Task 3), `prayerLogRepositoryProvider.watchDay` (existing), `currentCoupleProvider`/`authSessionProvider` (existing).
- Produces: `prayerNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 10.

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
Expected: `No issues found!` (this file already imports `shared/models/prayer_log.dart` for `PrayerLogEntry`/`PrayerStatus` and `core/time/prayer_engine.dart` for `Prayer.displayName`/`dbName` — confirm both are in scope; if not, add `import '../../../shared/models/prayer_log.dart';`, which is already present per the existing file header)

- [ ] **Step 3: Commit**

```bash
git add lib/features/prayer_log/domain/prayer_log_providers.dart
git commit -m "feat(notifications): partner prayer check-in notification pump"
```

---

### Task 8: Cycle pump

**Files:**
- Modify: `lib/features/cycle/data/cycle_repository.dart`
- Modify: `lib/features/cycle/domain/cycle_providers.dart`

**Interfaces:**
- Produces: `CycleRepository.watchCoupleShared({required String coupleId}) -> Stream<List<CycleRecord>>`; `cycleNotificationPumpProvider` (`Provider<void>`) — watched from `HomeScreen` in Task 10.

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

In `lib/features/cycle/domain/cycle_providers.dart`, add imports:

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

`authSessionProvider` needs importing too — check the top of the file; if it's not already imported, add:

```dart
import '../../auth/domain/auth_controller.dart';
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

### Task 9: `NotificationsScreen` + route

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
      kind: 'message',
      title: 'New message from your partner',
      body: 'on my way home',
      route: '/home/chat',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationStoreProvider.overrideWithValue(store),
        notificationsListProvider.overrideWith((ref) => store.watchAll()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pump();

    expect(find.text('New message from your partner'), findsOneWidget);
    expect(find.text('on my way home'), findsOneWidget);

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

Add a new `GoRoute` under `/home`'s `routes:` list (next to the `chat` route):

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

### Task 10: Home screen bell icon + mount the pumps

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`

**Interfaces:**
- Consumes: `unreadNotificationCountProvider` (Task 3), `pairingNotificationPumpProvider` (Task 6), `prayerNotificationPumpProvider` (Task 7), `cycleNotificationPumpProvider` (Task 8).

- [ ] **Step 1: Add imports**

In `lib/features/home/presentation/home_screen.dart`, add:

```dart
import '../../../core/notifications/notification_providers.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../prayer_log/domain/prayer_log_providers.dart';
```

(`../../pairing/domain/pairing_providers.dart` is already imported.)

- [ ] **Step 2: Mount the three new pumps**

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
git commit -m "feat(notifications): add home screen bell icon + badge, mount notification pumps"
```

---

### Task 11: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS (the pre-existing suite plus every test added in Tasks 1, 2, 4, 5, 9)

- [ ] **Step 3: If anything fails, fix forward**

Do not skip or delete a failing test to make this green — either the implementation or the test has a bug from an earlier task; find and fix it, re-run, and only proceed once this is clean.

- [ ] **Step 4: Final commit (if Step 3 required fixes)**

```bash
git add -A
git commit -m "fix(notifications): address full-suite verification findings"
```
