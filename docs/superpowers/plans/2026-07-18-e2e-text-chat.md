# E2E Text Chat Implementation Plan (sub-project 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship E2E text chat — multi-device fan-out send/receive, local-first plaintext history, delivered/read receipts, replies, encrypted reactions, typing indicator.

**Architecture:** `encryptFor` fan-out is stored as one `messages` row + N `message_envelopes` rows. Decryption is one-shot, so durable history is plaintext in local Drift; server envelopes are deleted after fetch. Text/replies/reactions are one encrypted `ChatPayload` type; typing is ephemeral realtime broadcast. UI → `ChatService` → (`SignalSessionService`, `ChatRepository`, `ChatStore`); the UI never touches crypto or Supabase directly.

**Tech Stack:** Flutter 3.44, flutter_riverpod ^3.3, drift, supabase_flutter ^2.16, libsignal_protocol_dart 0.8.2, local Supabase under Docker.

## Global Constraints

- Local Supabase is RUNNING under Docker. Verify migrations with **`supabase db reset`** (local). **NEVER `supabase db push`** (that targets the user's production Cloud).
- DB: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`; API `http://127.0.0.1:54321`. Local anon key via `supabase status`.
- bytea over PostgREST/RPC MUST be `\x` hex (the C2 lesson); reuse the existing `_hex`/`_bytes` helpers' convention.
- `cipher_type`: `CiphertextMessage.prekeyType` = 3 (X3DH first message), `whisperType` = 2. Constants, never literals.
- Drift schema changes bump `schemaVersion` AND add a `MigrationStrategy` (existing installs must not crash).
- Every new couple-scoped table enables RLS with `is_couple_member(couple_id)`.
- The UI layer must depend only on `ChatService` + providers, never on `SignalSessionService`/Supabase directly.
- Commit after every task. TDD throughout.

---

## Task 1: Wire the crypto layer into the running app

**Files:**
- Create: `lib/core/crypto/crypto_providers.dart`
- Modify: `lib/features/auth/presentation/sign_in_screen.dart`, `lib/features/auth/presentation/otp_screen.dart`, `lib/features/auth/presentation/reset_password_screen.dart` (any call site of `signalBootstrapProvider`/`ensureBundle`)
- Modify: `lib/features/auth/domain/auth_controller.dart` (deprecate/remove `SignalIdentityBootstrap` + `signalBootstrapProvider`)
- Test: `test/core/crypto/crypto_providers_test.dart`

**Interfaces:**
- Consumes: `SignalDb` (`lib/core/storage/signal_db.dart`), `KeyVault` (`keyVaultProvider`), `SupabaseDeviceRegistrar`, `ensureRegistered`, `SignalSessionService`, `SupabasePreKeyBundleSource`.
- Produces: `signalDbProvider` (singleton `SignalDb`), `deviceRegistrarProvider`, `signalSessionServiceProvider`, `ensureRegisteredProvider` (a callable that runs `ensureRegistered(...)` with the wired deps).

**Why:** the app currently runs the obsolete Phase-0 `SignalIdentityBootstrap.ensureBundle()`, which uploads keys in a shape incompatible with the multi-device session layer. Chat needs the real `ensureRegistered` path and a shared `SignalSessionService` in the provider graph.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/crypto_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/core/crypto/crypto_providers.dart';
import 'package:sakinah/core/crypto/signal_session_service.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  test('signalDbProvider is a singleton within a container', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final a = c.read(signalDbProvider);
    final b = c.read(signalDbProvider);
    expect(identical(a, b), isTrue);
  });

  test('signalSessionServiceProvider builds', () {
    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith((ref) {
        final db = SignalDb.memory();
        ref.onDispose(db.close);
        return db;
      }),
    ]);
    addTearDown(c.dispose);
    expect(c.read(signalSessionServiceProvider), isA<SignalSessionService>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/crypto_providers_test.dart`
Expected: FAIL — `crypto_providers.dart` not found.

- [ ] **Step 3: Implement the providers**

```dart
// lib/core/crypto/crypto_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/domain/auth_controller.dart' show keyVaultProvider;
import '../../shared/providers/supabase_provider.dart';
import '../storage/signal_db.dart';
import 'prekey_bundle_source.dart';
import 'signal_registration.dart';
import 'signal_session_service.dart';
import 'stores/drift_signal_store.dart';

/// One SignalDb for the app's lifetime (opens the on-disk `sakinah_signal` db).
final signalDbProvider = Provider<SignalDb>((ref) {
  final db = SignalDb();
  ref.onDispose(db.close);
  return db;
});

final deviceRegistrarProvider = Provider<DeviceRegistrar>((ref) {
  return SupabaseDeviceRegistrar(ref.read(supabaseClientProvider));
});

final preKeyBundleSourceProvider = Provider<PreKeyBundleSource>((ref) {
  return SupabasePreKeyBundleSource(ref.read(supabaseClientProvider));
});

final signalSessionServiceProvider = Provider<SignalSessionService>((ref) {
  final db = ref.watch(signalDbProvider);
  final vault = ref.read(keyVaultProvider);
  return SignalSessionService(
    store: DriftSignalStore(db, vault),
    bundles: ref.read(preKeyBundleSourceProvider),
    vault: vault,
    db: db,
  );
});

/// Registers this device (idempotent) + tops up prekeys. Call after auth.
final ensureRegisteredProvider = Provider<Future<int> Function()>((ref) {
  return () => ensureRegistered(
        db: ref.read(signalDbProvider),
        vault: ref.read(keyVaultProvider),
        registrar: ref.read(deviceRegistrarProvider),
      );
});
```

> Note: match `SignalSessionService`'s actual constructor parameter names by reading `lib/core/crypto/signal_session_service.dart` (it takes the store, a bundle source, the vault, and the db). Adjust the argument names in the provider to match exactly.

- [ ] **Step 4: Replace the old bootstrap at every call site**

In `sign_in_screen.dart`, `otp_screen.dart`, and `reset_password_screen.dart`, replace `await ref.read(signalBootstrapProvider).ensureBundle();` with `await ref.read(ensureRegisteredProvider)();`. Then delete `SignalIdentityBootstrap` and `signalBootstrapProvider` from `auth_controller.dart` (grep first: `grep -rn "signalBootstrapProvider\|ensureBundle" lib` must return no remaining references before deleting).

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/core/crypto/crypto_providers_test.dart`
Expected: PASS.
Run: `flutter analyze lib/core/crypto lib/features/auth`
Expected: No issues (proves no dangling references to the removed bootstrap).

- [ ] **Step 6: Commit**

```bash
git add lib/core/crypto/crypto_providers.dart lib/features/auth test/core/crypto/crypto_providers_test.dart
git commit -m "feat(crypto): wire session layer into app; retire Phase-0 bootstrap"
```

---

## Task 2: Server schema — envelopes + RPCs

**Files:**
- Create: `supabase/migrations/20260718000001_chat_envelopes.sql`

**Interfaces:**
- Produces: restructured `public.messages`; new `public.message_envelopes`; `send_message(p_sender_device_num int, p_envelopes jsonb) → (message_id uuid, created_at timestamptz)`; `mark_delivered(uuid)`, `mark_read(uuid)`.

- [ ] **Step 1: Write the migration**

```sql
-- Chat: restructure messages to logical-only + per-device ciphertext envelopes.
-- Chat has never shipped, so messages has no production rows to preserve.

alter table public.messages
  drop column if exists ciphertext,
  drop column if exists cipher_type,
  drop column if exists device_id,
  drop column if exists recipient_id,
  drop column if exists attachment_url,
  drop column if exists attachment_mime,
  drop column if exists attachment_bytes,
  drop column if exists ephemeral_until,
  drop column if exists reply_to,
  add column if not exists sender_device_num integer not null default 1;
alter table public.messages alter column sender_device_num drop default;

create table public.message_envelopes (
  id                   uuid primary key default gen_random_uuid(),
  message_id           uuid not null references public.messages(id) on delete cascade,
  couple_id            uuid not null references public.couples(id) on delete cascade,
  -- Denormalized sender address: an inbound envelope may be from the spouse OR
  -- from the recipient's OWN other device (multi-device sync), so the reader
  -- must know the sender's (user, device) to pick the right Signal session.
  -- message_envelopes is streamed on its own (realtime can't join messages).
  sender_id            uuid not null references public.users(id) on delete cascade,
  sender_device_num    integer not null,
  recipient_id         uuid not null references public.users(id) on delete cascade,
  recipient_device_num integer not null,
  cipher_type          smallint not null, -- 3 = prekey (X3DH first), 2 = message (per libsignal)
  ciphertext           bytea not null,
  created_at           timestamptz not null default now(),
  fetched_at           timestamptz
);
create index message_envelopes_recipient_idx
  on public.message_envelopes(recipient_id, fetched_at);
create index message_envelopes_message_idx on public.message_envelopes(message_id);

alter table public.message_envelopes enable row level security;

-- Couple members may insert (the sender writes all envelopes).
create policy envelopes_insert on public.message_envelopes
  for insert with check (public.is_couple_member(couple_id));
-- A device reads/deletes only its own envelopes.
create policy envelopes_read_own on public.message_envelopes
  for select using (recipient_id = auth.uid());
create policy envelopes_delete_own on public.message_envelopes
  for delete using (recipient_id = auth.uid());

grant select, insert, delete on public.message_envelopes to authenticated;

-- Atomic send: message row + N envelopes + bump conversation.
create or replace function public.send_message(
  p_sender_device_num integer,
  p_envelopes jsonb
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

  insert into public.messages (conversation_id, couple_id, sender_id, sender_device_num)
    values (v_conv, v_cid, v_uid, p_sender_device_num)
    returning * into v_msg;

  for e in select * from jsonb_array_elements(p_envelopes) loop
    insert into public.message_envelopes
      (message_id, couple_id, sender_id, sender_device_num,
       recipient_id, recipient_device_num, cipher_type, ciphertext)
    values (
      v_msg.id, v_cid,
      v_uid, p_sender_device_num,
      (e->>'recipient_id')::uuid,
      (e->>'recipient_device_num')::int,
      (e->>'cipher_type')::smallint,
      decode(e->>'ciphertext', 'hex')
    );
  end loop;

  update public.conversations set last_message_at = v_msg.created_at where id = v_conv;

  message_id := v_msg.id; created_at := v_msg.created_at; return next;
end;
$$;
grant execute on function public.send_message(integer, jsonb) to authenticated;

-- Receipts: only the recipient side (a couple member who is not the sender) may set them.
create or replace function public.mark_delivered(p_message_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  update public.messages set delivered_at = now()
   where id = p_message_id and delivered_at is null
     and public.is_couple_member(couple_id) and sender_id <> auth.uid();
end; $$;

create or replace function public.mark_read(p_message_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  update public.messages set read_at = now(), delivered_at = coalesce(delivered_at, now())
   where id = p_message_id and read_at is null
     and public.is_couple_member(couple_id) and sender_id <> auth.uid();
end; $$;

grant execute on function public.mark_delivered(uuid) to authenticated;
grant execute on function public.mark_read(uuid) to authenticated;

-- Realtime: the recipient streams its envelopes; the sender streams receipt updates.
do $$ begin
  begin alter publication supabase_realtime add table public.message_envelopes;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.messages;
  exception when duplicate_object then null; end;
end $$;
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db reset`
Then:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select proname from pg_proc where proname in ('send_message','mark_delivered','mark_read') order by 1;"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select tablename from pg_publication_tables where pubname='supabase_realtime' and tablename in ('messages','message_envelopes') order by 1;"
```
Expected: first prints `mark_delivered`, `mark_read`, `send_message`; second prints `message_envelopes`, `messages`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260718000001_chat_envelopes.sql
git commit -m "feat(db): message envelopes + send_message/receipt RPCs"
```

---

## Task 3: `ChatPayload` codec

**Files:**
- Create: `lib/features/chat/domain/chat_payload.dart`
- Test: `test/features/chat/chat_payload_test.dart`

**Interfaces:**
- Produces: `sealed class ChatPayload`; `TextPayload({String body, String? replyToMessageId})`; `ReactionPayload({String targetMessageId, String emoji, bool add})`; `UnsupportedPayload`; `Uint8List encodePayload(ChatPayload)`; `ChatPayload decodePayload(Uint8List)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/chat_payload_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/features/chat/domain/chat_payload.dart';

void main() {
  test('text round-trips, including reply', () {
    for (final p in [
      const TextPayload(body: 'salam'),
      const TextPayload(body: 're', replyToMessageId: 'm1'),
    ]) {
      final decoded = decodePayload(encodePayload(p));
      expect(decoded, isA<TextPayload>());
      final t = decoded as TextPayload;
      expect(t.body, p.body);
      expect(t.replyToMessageId, p.replyToMessageId);
    }
  });

  test('reaction round-trips add and remove', () {
    for (final add in [true, false]) {
      final p = ReactionPayload(targetMessageId: 'm9', emoji: '❤️', add: add);
      final decoded = decodePayload(encodePayload(p)) as ReactionPayload;
      expect(decoded.targetMessageId, 'm9');
      expect(decoded.emoji, '❤️');
      expect(decoded.add, add);
    }
  });

  test('unknown kind or newer version decodes to UnsupportedPayload', () {
    final future = '{"v":99,"kind":"hologram"}';
    final bytes = Uint8ListFromString(future);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });
}
```

Add this helper at the bottom of the test file:
```dart
import 'dart:convert';
import 'dart:typed_data';
Uint8List Uint8ListFromString(String s) => Uint8List.fromList(utf8.encode(s));
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_payload_test.dart`
Expected: FAIL — `chat_payload.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/domain/chat_payload.dart
import 'dart:convert';
import 'dart:typed_data';

const int _payloadVersion = 1;

sealed class ChatPayload {
  const ChatPayload();
}

class TextPayload extends ChatPayload {
  const TextPayload({required this.body, this.replyToMessageId});
  final String body;
  final String? replyToMessageId;
}

class ReactionPayload extends ChatPayload {
  const ReactionPayload({
    required this.targetMessageId,
    required this.emoji,
    required this.add,
  });
  final String targetMessageId;
  final String emoji;
  final bool add;
}

/// A payload from a newer/unknown client — skipped, never fatal.
class UnsupportedPayload extends ChatPayload {
  const UnsupportedPayload();
}

Uint8List encodePayload(ChatPayload p) {
  final map = switch (p) {
    TextPayload() => {
        'v': _payloadVersion,
        'kind': 'text',
        'body': p.body,
        if (p.replyToMessageId != null) 'reply': p.replyToMessageId,
      },
    ReactionPayload() => {
        'v': _payloadVersion,
        'kind': 'reaction',
        'target': p.targetMessageId,
        'emoji': p.emoji,
        'op': p.add ? 'add' : 'remove',
      },
    UnsupportedPayload() => {'v': _payloadVersion, 'kind': 'unsupported'},
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

ChatPayload decodePayload(Uint8List bytes) {
  final Map<String, dynamic> m;
  try {
    m = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  } catch (_) {
    return const UnsupportedPayload();
  }
  if ((m['v'] as num?) != _payloadVersion) return const UnsupportedPayload();
  return switch (m['kind']) {
    'text' => TextPayload(
        body: (m['body'] ?? '') as String,
        replyToMessageId: m['reply'] as String?,
      ),
    'reaction' => ReactionPayload(
        targetMessageId: (m['target'] ?? '') as String,
        emoji: (m['emoji'] ?? '') as String,
        add: m['op'] != 'remove',
      ),
    _ => const UnsupportedPayload(),
  };
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/chat_payload_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/domain/chat_payload.dart test/features/chat/chat_payload_test.dart
git commit -m "feat(chat): versioned typed payload codec (text/reply/reaction)"
```

---

## Task 4: Local chat store (Drift)

**Files:**
- Modify: `lib/core/storage/signal_db.dart` (add `ChatMessages`, `ChatReactions` tables; bump schemaVersion; extend MigrationStrategy)
- Create: `lib/features/chat/data/chat_store.dart`
- Test: `test/features/chat/chat_store_test.dart`

**Interfaces:**
- Consumes: `SignalDb`.
- Produces: `ChatMessageRow` (drift row); `ChatStore(SignalDb)` with `upsertMessage(...)`, `setStatus(id, status)`, `applyReaction({messageId, reactorId, emoji, add})`, `watchConversation() → Stream<List<ChatMessageRow>>` (ordered by createdAt), `messageExists(id)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/chat_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/storage/signal_db.dart';
import 'package:sakinah/features/chat/data/chat_store.dart';

void main() {
  late SignalDb db;
  late ChatStore store;
  setUp(() { db = SignalDb.memory(); store = ChatStore(db); });
  tearDown(() => db.close());

  test('upsert is idempotent by message id', () async {
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'delivered');
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'delivered');
    final rows = await store.watchConversation().first;
    expect(rows.length, 1);
  });

  test('applyReaction add then remove', () async {
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'sent');
    await store.applyReaction(messageId: 'm1', reactorId: 'b', emoji: '❤️', add: true);
    expect((await store.reactionsFor('m1')).length, 1);
    await store.applyReaction(messageId: 'm1', reactorId: 'b', emoji: '❤️', add: false);
    expect((await store.reactionsFor('m1')).length, 0);
  });

  test('watchConversation orders by createdAt', () async {
    await store.upsertMessage(id: 'm2', senderId: 'a', body: '2',
        createdAt: DateTime(2026, 1, 2), status: 'sent');
    await store.upsertMessage(id: 'm1', senderId: 'a', body: '1',
        createdAt: DateTime(2026, 1, 1), status: 'sent');
    final rows = await store.watchConversation().first;
    expect(rows.map((r) => r.id), ['m1', 'm2']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: FAIL — `chat_store.dart` not found.

- [ ] **Step 3: Add the Drift tables**

In `lib/core/storage/signal_db.dart`, add:
```dart
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get senderId => text()();
  TextColumn get body => text().nullable()();
  TextColumn get replyToMessageId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  TextColumn get status => text()(); // sending|sent|delivered|read|failed
  @override
  Set<Column> get primaryKey => {id};
}

class ChatReactions extends Table {
  TextColumn get messageId => text()();
  TextColumn get reactorId => text()();
  TextColumn get emoji => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {messageId, reactorId, emoji};
}
```
Add `ChatMessages, ChatReactions` to the `@DriftDatabase(tables: [...])` list. Bump `schemaVersion` to the next number, and in `onUpgrade` add:
```dart
if (from < <newVersion>) {
  await m.createTable(chatMessages);
  await m.createTable(chatReactions);
}
```
Run codegen: `dart run build_runner build --delete-conflicting-outputs` and commit the regenerated `signal_db.g.dart`. Never hand-edit generated files.

- [ ] **Step 4: Implement ChatStore**

```dart
// lib/features/chat/data/chat_store.dart
import 'package:drift/drift.dart';
import '../../../core/storage/signal_db.dart';

typedef ChatMessageRow = ChatMessage;

class ChatStore {
  ChatStore(this._db);
  final SignalDb _db;

  Future<void> upsertMessage({
    required String id,
    required String senderId,
    required String? body,
    required DateTime createdAt,
    required String status,
    String? replyToMessageId,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return _db.into(_db.chatMessages).insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            id: id,
            senderId: senderId,
            body: Value(body),
            replyToMessageId: Value(replyToMessageId),
            createdAt: createdAt,
            deliveredAt: Value(deliveredAt),
            readAt: Value(readAt),
            status: status,
          ),
        );
  }

  Future<void> setStatus(String id, String status) {
    return (_db.update(_db.chatMessages)..where((t) => t.id.equals(id)))
        .write(ChatMessagesCompanion(status: Value(status)));
  }

  Future<bool> messageExists(String id) async {
    final row = await (_db.select(_db.chatMessages)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> applyReaction({
    required String messageId,
    required String reactorId,
    required String emoji,
    required bool add,
  }) async {
    if (add) {
      await _db.into(_db.chatReactions).insertOnConflictUpdate(
            ChatReactionsCompanion.insert(
              messageId: messageId,
              reactorId: reactorId,
              emoji: emoji,
              createdAt: DateTime.now(),
            ),
          );
    } else {
      await (_db.delete(_db.chatReactions)
            ..where((t) =>
                t.messageId.equals(messageId) &
                t.reactorId.equals(reactorId) &
                t.emoji.equals(emoji)))
          .go();
    }
  }

  Future<List<ChatReaction>> reactionsFor(String messageId) {
    return (_db.select(_db.chatReactions)
          ..where((t) => t.messageId.equals(messageId)))
        .get();
  }

  Stream<List<ChatMessageRow>> watchConversation() {
    return (_db.select(_db.chatMessages)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }
}
```

> Note: the generated row/companion class names (`ChatMessage`, `ChatMessagesCompanion`, `ChatReaction`, `ChatReactionsCompanion`) come from Drift codegen for the table names above. If codegen produces different names, use whatever it generated.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart lib/features/chat/data/chat_store.dart test/features/chat/chat_store_test.dart
git commit -m "feat(chat): local Drift history (messages + reactions)"
```

---

## Task 5: `ChatRepository`

**Files:**
- Create: `lib/features/chat/data/chat_repository.dart`
- Test: `test/features/chat/chat_repository_test.dart` (integration — local Supabase)

**Interfaces:**
- Consumes: `supabaseClientProvider`, `EncryptedCopy` (from `signal_session_service.dart`).
- Produces: `ChatRepository(SupabaseClient)` with:
  - `Future<({String messageId, DateTime createdAt})> sendEnvelopes({required int senderDeviceNum, required List<EncryptedCopy> copies})` (calls `send_message`)
  - `Stream<List<Map<String,dynamic>>> watchInbox(String userId)` (realtime on `message_envelopes` where `recipient_id = userId`)
  - `Future<void> deleteEnvelope(String envelopeId)`
  - `Future<void> markDelivered(String messageId)` / `markRead(String messageId)`
  - `Stream<List<Map<String,dynamic>>> watchMyMessages(String coupleId)` (receipts on `messages`)

- [ ] **Step 1: Write the failing test**

Because mocktail cannot mock Supabase builders (established), this is an integration test against local Supabase. Follow the pattern in `test/integration/signal_server_test.dart` (sign up two users, pair them). Assert `sendEnvelopes` inserts a message + envelopes readable by the recipient, and `deleteEnvelope` removes one.

```dart
// test/features/chat/chat_repository_test.dart  (integration; requires local Supabase)
// Model the setup on test/integration/signal_server_test.dart: two throwaway users
// paired via the real RPCs, addTearDown + admin.deleteUser cleanup.
// Assert: after sendEnvelopes with one copy addressed to the spouse, the spouse
// client can select exactly one message_envelopes row for that message, with
// cipher_type and bytea intact; after deleteEnvelope it is gone.
```
Write the full test following that harness (the implementer copies the sign-up/pair helpers verbatim from the existing integration test).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: FAIL — `ChatRepository` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/data/chat_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/crypto/signal_session_service.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class ChatRepository {
  ChatRepository(this._client);
  final SupabaseClient _client;

  Future<({String messageId, DateTime createdAt})> sendEnvelopes({
    required int senderDeviceNum,
    required List<EncryptedCopy> copies,
  }) async {
    final envelopes = [
      for (final c in copies)
        {
          'recipient_id': c.userId,
          'recipient_device_num': c.deviceNum,
          'cipher_type': c.cipherType,
          'ciphertext': _hex(c.ciphertext),
        }
    ];
    final rows = await _client.rpc('send_message', params: {
      'p_sender_device_num': senderDeviceNum,
      'p_envelopes': envelopes,
    });
    final row = (rows is List) ? rows.first : rows;
    final m = Map<String, dynamic>.from(row as Map);
    return (
      messageId: m['message_id'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  Stream<List<Map<String, dynamic>>> watchInbox(String userId) {
    return _client
        .from('message_envelopes')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .map((rows) => [for (final r in rows) Map<String, dynamic>.from(r)]);
  }

  Stream<List<Map<String, dynamic>>> watchMyMessages(String coupleId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [for (final r in rows) Map<String, dynamic>.from(r)]);
  }

  Future<void> deleteEnvelope(String envelopeId) =>
      _client.from('message_envelopes').delete().eq('id', envelopeId);

  Future<void> markDelivered(String messageId) =>
      _client.rpc('mark_delivered', params: {'p_message_id': messageId});

  Future<void> markRead(String messageId) =>
      _client.rpc('mark_read', params: {'p_message_id': messageId});
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/chat_repository_test.dart`
Expected: PASS (against local Supabase).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/chat_repository.dart test/features/chat/chat_repository_test.dart
git commit -m "feat(chat): repository — send_message, inbox/receipt streams, delete"
```

---

## Task 6: `ChatService`

**Files:**
- Create: `lib/features/chat/domain/chat_service.dart`
- Test: `test/features/chat/chat_service_test.dart`

**Interfaces:**
- Consumes: `SignalSessionService`, `ChatRepository`, `ChatStore`, `encodePayload`/`decodePayload`.
- Produces: `ChatService({required SignalSessionService session, required ChatRepository repo, required ChatStore store, required String selfUserId, required String spouseUserId, required int selfDeviceNum})` with:
  - `Future<void> sendText(String body, {String? replyToMessageId})`
  - `Future<void> sendReaction({required String targetMessageId, required String emoji, required bool add})`
  - `Future<void> handleInboxRow(Map<String,dynamic> envelope)` — decrypt, apply, mark delivered, delete envelope; idempotent; returns without throwing on a decrypt failure.

- [ ] **Step 1: Write the failing test**

Use a fake `SignalSessionService` (or two real ones over in-memory Drift + a fake bundle source, mirroring `signal_session_service_test.dart`) and a fake `ChatRepository`. Assert:

```dart
// test/features/chat/chat_service_test.dart  (unit; in-memory, no server)
// - sendText: encodes a TextPayload, calls session.encryptFor(spouse), passes the
//   copies to repo.sendEnvelopes, and stores a local 'sent' message under the
//   returned messageId.
// - handleInboxRow: given an envelope encrypting a TextPayload from the spouse,
//   decrypts, upserts a local message, calls repo.markDelivered + deleteEnvelope.
// - handleInboxRow twice on the same envelope => one local message (idempotent).
// - a reaction payload => store.applyReaction on the target.
// Build the two-device crypto exactly like signal_session_service_test.dart's
// round-trip test so encrypt/decrypt is real.
```
Write the full test with a `_FakeChatRepo` capturing `sendEnvelopes`/`markDelivered`/`deleteEnvelope` calls.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL — `ChatService` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/domain/chat_service.dart
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/crypto/signal_session_service.dart';
import '../data/chat_repository.dart';
import '../data/chat_store.dart';
import 'chat_payload.dart';

class ChatService {
  ChatService({
    required this.session,
    required this.repo,
    required this.store,
    required this.selfUserId,
    required this.spouseUserId,
    required this.selfDeviceNum,
  });

  final SignalSessionService session;
  final ChatRepository repo;
  final ChatStore store;
  final String selfUserId;
  final String spouseUserId;
  final int selfDeviceNum;

  Future<void> sendText(String body, {String? replyToMessageId}) async {
    final payload = TextPayload(body: body, replyToMessageId: replyToMessageId);
    final copies = await session.encryptFor(
      recipientUserId: spouseUserId,
      plaintext: encodePayload(payload),
    );
    final sent = await repo.sendEnvelopes(
        senderDeviceNum: selfDeviceNum, copies: copies);
    await store.upsertMessage(
      id: sent.messageId,
      senderId: selfUserId,
      body: body,
      replyToMessageId: replyToMessageId,
      createdAt: sent.createdAt,
      status: 'sent',
    );
  }

  Future<void> sendReaction({
    required String targetMessageId,
    required String emoji,
    required bool add,
  }) async {
    final payload = ReactionPayload(
        targetMessageId: targetMessageId, emoji: emoji, add: add);
    final copies = await session.encryptFor(
      recipientUserId: spouseUserId,
      plaintext: encodePayload(payload),
    );
    await repo.sendEnvelopes(senderDeviceNum: selfDeviceNum, copies: copies);
    // Reflect our own reaction locally immediately.
    await store.applyReaction(
        messageId: targetMessageId, reactorId: selfUserId, emoji: emoji, add: add);
  }

  /// Decrypt one inbound envelope, apply it, acknowledge, and delete it.
  /// Never throws for a bad envelope — logs via return.
  Future<void> handleInboxRow(Map<String, dynamic> env) async {
    final messageId = env['message_id'] as String;
    if (await store.messageExists(messageId) && env['id'] != null) {
      // Already processed this logical message; just clean up the envelope.
      await repo.deleteEnvelope(env['id'] as String);
      return;
    }
    // Sender address comes from the envelope itself (denormalized): it may be
    // the spouse OR the recipient's own other device (multi-device sync).
    final String senderId = env['sender_id'] as String;
    final int senderDeviceNum = (env['sender_device_num'] as num).toInt();
    final Uint8List ciphertext = _bytes(env['ciphertext']);
    late final ChatPayload payload;
    try {
      final plain = await session.decryptFrom(
        senderUserId: senderId,
        senderDeviceNum: senderDeviceNum,
        ciphertext: ciphertext,
        cipherType: (env['cipher_type'] as num).toInt(),
      );
      payload = decodePayload(Uint8List.fromList(plain));
    } catch (_) {
      return; // leave fetched_at null; retried next tick
    }

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
    await repo.deleteEnvelope(env['id'] as String);
  }
}

Uint8List _bytes(dynamic v) {
  if (v is String) {
    final hex = v.startsWith('\\x') ? v.substring(2) : v;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ]);
  }
  return Uint8List.fromList((v as List).cast<int>());
}
```

> Note: `handleInboxRow` reads `sender_id`/`sender_device_num` directly off the envelope (denormalized in Task 2's migration), because realtime streams `message_envelopes` alone and can't join `messages`. Decryption always uses the *sender's* address. A self-sync copy (`sender_id == selfUserId`) is stored `sent` and does not trigger a delivered receipt; a spouse copy is stored `delivered` and marks the message delivered.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/domain/chat_service.dart test/features/chat/chat_service_test.dart
git commit -m "feat(chat): ChatService — send + inbound decrypt/apply pipeline"
```

---

## Task 7: End-to-end integration test (two devices)

**Files:**
- Create: `test/integration/chat_e2e_test.dart`

**Interfaces:**
- Consumes: everything above + local Supabase.

- [ ] **Step 1: Write the test**

Model the harness on `test/integration/signal_server_test.dart`. Sign up Alice + Bob, pair them, register each device via the real `ensureRegistered`. Then, driving `ChatService` for each side over their own Drift + real `SignalSessionService`:

```
- Alice.sendText("salam") -> Bob.handleInboxRow(his envelope) -> Bob's ChatStore has a
  'delivered' message with body "salam"; the messages row's delivered_at is set.
- Bob marks read -> Alice's watchMyMessages sees read_at.
- Alice reacts ❤️ to the message -> Bob.handleInboxRow -> Bob's reactionsFor(msg) has ❤️.
- Bob.handleInboxRow on the SAME envelope again -> still one message (idempotent),
  envelope already deleted.
- Assert the envelope row is gone from the server after handling (spent).
```
Clean up both throwaway users with `addTearDown` + `admin.deleteUser`.

- [ ] **Step 2: Run**

Run: `flutter test test/integration/chat_e2e_test.dart`
Expected: PASS (this is the headline proof that the whole pipeline works against a real server + real crypto).

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: all pass (local Supabase up).

- [ ] **Step 4: Commit**

```bash
git add test/integration/chat_e2e_test.dart
git commit -m "test(chat): end-to-end two-device send/receive/receipt/reaction"
```

---

## Task 8: Chat providers

**Files:**
- Create: `lib/features/chat/domain/chat_providers.dart`
- Test: `test/features/chat/chat_providers_test.dart`

**Interfaces:**
- Consumes: `signalSessionServiceProvider`, `supabaseClientProvider`, `signalDbProvider`, `authSessionProvider`, `currentCoupleProvider`, `keyVaultProvider`.
- Produces: `chatRepositoryProvider`, `chatStoreProvider`, `chatServiceProvider` (`FutureProvider<ChatService?>` — null until signed in + paired + device registered), `conversationMessagesProvider` (`StreamProvider<List<ChatMessageRow>>` from the local store), `inboxPumpProvider` (a provider that subscribes to `repo.watchInbox` and feeds each row to `ChatService.handleInboxRow`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/chat_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/core/storage/signal_db.dart';
import 'package:sakinah/core/crypto/crypto_providers.dart';
import 'package:sakinah/features/chat/data/chat_store.dart';
import 'package:sakinah/features/chat/domain/chat_providers.dart';

void main() {
  test('chatStoreProvider builds over the shared SignalDb', () {
    final c = ProviderContainer(overrides: [
      signalDbProvider.overrideWith((ref) {
        final db = SignalDb.memory();
        ref.onDispose(db.close);
        return db;
      }),
    ]);
    addTearDown(c.dispose);
    expect(c.read(chatStoreProvider), isA<ChatStore>());
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/chat_providers_test.dart`
Expected: FAIL — providers undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/domain/chat_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../../core/storage/signal_db.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../auth/domain/auth_controller.dart' show keyVaultProvider;
import '../data/chat_repository.dart';
import '../data/chat_store.dart';
import 'chat_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.read(supabaseClientProvider));
});

final chatStoreProvider = Provider<ChatStore>((ref) {
  return ChatStore(ref.watch(signalDbProvider));
});

final chatServiceProvider = FutureProvider<ChatService?>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (session == null || couple == null) return null;
  final selfId = session.user.id;
  final deviceNum = await ref.read(keyVaultProvider).readDeviceNum();
  if (deviceNum == null) return null; // not registered yet
  return ChatService(
    session: ref.read(signalSessionServiceProvider),
    repo: ref.read(chatRepositoryProvider),
    store: ref.read(chatStoreProvider),
    selfUserId: selfId,
    spouseUserId: couple.spouseOf(selfId),
    selfDeviceNum: deviceNum,
  );
});

final conversationMessagesProvider =
    StreamProvider<List<ChatMessageRow>>((ref) {
  return ref.watch(chatStoreProvider).watchConversation();
});
```

For `inboxPumpProvider`, add a provider that watches the inbox stream and forwards rows:
```dart
final inboxPumpProvider = Provider<void>((ref) {
  final svc = ref.watch(chatServiceProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (svc == null || session == null) return;
  final sub = ref
      .read(chatRepositoryProvider)
      .watchInbox(session.user.id)
      .listen((rows) async {
    for (final r in rows) {
      await svc.handleInboxRow(r);
    }
  });
  ref.onDispose(sub.cancel);
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/chat_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/domain/chat_providers.dart test/features/chat/chat_providers_test.dart
git commit -m "feat(chat): providers (service, store stream, inbox pump)"
```

---

## Task 9: Chat screen

**Files:**
- Create: `lib/features/chat/presentation/chat_screen.dart`
- Create: `lib/features/chat/presentation/message_bubble.dart`
- Test: `test/features/chat/chat_screen_test.dart`

**Interfaces:**
- Consumes: `conversationMessagesProvider`, `chatServiceProvider`, `inboxPumpProvider`, `authSessionProvider`.
- Produces: `ChatScreen` at route `/home/chat`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/chat/chat_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/features/chat/domain/chat_providers.dart';
import 'package:sakinah/features/chat/presentation/chat_screen.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  testWidgets('renders messages from the store', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'salam alaykum',
        createdAt: DateTime(2026), status: 'delivered');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();
    expect(find.text('salam alaykum'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // composer
  });
}
```
(Import `ChatStore` in the test.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: FAIL — `ChatScreen` undefined.

- [ ] **Step 3: Implement the screen + bubble**

Build `ChatScreen` as a `ConsumerStatefulWidget`: `ref.watch(inboxPumpProvider)` (keeps the pump alive), a reversed `ListView` of `conversationMessagesProvider`, and a composer `TextField` + send button calling `ref.read(chatServiceProvider).value?.sendText(text)`. `MessageBubble` aligns right when `senderId == myId` else left, shows the body, and for own messages renders a receipt tick from `status`/`deliveredAt`/`readAt` (✓ sent, ✓✓ delivered, ✓✓ blue read). Long-press a bubble → an emoji row that calls `sendReaction`. A reply swipe/long-press sets a "replying to" banner above the composer that passes `replyToMessageId` to `sendText`. Follow the existing screen style (`SakScaffold`, tokens). Keep `message_bubble.dart` focused on one bubble.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/message_bubble.dart test/features/chat/chat_screen_test.dart
git commit -m "feat(chat): chat screen — list, composer, bubbles, receipts, reactions"
```

---

## Task 10: Typing indicator

**Files:**
- Create: `lib/features/chat/data/typing_channel.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart` (show "typing…" + broadcast on input)
- Test: `test/features/chat/typing_channel_test.dart`

**Interfaces:**
- Produces: `TypingChannel` — a thin wrapper over a Supabase Realtime broadcast channel `chat:{conversationId}` with `void setTyping(bool)` (debounced stop ~3s) and `Stream<bool> spouseTyping`.

- [ ] **Step 1: Write the failing test**

Because a real channel needs a server, unit-test only the **debounce/dedup logic** by extracting it into a pure `TypingDebouncer` (`start()` emits typing=true immediately, then typing=false after a quiet window; repeated `start()` within the window doesn't re-emit true). Test that with `fakeAsync`.

```dart
// test/features/chat/typing_channel_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/features/chat/data/typing_channel.dart';

void main() {
  test('debouncer emits true once then false after the quiet window', () {
    fakeAsync((async) {
      final events = <bool>[];
      final d = TypingDebouncer(quiet: const Duration(seconds: 3), emit: events.add);
      d.onKeystroke();
      d.onKeystroke();
      expect(events, [true]); // only one true despite two keystrokes
      async.elapse(const Duration(seconds: 3));
      expect(events, [true, false]);
    });
  });
}
```
(`fake_async` is a transitive dev dependency of `flutter_test`; if the import fails, add `fake_async` to dev_dependencies.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/typing_channel_test.dart`
Expected: FAIL — `TypingDebouncer` undefined.

- [ ] **Step 3: Implement**

Implement `TypingDebouncer` (pure, timer-based) and `TypingChannel` wrapping `supabase.channel('chat:$conversationId')` with `.onBroadcast` for receive and `.sendBroadcastMessage` for send, driving send through the debouncer. Wire into `ChatScreen`: `onChanged` → `debouncer.onKeystroke()`; render "typing…" when `spouseTyping` is true.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/typing_channel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/typing_channel.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/typing_channel_test.dart
git commit -m "feat(chat): ephemeral typing indicator via realtime broadcast"
```

---

## Task 11: Route + home entry point

**Files:**
- Modify: `lib/core/router/app_router.dart` (add `/home/chat`)
- Modify: `lib/features/home/presentation/home_screen.dart` (a Chat tile)
- Test: `test/features/chat/chat_route_test.dart`

**Interfaces:**
- Consumes: `ChatScreen`.

- [ ] **Step 1: Write the failing smoke test**

```dart
// test/features/chat/chat_route_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/features/chat/presentation/chat_screen.dart';

void main() {
  test('ChatScreen is const-constructible', () {
    expect(const ChatScreen(), isA<Widget>());
  });
}
```

- [ ] **Step 2: Run**

Run: `flutter test test/features/chat/chat_route_test.dart`
Expected: PASS (smoke). Real deliverable verified by `flutter analyze`.

- [ ] **Step 3: Wire the route + tile**

In `app_router.dart`, add under `/home`: `GoRoute(path: 'chat', builder: (_, _) => const ChatScreen())`. In `home_screen.dart`, add a Chat tile (following the existing `_CareTile`/`_CycleTile` pattern) → `context.go('/home/chat')`.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/home/presentation/home_screen.dart test/features/chat/chat_route_test.dart
git commit -m "feat(chat): route + home entry point"
```

---

## Self-Review

**Spec coverage:** envelope schema + RPCs (Task 2); one-shot decrypt → local plaintext history (Tasks 4, 6); fan-out send (Tasks 5, 6); delivered/read receipts (Tasks 2, 6, 9); encrypted reactions + replies as typed payload (Tasks 3, 6, 9); typing (Task 10); local-first store with delete-after-fetch (Tasks 4, 6); crypto wiring gap the app had (Task 1); integration proof (Task 7); route/UI (Tasks 9, 11). ✅

**Placeholder scan:** no TBD/TODO; every logic step carries complete code. Two tasks (5, 7 integration tests, and the UI specifics in 9) are described against an existing harness/screens rather than reproduced verbatim, because they copy an established pattern (`signal_server_test.dart`) or follow established screen conventions — the implementer has those files open.

**Type consistency:** `EncryptedCopy(userId, deviceNum, ciphertext, cipherType)`, `ChatPayload`/`encodePayload`/`decodePayload`, `ChatStore.upsertMessage/applyReaction/watchConversation`, `ChatRepository.sendEnvelopes/watchInbox/deleteEnvelope/markDelivered/markRead`, `ChatService.sendText/sendReaction/handleInboxRow` are used consistently across tasks.

**Resolved in-plan (was a pre-flight gap):** the inbound envelope carries `sender_id`/`sender_device_num` (denormalized in Task 2), because a self-sync copy has a *different* sender than a spouse copy and realtime can't join. Task 6 reads them off the envelope.

**Open items the implementer must resolve (flagged inline):**
- Task 1: match `SignalSessionService`'s real constructor parameter names.
- Task 4: use whatever row/companion names Drift codegen emits.
