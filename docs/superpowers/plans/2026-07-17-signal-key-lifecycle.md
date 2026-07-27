# Signal Key Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the key-id lifecycle so an established conversation stops burning one-time prekeys, key ids are monotonic, signed-prekey rotation is safe, prekeys replenish — and prove the whole server path with real integration tests against local Supabase.

**Architecture:** Split the consuming bundle fetch into a non-consuming `list_devices` roster plus a single-device `fetch_prekey_bundle`, so `encryptFor` only handshakes where it has no session. Persist monotonic key-id counters in a Drift `signal_meta` table (never `max(id)+1` — consumed prekeys are deleted locally, so max walks backwards and reissues ids with different key material). Retain old signed prekeys so rotation can't orphan in-flight messages.

**Tech Stack:** Flutter 3.44, `libsignal_protocol_dart` 0.8.2, `drift` + `drift_dev`/`build_runner`, `supabase_flutter`, Supabase CLI 2.109 with **local Supabase running under Docker**.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-17-signal-key-lifecycle-design.md`.
- **Local Supabase IS running** (Docker up). DB: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`. API: `http://127.0.0.1:54321`. Anon key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0`
- Verify migrations with `supabase db reset` (fast, local, from scratch). **Do NOT run `supabase db push`** — that targets the user's production Cloud project; Cloud deployment happens later, after local is green.
- **bytea over PostgREST MUST be a `\x`-prefixed lowercase hex string.** Proven on this stack: `"\x0501ab"` → `0501ab`, but a JSON int array `[5,1,171]` → `5b352c312c3137315d` (the ASCII bytes of the literal text `"[5,1,171]"`) — it does NOT error, it silently stores garbage. The existing `_hex()` helper in `signal_registration.dart` is the encoder; `DeviceBundle._bytes` is the decoder.
- Key ids come from **persisted counters** in `signal_meta`, never `max(id)+1`.
- Signed prekeys are **retained**, never overwritten/deleted on rotation.
- Identity private key stays in the Keychain; Drift holds state only.
- `CiphertextMessage.prekeyType = 3`, `whisperType = 2` — use the constants, never literals.
- TDD. Commit after every task.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260717000001_key_lifecycle_rpcs.sql` | `list_devices` (non-consuming), `fetch_prekey_bundle` (single-device, consuming); drop `fetch_prekey_bundles` |
| `lib/core/storage/signal_db.dart` (+`.g.dart`) | add `SignalMeta(key, value)` table, schemaVersion 2 + migration |
| `lib/core/crypto/key_counters.dart` | typed accessors over `signal_meta` (next prekey / signed-prekey id) |
| `lib/core/crypto/prekey_bundle_source.dart` | `deviceNumsFor` + `bundleFor`; drop `bundlesFor` |
| `lib/core/crypto/signal_keys.dart` | generate prekeys/signed prekey from a starting id |
| `lib/core/crypto/signal_session_service.dart` | roster-then-handshake `encryptFor` |
| `lib/core/crypto/signal_registration.dart` | counters, safe rotation, `replenishPrekeysIfLow` |
| `test/integration/signal_server_test.dart` | **the real deliverable** — RPCs + bytea round-trip against local Supabase |

---

### Task 1: Migration — roster/handshake split

**Files:**
- Create: `supabase/migrations/20260717000001_key_lifecycle_rpcs.sql`

**Interfaces:**
- Produces: `list_devices(uuid) returns table(device_num int)`; `fetch_prekey_bundle(uuid, integer) returns table(...)`; drops `fetch_prekey_bundles(uuid)`.

- [ ] **Step 1: Write the migration**

```sql
-- Split roster discovery from the handshake.
--
-- fetch_prekey_bundles(user) consumed a one-time prekey for EVERY device on
-- every call, and encryptFor called it on every send just to learn the device
-- roster -- so an established conversation drained the prekey pool. Roster
-- lookup must consume nothing; only an actual X3DH handshake may consume.

drop function if exists public.fetch_prekey_bundles(uuid);

-- Non-consuming roster.
create or replace function public.list_devices(p_target_user uuid)
returns table (device_num integer)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  return query
    select b.device_num
      from public.signal_key_bundles b
     where b.user_id = p_target_user
       and b.device_num is not null
     order by b.device_num;
end;
$$;

grant execute on function public.list_devices(uuid) to authenticated;

-- Single-device bundle; consumes exactly one one-time prekey for THAT device.
create or replace function public.fetch_prekey_bundle(
  p_target_user uuid,
  p_device_num  integer
)
returns table (
  device_num          integer,
  registration_id     integer,
  identity_pub        bytea,
  signed_prekey_id    integer,
  signed_prekey_pub   bytea,
  signed_prekey_sig   bytea,
  one_time_prekey_id  integer,
  one_time_prekey_pub bytea
)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  r     record;
  v_otp record;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  select b.device_num, b.registration_id, b.identity_pub,
         b.signed_prekey_id, b.signed_prekey_pub, b.signed_prekey_sig
    into r
    from public.signal_key_bundles b
   where b.user_id = p_target_user and b.device_num = p_device_num;

  if not found then return; end if;

  update public.signal_one_time_prekeys o
     set consumed_at = now()
   where o.user_id = p_target_user
     and o.device_num = p_device_num
     and o.prekey_id = (
       select o2.prekey_id from public.signal_one_time_prekeys o2
        where o2.user_id = p_target_user
          and o2.device_num = p_device_num
          and o2.consumed_at is null
        order by o2.prekey_id
        limit 1
        for update skip locked
     )
  returning o.prekey_id, o.pub into v_otp;

  device_num          := r.device_num;
  registration_id     := r.registration_id;
  identity_pub        := r.identity_pub;
  signed_prekey_id    := r.signed_prekey_id;
  signed_prekey_pub   := r.signed_prekey_pub;
  signed_prekey_sig   := r.signed_prekey_sig;
  one_time_prekey_id  := v_otp.prekey_id;   -- null when exhausted
  one_time_prekey_pub := v_otp.pub;
  return next;
end;
$$;

grant execute on function public.fetch_prekey_bundle(uuid, integer) to authenticated;
```

- [ ] **Step 2: Apply locally from scratch**

Run: `supabase db reset`
Expected: every migration applies, ending with `20260717000001_key_lifecycle_rpcs.sql` and `Finished supabase db reset`. **Do NOT run `supabase db push`** (that targets production Cloud).

- [ ] **Step 3: Verify the functions**

Run:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -tAc \
  "select proname from pg_proc where proname in ('list_devices','fetch_prekey_bundle','fetch_prekey_bundles') order by proname;"
```
Expected: exactly two lines — `fetch_prekey_bundle` and `list_devices`. `fetch_prekey_bundles` must be ABSENT (dropped).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260717000001_key_lifecycle_rpcs.sql
git commit -m "feat(db): split roster lookup from consuming bundle fetch"
```

---

### Task 2: `signal_meta` table + key counters

**Files:**
- Modify: `lib/core/storage/signal_db.dart`
- Create: `lib/core/crypto/key_counters.dart`
- Test: `test/core/crypto/key_counters_test.dart`

**Interfaces:**
- Consumes: `SignalDb` (`SignalDb.memory()`).
- Produces: table `SignalMeta(key text pk, value text)`; `class KeyCounters { KeyCounters(SignalDb db); Future<int> nextPrekeyId(int count); Future<int> nextSignedPrekeyId(); }`
  - `nextPrekeyId(count)` returns the FIRST id of a reserved block of `count` ids and advances the counter by `count`.
  - `nextSignedPrekeyId()` returns one id and advances by 1.
  - Both start at 1 on a fresh device.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/key_counters_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/crypto/key_counters.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  setUp(() => db = SignalDb.memory());
  tearDown(() => db.close());

  test('prekey ids start at 1 and never repeat across reservations', () async {
    final c = KeyCounters(db);

    expect(await c.nextPrekeyId(20), 1);
    // Second reservation must start AFTER the first block, never reuse ids:
    // a reissued id with different key material is silently undecryptable.
    expect(await c.nextPrekeyId(5), 21);
    expect(await c.nextPrekeyId(1), 26);
  });

  test('signed prekey ids start at 1 and increment', () async {
    final c = KeyCounters(db);

    expect(await c.nextSignedPrekeyId(), 1);
    expect(await c.nextSignedPrekeyId(), 2);
    expect(await c.nextSignedPrekeyId(), 3);
  });

  test('counters are independent', () async {
    final c = KeyCounters(db);

    await c.nextPrekeyId(10);
    expect(await c.nextSignedPrekeyId(), 1,
        reason: 'signed prekey counter must not be advanced by prekeys');
  });

  test('counters persist across KeyCounters instances (same db)', () async {
    await KeyCounters(db).nextPrekeyId(20);

    // Simulates an app restart: new instance, same database.
    expect(await KeyCounters(db).nextPrekeyId(1), 21);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/key_counters_test.dart`
Expected: FAIL — `key_counters.dart` not found.

- [ ] **Step 3: Add the SignalMeta table**

In `lib/core/storage/signal_db.dart`, add the table class alongside the existing ones:

```dart
/// Small key/value store for device-local counters (monotonic key ids).
/// Lives in the DB rather than the Keychain: it is state, not a secret, and it
/// shares a lifecycle with the prekeys it numbers.
class SignalMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

Add `SignalMeta` to the `@DriftDatabase(tables: [...])` list, bump `schemaVersion` to `2`, and add a migration so existing installs gain the table:

```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(signalMeta);
        },
      );
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes, regenerating `lib/core/storage/signal_db.g.dart` with `SignalMeta`.

- [ ] **Step 5: Implement KeyCounters**

```dart
// lib/core/crypto/key_counters.dart
import 'package:drift/drift.dart';

import '../storage/signal_db.dart';

/// Monotonic key-id counters, persisted in `signal_meta`.
///
/// These MUST be persisted counters, not `max(id) + 1`: consumed one-time
/// prekeys are deleted from the local store, so `max()` walks backwards and
/// would reissue an id with DIFFERENT key material. The spouse's stored bundle
/// and ours would then disagree, producing messages that fail to decrypt with
/// no error anywhere.
class KeyCounters {
  KeyCounters(this._db);

  static const _prekeyKey = 'next_prekey_id';
  static const _signedPrekeyKey = 'next_signed_prekey_id';

  final SignalDb _db;

  /// Reserves a block of [count] prekey ids and returns the FIRST one.
  Future<int> nextPrekeyId(int count) => _reserve(_prekeyKey, count);

  /// Reserves one signed-prekey id.
  Future<int> nextSignedPrekeyId() => _reserve(_signedPrekeyKey, 1);

  Future<int> _reserve(String key, int count) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.signalMeta)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      final start = row == null ? 1 : int.parse(row.value);
      await _db.into(_db.signalMeta).insertOnConflictUpdate(
            SignalMetaCompanion(
              key: Value(key),
              value: Value('${start + count}'),
            ),
          );
      return start;
    });
  }
}
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/core/crypto/key_counters_test.dart`
Expected: PASS (4/4).

- [ ] **Step 7: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart lib/core/crypto/key_counters.dart test/core/crypto/key_counters_test.dart
git commit -m "feat(crypto): persisted monotonic key-id counters"
```

---

### Task 3: Generate keys from a starting id

**Files:**
- Modify: `lib/core/crypto/signal_keys.dart`
- Test: `test/core/crypto/signal_keys_test.dart`

**Interfaces:**
- Produces: `generateBundle({required String deviceId, int oneTimePrekeyCount = 20, sig.IdentityKeyPair? existingIdentity, int? existingRegistrationId, int firstPrekeyId = 1, int signedPrekeyId = 1})`
  and `generatePrekeyBatch({required int firstPrekeyId, required int count})` returning `({Map<int, Uint8List> privateSerialized, List<PublicPrekey> publics})`.

**Why:** ids are currently hardcoded (`const signedPrekeyId = 1`, `generatePreKeys(1, n)`), so any rotation or replenish reuses ids with different key material.

- [ ] **Step 1: Write the failing test**

Append to `test/core/crypto/signal_keys_test.dart`:

```dart
  test('generateBundle honours explicit starting ids', () {
    final b = generateBundle(
      deviceId: 'd',
      oneTimePrekeyCount: 3,
      firstPrekeyId: 100,
      signedPrekeyId: 7,
    );

    expect(b.public.signedPrekeyId, 7);
    expect(b.public.oneTimePrekeys.map((p) => p.id).toList(), [100, 101, 102]);
    expect(b.private.oneTimePrekeysSerialized.keys.toList()..sort(),
        [100, 101, 102]);
  });

  test('generateBundle defaults are unchanged (ids start at 1)', () {
    final b = generateBundle(deviceId: 'd', oneTimePrekeyCount: 2);

    expect(b.public.signedPrekeyId, 1);
    expect(b.public.oneTimePrekeys.map((p) => p.id).toList(), [1, 2]);
  });

  test('generatePrekeyBatch numbers from the given first id', () {
    final batch = generatePrekeyBatch(firstPrekeyId: 50, count: 3);

    expect(batch.publics.map((p) => p.id).toList(), [50, 51, 52]);
    expect(batch.privateSerialized.keys.toList()..sort(), [50, 51, 52]);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/signal_keys_test.dart`
Expected: FAIL — `firstPrekeyId` / `signedPrekeyId` / `generatePrekeyBatch` undefined.

- [ ] **Step 3: Implement**

In `lib/core/crypto/signal_keys.dart`, add a batch helper:

```dart
/// Generate a block of one-time prekeys numbered from [firstPrekeyId].
///
/// Ids must come from a persisted counter — reusing an id with different key
/// material makes messages silently undecryptable.
({Map<int, Uint8List> privateSerialized, List<PublicPrekey> publics})
    generatePrekeyBatch({
  required int firstPrekeyId,
  required int count,
}) {
  final prekeys = sig.generatePreKeys(firstPrekeyId, count);
  return (
    privateSerialized: {for (final p in prekeys) p.id: p.serialize()},
    publics: prekeys
        .map((p) => PublicPrekey(id: p.id, pub: p.getKeyPair().publicKey.serialize()))
        .toList(growable: false),
  );
}
```

Then change `generateBundle` to take `int firstPrekeyId = 1, int signedPrekeyId = 1` and use them: replace `const signedPrekeyId = 1;` with the parameter (rename the local so it doesn't shadow), call `sig.generateSignedPreKey(identity, signedPrekeyId)`, and build the one-time prekeys via `generatePrekeyBatch(firstPrekeyId: firstPrekeyId, count: oneTimePrekeyCount)` — reusing its result for both the public and private bundles. Defaults must keep current behaviour exactly.

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_keys_test.dart`
Expected: PASS (existing tests + 3 new).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/signal_keys.dart test/core/crypto/signal_keys_test.dart
git commit -m "feat(crypto): generate keys from explicit starting ids"
```

---

### Task 4: Roster/handshake split in the bundle source

**Files:**
- Modify: `lib/core/crypto/prekey_bundle_source.dart`
- Test: `test/core/crypto/prekey_bundle_source_test.dart`

**Interfaces:**
- Produces:
  ```dart
  abstract class PreKeyBundleSource {
    Future<List<int>> deviceNumsFor(String userId);            // non-consuming
    Future<DeviceBundle?> bundleFor(String userId, int deviceNum); // consuming
  }
  ```
  `SupabasePreKeyBundleSource` calls `list_devices` and `fetch_prekey_bundle`. `bundlesFor` is REMOVED.
- `DeviceBundle` and `DeviceBundle.fromRow` are unchanged.

- [ ] **Step 1: Write the failing test**

Append to `test/core/crypto/prekey_bundle_source_test.dart`:

```dart
  test('PreKeyBundleSource exposes a non-consuming roster and a single-device fetch', () {
    // Compile-time contract check: a fake must satisfy exactly these members.
    final fake = _FakeSource();
    expect(fake, isA<PreKeyBundleSource>());
  });
}

class _FakeSource implements PreKeyBundleSource {
  @override
  Future<List<int>> deviceNumsFor(String userId) async => [1, 2];

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async => null;
```

(Place `_FakeSource` at file scope — move `main()`'s closing brace above it.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/prekey_bundle_source_test.dart`
Expected: FAIL — `deviceNumsFor` / `bundleFor` are not members of `PreKeyBundleSource`.

- [ ] **Step 3: Implement**

Replace the abstract class and the Supabase implementation:

```dart
abstract class PreKeyBundleSource {
  /// The target's device numbers. Consumes NOTHING — this is called on every
  /// send to build the fan-out roster.
  Future<List<int>> deviceNumsFor(String userId);

  /// One device's bundle, consuming one one-time prekey server-side. Call this
  /// ONLY when establishing a session. Null when the device has no bundle.
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum);
}

class SupabasePreKeyBundleSource implements PreKeyBundleSource {
  SupabasePreKeyBundleSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<int>> deviceNumsFor(String userId) async {
    final rows = await _client.rpc(
      'list_devices',
      params: {'p_target_user': userId},
    );
    if (rows is! List) return const [];
    return rows
        .map((r) => (Map<String, dynamic>.from(r as Map))['device_num'] as int)
        .toList();
  }

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async {
    final rows = await _client.rpc(
      'fetch_prekey_bundle',
      params: {'p_target_user': userId, 'p_device_num': deviceNum},
    );
    if (rows is! List || rows.isEmpty) return null;
    return DeviceBundle.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }
}
```

Delete the old `bundlesFor` from both the interface and the implementation.

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/prekey_bundle_source_test.dart`
Expected: PASS. (`signal_session_service.dart` will not compile yet — Task 5 fixes it.)

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/prekey_bundle_source.dart test/core/crypto/prekey_bundle_source_test.dart
git commit -m "feat(crypto): non-consuming roster + single-device bundle fetch"
```

---

### Task 5: `encryptFor` — roster, then handshake only where needed

**Files:**
- Modify: `lib/core/crypto/signal_session_service.dart`
- Test: `test/core/crypto/signal_session_service_test.dart`

**Interfaces:**
- Consumes: `PreKeyBundleSource.deviceNumsFor` / `bundleFor` (Task 4).
- Produces: unchanged public API (`encryptFor`, `decryptFrom`, `EncryptedCopy`).

**The fix:** `encryptFor` currently calls `bundlesFor` for recipient AND self on every send, and `_ensureSession` calls it again — consuming a prekey per device per message. Now: get the roster (free), and call `bundleFor` only where `containsSession` is false.

- [ ] **Step 1: Write the failing test**

Append to `test/core/crypto/signal_session_service_test.dart`. First extend the fake source in that file to count calls (replace its `bundlesFor` with the new members):

```dart
  test('an established session consumes NO prekey bundles on later sends', () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    final source = alice.source; // the _FakeBundles instance alice uses

    await alice.service.encryptFor(
        recipientUserId: 'bob', plaintext: Uint8List.fromList([1]));
    final afterFirst = source.bundleForCalls;
    expect(afterFirst, 1, reason: 'exactly one handshake for bob:1');

    await alice.service.encryptFor(
        recipientUserId: 'bob', plaintext: Uint8List.fromList([2]));

    expect(source.bundleForCalls, afterFirst,
        reason: 'second send must NOT fetch (and consume) another bundle');
    expect(source.deviceNumsForCalls, greaterThan(0),
        reason: 'roster lookup is used instead');
  });
```

`_FakeBundles` must expose `int bundleForCalls` and `int deviceNumsForCalls`, and `_Device` must expose its `source`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/signal_session_service_test.dart`
Expected: FAIL — the file won't compile (`bundlesFor` no longer exists on the interface).

- [ ] **Step 3: Implement**

Replace `encryptFor`'s roster building and `_ensureSession`:

```dart
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) async {
    final targets = <({String userId, int deviceNum})>[];

    // Roster lookups consume nothing; only a real handshake consumes a prekey.
    if (recipientUserId != _selfUserId) {
      for (final n in await _bundles.deviceNumsFor(recipientUserId)) {
        targets.add((userId: recipientUserId, deviceNum: n));
      }
    }
    for (final n in await _bundles.deviceNumsFor(_selfUserId)) {
      if (n == _selfDeviceNum) continue;
      targets.add((userId: _selfUserId, deviceNum: n));
    }

    final copies = <EncryptedCopy>[];
    for (final t in targets) {
      final address = SignalProtocolAddress(t.userId, t.deviceNum);
      await _ensureSession(address);
      final cipher = SessionCipher.fromStore(_store, address);
      final message = await cipher.encrypt(plaintext);
      copies.add(EncryptedCopy(
        userId: t.userId,
        deviceNum: t.deviceNum,
        ciphertext: Uint8List.fromList(message.serialize()),
        cipherType: message.getType(),
      ));
    }
    return copies;
  }

  /// X3DH only when we have no session for this address yet. This is the ONLY
  /// place allowed to fetch a bundle, because fetching consumes a one-time
  /// prekey server-side.
  Future<void> _ensureSession(SignalProtocolAddress address) async {
    if (await _store.containsSession(address)) return;

    final bundle =
        await _bundles.bundleFor(address.getName(), address.getDeviceId());
    if (bundle == null) {
      throw StateError(
          'No published bundle for ${address.getName()}:${address.getDeviceId()}');
    }
    final builder = SessionBuilder.fromSignalStore(_store, address);
    await builder.processPreKeyBundle(bundle.toPreKeyBundle());
  }
```

Update `_FakeBundles` in the test file to implement `deviceNumsFor` (returning the registry's device numbers for that user) and `bundleFor` (returning that device's `DeviceBundle`), counting both.

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_session_service_test.dart`
Expected: PASS — all existing tests plus the new consumption test.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/signal_session_service.dart test/core/crypto/signal_session_service_test.dart
git commit -m "fix(crypto): stop consuming a prekey per send; roster then handshake"
```

---

### Task 6: Registration uses counters; rotation retains old signed prekeys

**Files:**
- Modify: `lib/core/crypto/signal_registration.dart`
- Test: `test/core/crypto/signal_registration_test.dart`

**Interfaces:**
- Consumes: `KeyCounters` (Task 2), `generateBundle(firstPrekeyId:, signedPrekeyId:)` (Task 3).
- Produces: `ensureRegistered` unchanged in signature; internally allocates ids from `KeyCounters`.

**Why:** re-registration currently regenerates the signed prekey under the hardcoded id 1 and prekeys from id 1 — overwriting keys the spouse may already hold.

- [ ] **Step 1: Write the failing test**

Append to `test/core/crypto/signal_registration_test.dart`:

```dart
  test('re-registration rotates ids forward and RETAINS the old signed prekey',
      () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final firstSpkIds = await _signedPrekeyIds(db);
    final firstPrekeyIds = registrar.uploaded.keys.toList()..sort();

    // Force the resume path: identity kept, device number cleared.
    await vault.saveDeviceNum(-1); // sentinel; cleared below
    await _clearDeviceNum(vault);
    registrar.uploaded.clear();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);

    final secondSpkIds = await _signedPrekeyIds(db);
    final secondPrekeyIds = registrar.uploaded.keys.toList()..sort();

    expect(secondSpkIds.length, greaterThan(firstSpkIds.length),
        reason: 'the previous signed prekey must be RETAINED, not overwritten '
            '- an in-flight message naming the old id must still decrypt');
    expect(secondPrekeyIds.first, greaterThan(firstPrekeyIds.last),
        reason: 'prekey ids must never be reissued with different key material');
  });
}

Future<List<int>> _signedPrekeyIds(SignalDb db) async {
  final rows = await db.select(db.signalSignedPrekeys).get();
  return rows.map((r) => r.signedPrekeyId).toList()..sort();
}

Future<void> _clearDeviceNum(KeyVault vault) async {
  // KeyVault has no delete-one; wipe is too broad, so overwrite via the store.
  await vault.saveDeviceNum(0);
}
```

**Implementer note:** the test needs a way to reach the "identity present, device_num absent" state. `KeyVault` currently has no method to clear just the device number. Add `Future<void> clearDeviceNum()` to `KeyVault` (deleting only `_deviceNumKey`) and use it here instead of the `_clearDeviceNum` helper above — then delete that helper and the `saveDeviceNum(-1)`/`saveDeviceNum(0)` lines. Keep `readDeviceNum()` returning null afterwards.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: FAIL — `ensureRegistered` has no `db` param yet in this shape / ids don't advance.

- [ ] **Step 3: Implement**

In `ensureRegistered`, replace the hardcoded generation with counter-allocated ids:

```dart
  final counters = KeyCounters(db);
  final firstPrekeyId = await counters.nextPrekeyId(oneTimePrekeyCount);
  final signedPrekeyId = await counters.nextSignedPrekeyId();

  final generated = generateBundle(
    deviceId: deviceId,
    oneTimePrekeyCount: oneTimePrekeyCount,
    existingIdentity: existingIdentity,
    existingRegistrationId: existingRegistrationId,
    firstPrekeyId: firstPrekeyId,
    signedPrekeyId: signedPrekeyId,
  );
```

Keep the existing store-seeding (Task C1's fix) — it writes each prekey and the signed prekey into the Drift store. **Do not delete old signed prekeys**: `storeSignedPreKey` upserts by id, and because ids now advance, previous rows are naturally retained. Add a comment stating that retention is deliberate (an in-flight `PreKeySignalMessage` names the spk id it used).

Add `clearDeviceNum()` to `KeyVault`:
```dart
  Future<void> clearDeviceNum() => _storage.delete(_deviceNumKey);
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: PASS — including the existing idempotency and resume tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/signal_registration.dart lib/core/crypto/key_vault.dart test/core/crypto/signal_registration_test.dart
git commit -m "feat(crypto): allocate key ids from counters; retain rotated signed prekeys"
```

---

### Task 7: `replenishPrekeysIfLow`

**Files:**
- Modify: `lib/core/crypto/signal_registration.dart`
- Test: `test/core/crypto/signal_registration_test.dart`

**Interfaces:**
- Produces:
  ```dart
  Future<void> replenishPrekeysIfLow({
    required SignalDb db,
    required KeyVault vault,
    required DeviceRegistrar registrar,
    int threshold = 10,
    int topUpTo = 20,
  });
  ```
- Called from `ensureRegistered` after registration completes.

**Why:** `unconsumedPrekeyCount` has zero callers today; each device gets 20 prekeys once and never tops up, so handshakes silently degrade to signed-prekey-only.

- [ ] **Step 1: Write the failing test**

Append to `test/core/crypto/signal_registration_test.dart`:

```dart
  test('replenish tops up to topUpTo using fresh, never-reused ids', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    final initialIds = registrar.uploaded.keys.toList()..sort();
    registrar.uploaded.clear();
    registrar.remaining = 3; // server says only 3 unconsumed left

    await replenishPrekeysIfLow(
        db: db, vault: vault, registrar: registrar, threshold: 10, topUpTo: 20);

    final topUpIds = registrar.uploaded.keys.toList()..sort();
    expect(topUpIds.length, 17, reason: 'tops up 3 -> 20');
    expect(topUpIds.first, greaterThan(initialIds.last),
        reason: 'must never reissue an id that was already published');
  });

  test('replenish does nothing when above threshold', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(db: db, vault: vault, registrar: registrar);
    registrar.uploaded.clear();
    registrar.remaining = 15;

    await replenishPrekeysIfLow(
        db: db, vault: vault, registrar: registrar, threshold: 10, topUpTo: 20);

    expect(registrar.uploaded, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: FAIL — `replenishPrekeysIfLow` undefined.

- [ ] **Step 3: Implement**

```dart
/// Top up this device's one-time prekeys when the server pool runs low.
///
/// Ids come from the persisted counter, so a top-up can never reissue an id the
/// spouse already holds under different key material.
///
/// Failure is non-fatal: the device still works, its handshakes just degrade to
/// signed-prekey-only until the next attempt.
Future<void> replenishPrekeysIfLow({
  required SignalDb db,
  required KeyVault vault,
  required DeviceRegistrar registrar,
  int threshold = 10,
  int topUpTo = 20,
}) async {
  final deviceNum = await vault.readDeviceNum();
  if (deviceNum == null) return; // not registered yet

  final remaining = await registrar.unconsumedPrekeyCount(deviceNum);
  if (remaining >= threshold) return;

  final need = topUpTo - remaining;
  if (need <= 0) return;

  final firstId = await KeyCounters(db).nextPrekeyId(need);
  final batch = generatePrekeyBatch(firstPrekeyId: firstId, count: need);

  final store = DriftSignalStore(db, vault);
  for (final e in batch.privateSerialized.entries) {
    await store.storePreKey(e.key, PreKeyRecord.fromBuffer(e.value));
  }

  await registrar.uploadOneTimePrekeys(
    deviceNum: deviceNum,
    prekeys: {for (final p in batch.publics) p.id: p.pub},
  );
}
```

Call it at the end of `ensureRegistered` (after `saveDeviceNum`), wrapped so a failure can't break registration:
```dart
  // Non-fatal: a failed top-up degrades handshakes, it doesn't break the device.
  try {
    await replenishPrekeysIfLow(db: db, vault: vault, registrar: registrar);
  } catch (_) {}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: PASS.
Run: `flutter test test/core`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/signal_registration.dart test/core/crypto/signal_registration_test.dart
git commit -m "feat(crypto): replenish one-time prekeys when the pool runs low"
```

---

### Task 8: Integration tests against local Supabase — the real deliverable

**Files:**
- Create: `test/integration/signal_server_test.dart`

**Interfaces:**
- Consumes: `SupabaseDeviceRegistrar`, `SupabasePreKeyBundleSource`, `generateBundle`, the `list_devices` / `fetch_prekey_bundle` / `register_device_bundle` RPCs.

**Why this task exists:** the entire server path has never touched a database. Inspection alone let two fatal bugs (C1, C2) reach the final review. On this exact stack a JSON int array does NOT error — it silently stores the ASCII bytes of `"[5,1,171]"` as the key. Only a real round-trip proves the encoding.

- [ ] **Step 1: Verify local Supabase is up**

Run: `supabase status`
Expected: services listed, API at `http://127.0.0.1:54321`. If it errors, run `supabase start` first. **Never run `supabase db push`** — that targets production Cloud.

- [ ] **Step 2: Write the failing test**

```dart
// test/integration/signal_server_test.dart
//
// Integration tests against LOCAL Supabase (Docker). These are the only tests
// that exercise the RPCs and the bytea wire format. Require `supabase start`.
@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sakinah/core/crypto/prekey_bundle_source.dart';
import 'package:sakinah/core/crypto/signal_keys.dart';
import 'package:sakinah/core/crypto/signal_registration.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

late SupabaseClient client;

Future<String> _signUpUser() async {
  final email = 'sig-${DateTime.now().microsecondsSinceEpoch}@test.local';
  final res = await client.auth.signUp(email: email, password: 'password123');
  return res.user!.id;
}

void main() {
  setUpAll(() async {
    client = SupabaseClient(_url, _anon);
  });

  test('BYTEA ROUND-TRIP: published key bytes come back identical', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-a', oneTimePrekeyCount: 2);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-a',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );

    final me = client.auth.currentUser!.id;
    final bundle = await source.bundleFor(me, deviceNum);

    expect(bundle, isNotNull);
    // THE point of this test: a JSON int array would silently store the ASCII
    // bytes of "[5,1,171]" instead of the key, and nothing would error.
    expect(bundle!.identityPub, pub.identityPub);
    expect(bundle.signedPrekeyPub, pub.signedPrekeyPub);
    expect(bundle.signedPrekeySig, pub.signedPrekeySig);
    expect(bundle.registrationId, pub.registrationId);
  });

  test('list_devices consumes nothing; fetch_prekey_bundle consumes exactly one',
      () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-b', oneTimePrekeyCount: 3);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-b',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );
    final me = client.auth.currentUser!.id;

    final before = await registrar.unconsumedPrekeyCount(deviceNum);
    await source.deviceNumsFor(me);
    expect(await registrar.unconsumedPrekeyCount(deviceNum), before,
        reason: 'roster lookup must consume nothing');

    final first = await source.bundleFor(me, deviceNum);
    expect(await registrar.unconsumedPrekeyCount(deviceNum), before - 1);

    final second = await source.bundleFor(me, deviceNum);
    expect(second!.oneTimePrekeyId, isNot(first!.oneTimePrekeyId),
        reason: 'a prekey must never be handed out twice');
  });

  test('exhausted device still returns a bundle with a null one-time prekey',
      () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-c', oneTimePrekeyCount: 1);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-c',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );
    final me = client.auth.currentUser!.id;

    await source.bundleFor(me, deviceNum); // consumes the only one
    final exhausted = await source.bundleFor(me, deviceNum);

    expect(exhausted, isNotNull,
        reason: 'the device must stay reachable when prekeys run out');
    expect(exhausted!.oneTimePrekeyId, isNull);
    expect(exhausted.signedPrekeyPub, pub.signedPrekeyPub,
        reason: 'handshake falls back to the signed prekey');
  });

  test('re-registering the same device reuses its device_num', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final g1 = generateBundle(deviceId: 'dev-d');
    final first = await registrar.register(
      deviceId: 'dev-d',
      registrationId: g1.public.registrationId,
      identityPub: g1.public.identityPub,
      signedPrekeyId: g1.public.signedPrekeyId,
      signedPrekeyPub: g1.public.signedPrekeyPub,
      signedPrekeySig: g1.public.signedPrekeySig,
    );
    final second = await registrar.register(
      deviceId: 'dev-d',
      registrationId: g1.public.registrationId,
      identityPub: g1.public.identityPub,
      signedPrekeyId: g1.public.signedPrekeyId,
      signedPrekeyPub: g1.public.signedPrekeyPub,
      signedPrekeySig: g1.public.signedPrekeySig,
    );

    expect(second, first);
  });

  test('two new devices for one user get distinct device numbers', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final g = generateBundle(deviceId: 'x');

    final a = await registrar.register(
      deviceId: 'dev-e1',
      registrationId: g.public.registrationId,
      identityPub: g.public.identityPub,
      signedPrekeyId: g.public.signedPrekeyId,
      signedPrekeyPub: g.public.signedPrekeyPub,
      signedPrekeySig: g.public.signedPrekeySig,
    );
    final b = await registrar.register(
      deviceId: 'dev-e2',
      registrationId: g.public.registrationId,
      identityPub: g.public.identityPub,
      signedPrekeyId: g.public.signedPrekeyId,
      signedPrekeyPub: g.public.signedPrekeyPub,
      signedPrekeySig: g.public.signedPrekeySig,
    );

    expect(a, isNot(b));
  });
}
```

- [ ] **Step 3: Run the integration tests**

Run: `flutter test test/integration/signal_server_test.dart`
Expected: all PASS.

If the bytea round-trip FAILS, the encoding is wrong — fix `_hex` in `signal_registration.dart` (bytea over PostgREST must be a `\x`-prefixed lowercase hex string). **Do not weaken the assertion** — it is the entire point of the task.

- [ ] **Step 4: Run the whole suite**

Run: `flutter test`
Expected: all PASS. Local Supabase is up, so the previously-unrunnable onboarding / scoreboard / preferences integration tests should pass too. If any of those fail for reasons unrelated to this plan, report them rather than fixing them here.

- [ ] **Step 5: Commit**

```bash
git add test/integration/signal_server_test.dart
git commit -m "test(crypto): integration tests for signal RPCs + bytea round-trip"
```

---

## Self-Review

**Spec coverage:**
- Roster/handshake split (RPCs + client + encryptFor) → Tasks 1, 4, 5 ✅
- Monotonic key ids (`signal_meta` + counters, never `max+1`) → Tasks 2, 3, 6 ✅
- Safe SPK rotation (monotonic ids + retention) → Task 6 ✅
- Replenishment → Task 7 ✅
- Integration tests incl. the bytea round-trip (the C2 proof) → Task 8 ✅
- Error handling: replenish non-fatal (Task 7), missing bundle → typed failure (Task 5) ✅

**Gaps found and closed while planning:**
- `KeyVault` had no way to clear just the device number, so Task 6's rotation test couldn't reach the resume state. Added `clearDeviceNum()` to Task 6.
- `SignalDb` needed `schemaVersion` 2 + a `MigrationStrategy`, or existing installs would crash on the new `signal_meta` table. Added to Task 2.

**Placeholder scan:** none — every code step carries complete code. Task 6 Step 1 contains an explicit implementer note replacing its own scaffold helper with `KeyVault.clearDeviceNum()`; that is a deliberate instruction, not a TBD.

**Type consistency:** `KeyCounters.nextPrekeyId(count)`/`nextSignedPrekeyId()`, `generatePrekeyBatch({firstPrekeyId, count})` → `({privateSerialized, publics})`, `PreKeyBundleSource.deviceNumsFor`/`bundleFor`, `replenishPrekeysIfLow({db, vault, registrar, threshold, topUpTo})`, `ensureRegistered({db, vault, registrar, oneTimePrekeyCount})` are used consistently. `CiphertextMessage` constants only.

**Known limits:**
- Task 8's tests need local Supabase running; they are tagged `integration` but not excluded from `flutter test` by default — if the suite is ever run without Docker they will fail loudly (acceptable: silent skipping is what let C2 through).
- Cloud deployment of migration `20260717000001` is deliberately NOT in this plan; it happens after local is green.
