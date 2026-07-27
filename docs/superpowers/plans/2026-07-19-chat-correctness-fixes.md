# Chat Correctness Fixes (sub-project 2 — final-review findings)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the Critical + 3 Important findings from the E2E-chat final review so chat is multi-device-correct and its receipt/send promises reach the UI.

**Architecture:** Targeted fixes in the existing chat pipeline (ChatService/ChatRepository/ChatStore/providers/screen) + one small `send_message` migration. No new features.

**Tech Stack:** Flutter 3.44, drift, supabase_flutter, libsignal, local Supabase (Docker).

## Global Constraints

- Local Supabase RUNNING under Docker. Verify migrations with `supabase db reset` (local). **NEVER `supabase db push`** (production Cloud). DB `127.0.0.1:54322`.
- `cipher_type` uses libsignal constants (3 prekey / 2 message), never literals.
- `handleInboxRow` must never throw on a bad envelope.
- Commit after every task. TDD throughout.

---

## Task 1 (C1 — Critical): device-scoped inbox handling

**Problem:** `watchInbox` filters only by `recipient_id`, so every device in an account sees every device's envelopes; `handleInboxRow`'s `messageExists` short-circuit then **deletes a sibling device's envelope**, so the sibling never receives the message. Multi-device is broken.

**Files:**
- Modify: `lib/features/chat/domain/chat_service.dart` (`handleInboxRow`)
- Test: `test/features/chat/chat_service_test.dart` (add cases)

**Interfaces:**
- Consumes: `ChatService.selfDeviceNum` (already a field); the envelope map carries `recipient_device_num`.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/chat/chat_service_test.dart` (reuse the file's existing fake repo + real two-device crypto harness; the fake `ChatRepository` already captures `deleteEnvelope`/`markDelivered` calls — match its existing field names):

```dart
test('ignores an envelope addressed to a DIFFERENT device (no delete, no decrypt)', () async {
  // Build a ChatService whose selfDeviceNum is 1 (use the existing harness).
  // Feed an envelope map with recipient_device_num = 2 (a sibling device).
  final env = {
    'id': 'env-for-d2',
    'message_id': 'm-other',
    'sender_id': spouseId,       // from the harness
    'sender_device_num': 1,
    'recipient_device_num': 2,   // NOT ours (we are device 1)
    'cipher_type': 3,
    'ciphertext': 'deadbeef',
    'created_at': DateTime(2026).toIso8601String(),
  };
  await service.handleInboxRow(env); // service.selfDeviceNum == 1
  expect(repo.deleteEnvelopeCalls, isEmpty,
      reason: 'must not delete a sibling device\'s envelope');
  expect(await store.messageExists('m-other'), isFalse);
});

test('processes an envelope addressed to OUR device', () async {
  // A real spouse->us TextPayload envelope with recipient_device_num == our selfDeviceNum
  // decrypts, stores 'delivered', and IS deleted. (Build via the real-crypto harness
  // used by the existing round-trip test, adding recipient_device_num == service.selfDeviceNum.)
});
```

- [ ] **Step 2: Run to verify RED**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL — the sibling-device envelope is currently deleted / processed.

- [ ] **Step 3: Add the device guard**

In `handleInboxRow`, make the **first** action (before the `messageExists` short-circuit) a device check:

```dart
Future<void> handleInboxRow(Map<String, dynamic> env) async {
  // Only handle envelopes addressed to THIS device. A user's other devices
  // share the same recipient_id and appear in this stream, but their
  // envelopes are theirs to fetch — we must not read or delete them.
  final recipientDeviceNum = (env['recipient_device_num'] as num?)?.toInt();
  if (recipientDeviceNum != selfDeviceNum) return;

  final messageId = env['message_id'] as String;
  if (await store.messageExists(messageId) && env['id'] != null) {
    await repo.deleteEnvelope(env['id'] as String);
    return;
  }
  // ... unchanged: sender address, decrypt, apply, delete ...
}
```

- [ ] **Step 4: Run to verify GREEN**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: PASS (all existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/domain/chat_service.dart test/features/chat/chat_service_test.dart
git commit -m "fix(chat): only handle envelopes for this device (C1 multi-device loss)"
```

---

## Task 2 (I1 — Important): deliver receipts to the sender's UI

**Problem:** `watchMyMessages` + `ChatStore.setStatus` exist but are never consumed; the sender's local row is never updated from the server receipt flip, so ticks stay ✓ forever.

**Files:**
- Modify: `lib/features/chat/data/chat_store.dart` (add `applyReceipt`)
- Modify: `lib/features/chat/domain/chat_providers.dart` (add `receiptPumpProvider`)
- Modify: `lib/features/chat/presentation/chat_screen.dart` (`ref.watch(receiptPumpProvider)`)
- Test: `test/features/chat/chat_store_test.dart` (add `applyReceipt` case)

**Interfaces:**
- Produces: `ChatStore.applyReceipt({required String id, DateTime? deliveredAt, DateTime? readAt})` — updates only an existing row, sets timestamps, and derives `status` (`read` if readAt, else `delivered` if deliveredAt, else unchanged); `receiptPumpProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

```dart
// in chat_store_test.dart
test('applyReceipt updates delivered/read + derives status; only on an existing row', () async {
  await store.upsertMessage(id: 'm1', senderId: 'me', body: 'hi',
      createdAt: DateTime(2026), status: 'sent');
  await store.applyReceipt(id: 'm1', deliveredAt: DateTime(2026, 1, 2));
  var row = (await store.watchConversation().first).single;
  expect(row.status, 'delivered');
  expect(row.deliveredAt, isNotNull);
  await store.applyReceipt(id: 'm1', readAt: DateTime(2026, 1, 3));
  row = (await store.watchConversation().first).single;
  expect(row.status, 'read');
  expect(row.readAt, isNotNull);
  // No-op on an unknown id (does not insert).
  await store.applyReceipt(id: 'ghost', deliveredAt: DateTime(2026));
  expect(await store.messageExists('ghost'), isFalse);
});
```

- [ ] **Step 2: Run to verify RED**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: FAIL — `applyReceipt` undefined.

- [ ] **Step 3: Implement `applyReceipt`**

In `chat_store.dart`:
```dart
Future<void> applyReceipt({
  required String id,
  DateTime? deliveredAt,
  DateTime? readAt,
}) async {
  final status = readAt != null
      ? 'read'
      : (deliveredAt != null ? 'delivered' : null);
  await (_db.update(_db.chatMessages)..where((t) => t.id.equals(id))).write(
    ChatMessagesCompanion(
      deliveredAt: deliveredAt != null ? Value(deliveredAt) : const Value.absent(),
      readAt: readAt != null ? Value(readAt) : const Value.absent(),
      status: status != null ? Value(status) : const Value.absent(),
    ),
  );
}
```
(A Drift `update().write()` on a non-matching `where` affects 0 rows — no insert — satisfying the "existing row only" requirement.)

- [ ] **Step 4: Add `receiptPumpProvider`**

In `chat_providers.dart` (mirrors `inboxPumpProvider`):
```dart
/// Streams the couple's `messages` rows and reflects the sender-side
/// delivered/read receipts onto the local chat rows the sender authored.
final receiptPumpProvider = Provider<void>((ref) {
  final svc = ref.watch(chatServiceProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (svc == null || couple == null) return;
  final store = ref.read(chatStoreProvider);
  final selfId = svc.selfUserId;
  final sub =
      ref.read(chatRepositoryProvider).watchMyMessages(couple.id).listen((rows) async {
    for (final r in rows) {
      if (r['sender_id'] != selfId) continue; // only our own sent messages
      await store.applyReceipt(
        id: r['id'] as String,
        deliveredAt: r['delivered_at'] == null
            ? null
            : DateTime.parse(r['delivered_at'] as String),
        readAt: r['read_at'] == null
            ? null
            : DateTime.parse(r['read_at'] as String),
      );
    }
  });
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 5: Keep it alive from the screen**

In `chat_screen.dart` `build`, next to the existing `ref.watch(inboxPumpProvider)`, add `ref.watch(receiptPumpProvider);`.

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/chat`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/data/chat_store.dart lib/features/chat/domain/chat_providers.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_store_test.dart
git commit -m "fix(chat): reflect delivered/read receipts onto the sender's messages (I1)"
```

---

## Task 3 (I2 — Important): optimistic send with a failed state

**Problem:** `_send` doesn't await/catch and clears the composer immediately; `sendText` only stores the local row *after* the send succeeds. An offline send loses the text with no `failed` row.

To make the optimistic row (shown before the server responds) share the SAME id as the server message — needed so receipts (Task 2, keyed on the server message id) land on it — the client generates the message id and passes it to `send_message`.

**Files:**
- Create: `supabase/migrations/20260719000001_send_message_client_id.sql`
- Modify: `lib/features/chat/data/chat_repository.dart` (`sendEnvelopes` accepts `messageId`)
- Modify: `lib/features/chat/domain/chat_service.dart` (`sendText` optimistic + status transitions)
- Modify: `lib/features/chat/presentation/chat_screen.dart` (`_send` awaits + is fire-safe)
- Test: `test/features/chat/chat_service_test.dart` (add send-failure case)

**Interfaces:**
- Produces: `send_message(p_sender_device_num int, p_envelopes jsonb, p_message_id uuid default null)`; `ChatRepository.sendEnvelopes({senderDeviceNum, copies, String? messageId})`.

- [ ] **Step 1: Migration**

`supabase/migrations/20260719000001_send_message_client_id.sql` — recreate `send_message` with an optional client id:
```sql
create or replace function public.send_message(
  p_sender_device_num integer,
  p_envelopes jsonb,
  p_message_id uuid default null
)
returns table (message_id uuid, created_at timestamptz)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_cid  uuid;
  v_conv uuid;
  v_msg  public.messages%rowtype;
  e      jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select id into v_cid from public.couples
    where v_uid in (member_a, member_b) and status = 'active' limit 1;
  if v_cid is null then raise exception 'not_paired'; end if;

  select id into v_conv from public.conversations where couple_id = v_cid;
  if v_conv is null then
    insert into public.conversations (couple_id) values (v_cid) returning id into v_conv;
  end if;

  insert into public.messages (id, conversation_id, couple_id, sender_id, sender_device_num)
    values (coalesce(p_message_id, gen_random_uuid()), v_conv, v_cid, v_uid, p_sender_device_num)
    returning * into v_msg;

  for e in select * from jsonb_array_elements(p_envelopes) loop
    if (e->>'recipient_id')::uuid not in (
      select member_a from public.couples where id = v_cid
      union
      select member_b from public.couples where id = v_cid
    ) then
      raise exception 'invalid_recipient';
    end if;
    insert into public.message_envelopes
      (message_id, couple_id, sender_id, sender_device_num,
       recipient_id, recipient_device_num, cipher_type, ciphertext)
    values (
      v_msg.id, v_cid, v_uid, p_sender_device_num,
      (e->>'recipient_id')::uuid, (e->>'recipient_device_num')::int,
      (e->>'cipher_type')::smallint, decode(e->>'ciphertext', 'hex')
    );
  end loop;

  update public.conversations set last_message_at = v_msg.created_at where id = v_conv;
  message_id := v_msg.id; created_at := v_msg.created_at; return next;
end;
$$;
grant execute on function public.send_message(integer, jsonb, uuid) to authenticated;
```
Verify: `supabase db reset`, then
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select count(*) from pg_proc where proname='send_message' and pronargs=3;"
```
Expected: `1`. **Do NOT `supabase db push`.**

- [ ] **Step 2: Repository passes the id**

In `chat_repository.dart`, add `String? messageId` to `sendEnvelopes` and include it in the RPC params:
```dart
Future<({String messageId, DateTime createdAt})> sendEnvelopes({
  required int senderDeviceNum,
  required List<EncryptedCopy> copies,
  String? messageId,
}) async {
  final envelopes = [ /* unchanged */ ];
  final rows = await _client.rpc('send_message', params: {
    'p_sender_device_num': senderDeviceNum,
    'p_envelopes': envelopes,
    if (messageId != null) 'p_message_id': messageId,
  });
  // ... unchanged parse ...
}
```

- [ ] **Step 3: Write the failing test**

In `chat_service_test.dart`, add (using the harness's fake repo; make `sendEnvelopes` throw for this case):
```dart
test('sendText stores a "sending" row, then "sent"; "failed" on send error', () async {
  // Happy path: after sendText, the local row exists with status 'sent'.
  await service.sendText('salam');
  final ok = (await store.watchConversation().first).last;
  expect(ok.body, 'salam');
  expect(ok.status, 'sent');

  // Failure path: make the fake repo's sendEnvelopes throw once.
  repo.failNextSend = true; // add this flag to the fake repo
  await service.sendText('offline msg');
  final failed = (await store.watchConversation().first)
      .firstWhere((m) => m.body == 'offline msg');
  expect(failed.status, 'failed',
      reason: 'a failed send must leave a retryable failed row, not vanish');
});
```

- [ ] **Step 4: Run to verify RED**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL — a failed send currently stores nothing.

- [ ] **Step 5: Optimistic `sendText`**

In `chat_service.dart`, import uuid (`import 'package:uuid/uuid.dart';` — already a dependency) and rewrite `sendText`:
```dart
Future<void> sendText(String body, {String? replyToMessageId}) async {
  final id = const Uuid().v4();
  final now = DateTime.now();
  // Optimistic row shown immediately.
  await store.upsertMessage(
    id: id, senderId: selfUserId, body: body,
    replyToMessageId: replyToMessageId, createdAt: now, status: 'sending',
  );
  try {
    final payload = TextPayload(body: body, replyToMessageId: replyToMessageId);
    final copies = await session.encryptFor(
        recipientUserId: spouseUserId, plaintext: encodePayload(payload));
    await repo.sendEnvelopes(
        senderDeviceNum: selfDeviceNum, copies: copies, messageId: id);
    await store.setStatus(id, 'sent');
  } catch (_) {
    await store.setStatus(id, 'failed');
  }
}
```
(The client-generated `id` is the server message id via `p_message_id`, so receipts from Task 2 update this same row.)

- [ ] **Step 6: Fire-safe `_send`**

In `chat_screen.dart`, make `_send` not swallow async errors and not depend on the future for clearing (the optimistic row already renders):
```dart
void _send(ChatService? service) {
  final text = _controller.text.trim();
  if (text.isEmpty || service == null) return;
  final replyToMessageId = _replyToMessageId;
  // Fire-and-forget: sendText handles its own failure by marking the row
  // 'failed'; we must not leave an unhandled async error.
  unawaited(service.sendText(text, replyToMessageId: replyToMessageId));
  _controller.clear();
  setState(() { _replyToMessageId = null; _replyPreview = null; });
}
```
Add `import 'dart:async';` for `unawaited` if not present.

- [ ] **Step 7: Run tests + verify migration**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/chat`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260719000001_send_message_client_id.sql lib/features/chat/data/chat_repository.dart lib/features/chat/domain/chat_service.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_service_test.dart
git commit -m "fix(chat): optimistic send with client id + failed state (I2)"
```

---

## Task 4 (I3 — Important): bounded retry / dead-letter for undecryptable envelopes

**Problem:** `handleInboxRow` returns on decrypt failure without any counter and never sets `fetched_at`, so a genuinely-undecryptable envelope re-decrypts a spent ciphertext every tick forever.

**Files:**
- Modify: `lib/features/chat/domain/chat_service.dart`
- Test: `test/features/chat/chat_service_test.dart`

**Interfaces:**
- Produces: bounded in-memory retry in `ChatService`; after `maxDecryptAttempts` failures for one envelope id, the envelope is dead-lettered (deleted) so the loop ends. (In-memory is sufficient: a dead-letter delete persists, so a corrupt envelope survives at most one session's worth of retries.)

- [ ] **Step 1: Write the failing test**

```dart
test('an undecryptable envelope is retried then dead-lettered, not looped forever', () async {
  // env addressed to OUR device but with garbage ciphertext that never decrypts.
  final env = {
    'id': 'bad-env', 'message_id': 'm-bad',
    'sender_id': spouseId, 'sender_device_num': 1,
    'recipient_device_num': service.selfDeviceNum,
    'cipher_type': 2, 'ciphertext': 'deadbeef',
    'created_at': DateTime(2026).toIso8601String(),
  };
  // Below the threshold: retried, NOT deleted.
  for (var i = 0; i < ChatService.maxDecryptAttempts - 1; i++) {
    await service.handleInboxRow(env);
  }
  expect(repo.deleteEnvelopeCalls, isEmpty);
  // The attempt that reaches the threshold dead-letters it.
  await service.handleInboxRow(env);
  expect(repo.deleteEnvelopeCalls, contains('bad-env'));
  // Further ticks do nothing (already dead-lettered / not re-added).
  await service.handleInboxRow(env);
  expect(repo.deleteEnvelopeCalls.where((e) => e == 'bad-env').length, 1);
});
```

- [ ] **Step 2: Run to verify RED**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL — `maxDecryptAttempts` undefined / envelope never deleted.

- [ ] **Step 3: Implement bounded retry**

In `chat_service.dart`, add a field + constant and update the decrypt-failure branch:
```dart
static const int maxDecryptAttempts = 8;
final Map<String, int> _decryptAttempts = {};
```
In `handleInboxRow`, replace the `catch (_) { return; }` block with:
```dart
} catch (_) {
  final id = env['id'] as String?;
  if (id == null) return;
  final n = (_decryptAttempts[id] ?? 0) + 1;
  _decryptAttempts[id] = n;
  if (n >= maxDecryptAttempts) {
    // Unrecoverable (corrupt, or a session we can never rebuild). Dead-letter
    // it so the inbox stream stops re-delivering it every tick.
    _decryptAttempts.remove(id);
    await repo.deleteEnvelope(id);
  }
  return; // otherwise leave it for the next tick
}
```
On a SUCCESSFUL decrypt, clear any counter for that id (right after `payload = decodePayload(...)`): `_decryptAttempts.remove(env['id']);`.

- [ ] **Step 4: Run to verify GREEN**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + commit**

Run: `flutter test`
Expected: All pass.
```bash
git add lib/features/chat/domain/chat_service.dart test/features/chat/chat_service_test.dart
git commit -m "fix(chat): bounded retry + dead-letter for undecryptable envelopes (I3)"
```

---

## Self-Review

**Coverage:** C1 → Task 1 (device guard + sibling-envelope test). I1 → Task 2 (applyReceipt + receiptPump + screen). I2 → Task 3 (client id migration + optimistic/failed send). I3 → Task 4 (bounded retry/dead-letter). ✅

**Ordering:** Tasks 1 and 4 both edit `handleInboxRow`; run sequentially (1 before 4) so 4 builds on 1's guarded version. Task 3's migration is independent.

**Type consistency:** `ChatService.selfDeviceNum`/`selfUserId` (existing fields), `ChatStore.applyReceipt`/`setStatus`/`upsertMessage`, `ChatRepository.sendEnvelopes({messageId})`/`watchMyMessages`, `maxDecryptAttempts` used consistently.

**Open items:** the fake `ChatRepository` in `chat_service_test.dart` needs a `deleteEnvelopeCalls` list and a `failNextSend` flag if not already present — the implementer adds these to the existing fake.
