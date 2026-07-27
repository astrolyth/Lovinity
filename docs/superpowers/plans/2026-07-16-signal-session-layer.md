# Signal Session Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a trustworthy, test-proven Signal session layer (Drift-backed stores, X3DH, Double Ratchet, multi-device fan-out, prekey lifecycle) that E2E chat will sit on. No UI.

**Architecture:** Four libsignal store interfaces implemented as thin adapters over a Drift/SQLite database (identity private key stays in the Keychain), composed into a `SignalProtocolStore`, and wrapped by a single `SignalSessionService` that is the *only* crypto API the rest of the app touches. Prekey bundles come from an injected source so the whole layer is unit-testable with no server.

**Tech Stack:** Flutter 3.44, `libsignal_protocol_dart` 0.8.2, `drift` + `sqlite3_flutter_libs` + `drift_dev`/`build_runner` (already in pubspec, first real use), `flutter_secure_storage`, Supabase (Cloud only — local Supabase/Docker is off).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-16-signal-session-layer-design.md`.
- **Verified libsignal constants:** `CiphertextMessage.prekeyType = 3` (X3DH first message), `CiphertextMessage.whisperType = 2` (subsequent). The existing `messages.cipher_type` comment ("1 (pre-key) or 3 (message)") is WRONG and must be corrected.
- `SignalProtocolAddress(String name, int deviceId)` — deviceId is an **int**; `name` is the user's UUID string.
- Multi-device **fan-out**: encrypt one copy per recipient device **plus** per the sender's own other devices.
- Identity trust: **TOFU + accept-on-change**, recording a change event. `isTrustedIdentity` always returns true.
- Identity keypair + registration id + device number live in the **Keychain** (`KeyVault`); the Drift DB holds session/prekey/identity state only.
- **`KeyVault` takes a `SecureStore` abstraction** (Task 2). Tests construct a **per-device `InMemorySecureStore`**. **Never use `FlutterSecureStorage.setMockInitialValues` in these tests** — it is a single global map shared by every instance, so simulated devices would clobber each other's identities and the multi-device tests would silently lie.
- No UI, no `messages` table changes, no media in this plan.
- Local Supabase is OFF (project runs against Cloud). Migration verification is `supabase db push` + `supabase migration list`; there are **no** DB integration tests. All Dart tests use Drift **in-memory** + a fake bundle source.
- Follow existing patterns: repositories take a `SupabaseClient`; failures use `core/errors/failures.dart`.
- Commit after every task.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260716000003_signal_devices_prekeys.sql` | device_num, one-time prekey table, register/fetch RPCs, cipher_type comment fix |
| `lib/core/crypto/key_vault.dart` (modify) | also persist registrationId + deviceNum |
| `lib/core/storage/signal_db.dart` (+ `.g.dart`) | Drift DB + 5 tables |
| `lib/core/crypto/stores/drift_session_store.dart` | SessionStore adapter |
| `lib/core/crypto/stores/drift_prekey_store.dart` | PreKeyStore + SignedPreKeyStore adapters |
| `lib/core/crypto/stores/drift_identity_store.dart` | IdentityKeyStore adapter (TOFU + change events) |
| `lib/core/crypto/stores/drift_signal_store.dart` | composite `SignalProtocolStore` delegating to the four |
| `lib/core/crypto/prekey_bundle_source.dart` | injected bundle source (interface + Supabase impl) |
| `lib/core/crypto/signal_session_service.dart` | the public API: register / encryptFor / decryptFrom / replenish |

---

### Task 1: Migration — device numbers, prekey table, RPCs

**Files:**
- Create: `supabase/migrations/20260716000003_signal_devices_prekeys.sql`

**Interfaces:**
- Produces: `signal_key_bundles.device_num int`; table `signal_one_time_prekeys`; RPCs `register_device_bundle(...) returns int` and `fetch_prekey_bundles(uuid)`.

- [ ] **Step 1: Write the migration**

```sql
-- libsignal addresses are (name, int deviceId); device_id is a uuid, so each
-- device also needs a small integer number, unique per user (1 = first device).
alter table public.signal_key_bundles
  add column if not exists device_num integer;

create unique index if not exists signal_bundles_user_devicenum_idx
  on public.signal_key_bundles(user_id, device_num);

-- One-time prekeys must be consumed atomically; a jsonb array cannot be popped
-- safely and handing the same prekey to two senders breaks the handshake.
create table if not exists public.signal_one_time_prekeys (
  user_id     uuid not null references public.users(id) on delete cascade,
  device_num  integer not null,
  prekey_id   integer not null,
  pub         bytea not null,
  consumed_at timestamptz,
  primary key (user_id, device_num, prekey_id)
);

create index if not exists signal_otp_unconsumed_idx
  on public.signal_one_time_prekeys(user_id, device_num)
  where consumed_at is null;

alter table public.signal_one_time_prekeys enable row level security;

-- Own rows: full control (upload/replenish). Spouse: no direct select --
-- prekeys are handed out only via fetch_prekey_bundles (security definer).
create policy signal_otp_own on public.signal_one_time_prekeys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.signal_one_time_prekeys to authenticated;

-- Correct the documented cipher_type values: libsignal uses
-- CiphertextMessage.whisperType = 2 and prekeyType = 3.
comment on column public.messages.cipher_type is
  'libsignal CiphertextMessage type: 3 = prekey (X3DH first message), 2 = whisper (subsequent)';

------------------------------------------------------------------
-- register_device_bundle: allocate this device's number + upsert its bundle
------------------------------------------------------------------
create or replace function public.register_device_bundle(
  p_device_id         text,
  p_registration_id   integer,
  p_identity_pub      bytea,
  p_signed_prekey_id  integer,
  p_signed_prekey_pub bytea,
  p_signed_prekey_sig bytea
)
returns integer
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_num integer;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Reuse this device's number if it re-registers; otherwise allocate next.
  select device_num into v_num from public.signal_key_bundles
   where user_id = v_uid and device_id = p_device_id;

  if v_num is null then
    select coalesce(max(device_num), 0) + 1 into v_num
      from public.signal_key_bundles where user_id = v_uid;
  end if;

  insert into public.signal_key_bundles (
    user_id, device_id, device_num, registration_id, identity_pub,
    signed_prekey_id, signed_prekey_pub, signed_prekey_sig, updated_at
  ) values (
    v_uid, p_device_id, v_num, p_registration_id, p_identity_pub,
    p_signed_prekey_id, p_signed_prekey_pub, p_signed_prekey_sig, now()
  )
  on conflict (user_id, device_id) do update set
    device_num       = excluded.device_num,
    registration_id  = excluded.registration_id,
    identity_pub     = excluded.identity_pub,
    signed_prekey_id = excluded.signed_prekey_id,
    signed_prekey_pub= excluded.signed_prekey_pub,
    signed_prekey_sig= excluded.signed_prekey_sig,
    updated_at       = now();

  return v_num;
end;
$$;

grant execute on function public.register_device_bundle(text,integer,bytea,integer,bytea,bytea) to authenticated;

------------------------------------------------------------------
-- fetch_prekey_bundles: one bundle per device of the target, consuming one
-- one-time prekey each. Target may be the caller or the caller's spouse.
------------------------------------------------------------------
create or replace function public.fetch_prekey_bundles(p_target_user uuid)
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

  -- Self, or a member of the caller's active couple.
  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  for r in
    select b.device_num, b.registration_id, b.identity_pub,
           b.signed_prekey_id, b.signed_prekey_pub, b.signed_prekey_sig
      from public.signal_key_bundles b
     where b.user_id = p_target_user and b.device_num is not null
  loop
    -- Atomically claim one unused one-time prekey for this device.
    update public.signal_one_time_prekeys o
       set consumed_at = now()
     where o.user_id = p_target_user
       and o.device_num = r.device_num
       and o.prekey_id = (
         select o2.prekey_id from public.signal_one_time_prekeys o2
          where o2.user_id = p_target_user
            and o2.device_num = r.device_num
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
    v_otp := null;
  end loop;
end;
$$;

grant execute on function public.fetch_prekey_bundles(uuid) to authenticated;
```

- [ ] **Step 2: Push to cloud**

Run: `supabase db push`
Expected: `Applying migration 20260716000003_signal_devices_prekeys.sql...` then `Finished supabase db push.` with no SQL error. (A `pgdelta`/Docker cache warning is expected and harmless — Docker is off.)

- [ ] **Step 3: Verify it is applied on remote**

Run: `supabase migration list`
Expected: `20260716000003` appears in BOTH the Local and Remote columns.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260716000003_signal_devices_prekeys.sql
git commit -m "feat(db): signal device numbers, one-time prekey table, bundle RPCs"
```

---

### Task 2: SecureStore abstraction + KeyVault persists registration id / device number

**Files:**
- Create: `lib/core/crypto/secure_store.dart`
- Modify: `lib/core/crypto/key_vault.dart`
- Modify: `lib/core/crypto/signal_keys.dart` (add `registrationId` to `PrivateBundle`)
- Modify: `lib/features/auth/domain/auth_controller.dart` (`keyVaultProvider` passes the real store)
- Test: `test/core/crypto/key_vault_test.dart`

**Interfaces:**
- Consumes: `PrivateBundle` (existing).
- Produces:
  - `abstract class SecureStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); Future<void> deleteAll(); }`
  - `class FlutterSecureStore implements SecureStore` (wraps `FlutterSecureStorage`)
  - `class InMemorySecureStore implements SecureStore` (tests; **per-instance** map)
  - `KeyVault(SecureStore store)`
  - `PrivateBundle.registrationId` (int); `KeyVault.readRegistrationId() → Future<int?>`, `KeyVault.saveDeviceNum(int)`, `KeyVault.readDeviceNum() → Future<int?>`.

**Why:** libsignal's `IdentityKeyStore.getLocalRegistrationId()` is required, but nothing currently persists the registration id (`PrivateBundle` doesn't carry it) or the device number.

**Why the abstraction:** later tasks simulate several devices at once. `FlutterSecureStorage`'s test mock is one **global** map shared by all instances, so device B's identity would overwrite device A's and the multi-device tests would pass while testing nonsense. `InMemorySecureStore` gives each simulated device a genuinely isolated vault.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/key_vault_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/crypto/key_vault.dart';
import 'package:sakinah/core/crypto/secure_store.dart';
import 'package:sakinah/core/crypto/signal_keys.dart';

void main() {
  test('round-trips registration id and device number', () async {
    final vault = KeyVault(InMemorySecureStore());
    final generated = generateBundle(deviceId: 'dev-1', oneTimePrekeyCount: 2);

    await vault.savePrivate(generated.private);
    await vault.saveDeviceNum(3);

    expect(await vault.readRegistrationId(), generated.private.registrationId);
    expect(await vault.readDeviceNum(), 3);
    expect(await vault.hasIdentity(), isTrue);
  });

  test('wipe clears registration id and device number', () async {
    final vault = KeyVault(InMemorySecureStore());
    await vault.savePrivate(
        generateBundle(deviceId: 'd', oneTimePrekeyCount: 1).private);
    await vault.saveDeviceNum(1);

    await vault.wipe();

    expect(await vault.readRegistrationId(), isNull);
    expect(await vault.readDeviceNum(), isNull);
  });

  test('two vaults with separate stores do not share state', () async {
    final a = KeyVault(InMemorySecureStore());
    final b = KeyVault(InMemorySecureStore());

    await a.savePrivate(generateBundle(deviceId: 'a', oneTimePrekeyCount: 1).private);

    expect(await a.hasIdentity(), isTrue);
    expect(await b.hasIdentity(), isFalse,
        reason: 'each simulated device must have an isolated vault');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/key_vault_test.dart`
Expected: FAIL — `secure_store.dart` not found / `KeyVault(InMemorySecureStore())` type mismatch.

- [ ] **Step 3: Create the SecureStore abstraction**

```dart
// lib/core/crypto/secure_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value secret storage. Exists so KeyVault can be constructed with
/// an isolated fake per simulated device in tests — FlutterSecureStorage's mock
/// is a single global map and would let devices clobber each other.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Test double with per-instance state.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}
```

- [ ] **Step 4: Point KeyVault at SecureStore**

In `lib/core/crypto/key_vault.dart`, change the constructor parameter type from `FlutterSecureStorage` to `SecureStore`, and replace every `_storage.read(key: k)` / `_storage.write(key: k, value: v)` / `_storage.delete(key: k)` call with the `SecureStore` equivalents (`_storage.read(k)`, `_storage.write(k, v)`, `_storage.delete(k)`). Keep all existing methods and key names unchanged.

In `lib/features/auth/domain/auth_controller.dart`, update `keyVaultProvider` to wrap the real storage:
```dart
final keyVaultProvider = Provider<KeyVault>((ref) {
  return KeyVault(FlutterSecureStore(ref.read(secureStorageProvider)));
});
```

- [ ] **Step 5: Add registrationId to PrivateBundle**

In `lib/core/crypto/signal_keys.dart`, add to `PrivateBundle`: a `final int registrationId;` field, `required this.registrationId` in the const constructor, and pass `registrationId: registrationId` where `generateBundle` builds the `PrivateBundle` (the value is already computed as `registrationId` for the public bundle).

- [ ] **Step 6: Extend KeyVault with the new fields**

In `lib/core/crypto/key_vault.dart` add key constants and methods alongside the existing ones:

```dart
  static const _registrationIdKey = 'signal_registration_id';
  static const _deviceNumKey = 'signal_device_num';

  Future<int?> readRegistrationId() async {
    final v = await _storage.read(key: _registrationIdKey);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> saveDeviceNum(int num) =>
      _storage.write(key: _deviceNumKey, value: '$num');

  Future<int?> readDeviceNum() async {
    final v = await _storage.read(key: _deviceNumKey);
    return v == null ? null : int.tryParse(v);
  }
```

In `savePrivate`, also write the registration id:
```dart
    await _storage.write(
      key: _registrationIdKey, value: '${bundle.registrationId}');
```
In `wipe`, also delete `_registrationIdKey` and `_deviceNumKey`.

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/core/crypto/key_vault_test.dart test/core/crypto/signal_keys_test.dart`
Expected: PASS (3 vault tests + existing signal_keys tests).
Run: `flutter analyze lib/core/crypto lib/features/auth`
Expected: No issues (confirms `keyVaultProvider` still compiles against the new constructor).

- [ ] **Step 8: Commit**

```bash
git add lib/core/crypto/secure_store.dart lib/core/crypto/key_vault.dart lib/core/crypto/signal_keys.dart lib/features/auth/domain/auth_controller.dart test/core/crypto/key_vault_test.dart
git commit -m "feat(crypto): SecureStore abstraction + persist registration id/device number"
```

---

### Task 3: Drift database for Signal state

**Files:**
- Create: `lib/core/storage/signal_db.dart`
- Test: `test/core/storage/signal_db_test.dart`

**Interfaces:**
- Produces: `SignalDb` (Drift `_$SignalDb`) with tables `SignalSessions(name, deviceNum, record)`, `SignalPrekeys(prekeyId, record)`, `SignalSignedPrekeys(signedPrekeyId, record)`, `SignalIdentities(name, deviceNum, identityKey, firstSeen)`, `SignalIdentityChanges(id, name, deviceNum, changedAt)`; `SignalDb.memory()` for tests.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/storage/signal_db_test.dart
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  test('stores and reads a session row', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);

    await db.into(db.signalSessions).insert(SignalSessionsCompanion.insert(
          name: 'user-a',
          deviceNum: 1,
          record: Uint8List.fromList([1, 2, 3]),
        ));

    final rows = await db.select(db.signalSessions).get();
    expect(rows.single.name, 'user-a');
    expect(rows.single.deviceNum, 1);
    expect(rows.single.record, [1, 2, 3]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/storage/signal_db_test.dart`
Expected: FAIL — `signal_db.dart` not found.

- [ ] **Step 3: Write the database**

```dart
// lib/core/storage/signal_db.dart
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'signal_db.g.dart';

/// Ratchet/session state. The identity PRIVATE key never lives here — it stays
/// in the Keychain (KeyVault). Keeping this in a DB (rather than scattered
/// Keychain entries) is what makes an encrypted backup feasible later.
class SignalSessions extends Table {
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {name, deviceNum};
}

class SignalPrekeys extends Table {
  IntColumn get prekeyId => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {prekeyId};
}

class SignalSignedPrekeys extends Table {
  IntColumn get signedPrekeyId => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {signedPrekeyId};
}

class SignalIdentities extends Table {
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  BlobColumn get identityKey => blob()();
  DateTimeColumn get firstSeen => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {name, deviceNum};
}

/// Recorded when a known address presents a different identity key, so chat can
/// surface "their security code changed".
class SignalIdentityChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [
  SignalSessions,
  SignalPrekeys,
  SignalSignedPrekeys,
  SignalIdentities,
  SignalIdentityChanges,
])
class SignalDb extends _$SignalDb {
  SignalDb() : super(driftDatabase(name: 'sakinah_signal'));

  /// In-memory instance for tests.
  SignalDb.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes, writing `lib/core/storage/signal_db.g.dart`.

- [ ] **Step 5: Run tests**

Run: `flutter test test/core/storage/signal_db_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart test/core/storage/signal_db_test.dart
git commit -m "feat(storage): drift database for signal session state"
```

---

### Task 4: DriftSessionStore

**Files:**
- Create: `lib/core/crypto/stores/drift_session_store.dart`
- Test: `test/core/crypto/stores/drift_session_store_test.dart`

**Interfaces:**
- Consumes: `SignalDb` (Task 3).
- Produces: `DriftSessionStore(SignalDb db) implements SessionStore` — `loadSession`, `getSubDeviceSessions`, `storeSession`, `containsSession`, `deleteSession`, `deleteAllSessions`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/stores/drift_session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/stores/drift_session_store.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late DriftSessionStore store;

  setUp(() {
    db = SignalDb.memory();
    store = DriftSessionStore(db);
  });
  tearDown(() => db.close());

  test('loadSession returns a fresh record for an unknown address', () async {
    final rec = await store.loadSession(SignalProtocolAddress('bob', 1));
    expect(rec, isA<SessionRecord>());
    expect(await store.containsSession(SignalProtocolAddress('bob', 1)), isFalse);
  });

  test('stored session round-trips and is reported as present', () async {
    final addr = SignalProtocolAddress('bob', 1);
    final record = SessionRecord();
    await store.storeSession(addr, record);

    expect(await store.containsSession(addr), isTrue);
    final loaded = await store.loadSession(addr);
    expect(loaded.serialize(), record.serialize());
  });

  test('getSubDeviceSessions lists other devices, excluding device 1', () async {
    await store.storeSession(SignalProtocolAddress('bob', 1), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 2), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 3), SessionRecord());

    final subs = await store.getSubDeviceSessions('bob');
    expect(subs..sort(), [2, 3]);
  });

  test('deleteSession and deleteAllSessions remove rows', () async {
    await store.storeSession(SignalProtocolAddress('bob', 1), SessionRecord());
    await store.storeSession(SignalProtocolAddress('bob', 2), SessionRecord());

    await store.deleteSession(SignalProtocolAddress('bob', 1));
    expect(await store.containsSession(SignalProtocolAddress('bob', 1)), isFalse);

    await store.deleteAllSessions('bob');
    expect(await store.containsSession(SignalProtocolAddress('bob', 2)), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/stores/drift_session_store_test.dart`
Expected: FAIL — `DriftSessionStore` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/stores/drift_session_store.dart
import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';

/// SessionStore backed by Drift. Holds the Double Ratchet state, so every write
/// must land before the next message is processed — hence no caching here.
class DriftSessionStore implements SessionStore {
  DriftSessionStore(this._db);

  final SignalDb _db;

  Future<SignalSession?> _row(SignalProtocolAddress address) {
    return (_db.select(_db.signalSessions)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .getSingleOrNull();
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final row = await _row(address);
    // libsignal expects a fresh record (not an error) for an unknown address.
    if (row == null) return SessionRecord();
    return SessionRecord.fromSerialized(row.record);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = await (_db.select(_db.signalSessions)
          ..where((t) => t.name.equals(name) & t.deviceNum.equals(1).not()))
        .get();
    return rows.map((r) => r.deviceNum).toList();
  }

  @override
  Future<void> storeSession(
      SignalProtocolAddress address, SessionRecord record) async {
    await _db.into(_db.signalSessions).insertOnConflictUpdate(
          SignalSessionsCompanion.insert(
            name: address.getName(),
            deviceNum: address.getDeviceId(),
            record: record.serialize(),
          ),
        );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _row(address) != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await (_db.delete(_db.signalSessions)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .go();
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await (_db.delete(_db.signalSessions)..where((t) => t.name.equals(name)))
        .go();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/stores/drift_session_store_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/stores/drift_session_store.dart test/core/crypto/stores/drift_session_store_test.dart
git commit -m "feat(crypto): drift-backed SessionStore"
```

---

### Task 5: DriftPreKeyStore + DriftSignedPreKeyStore

**Files:**
- Create: `lib/core/crypto/stores/drift_prekey_store.dart`
- Test: `test/core/crypto/stores/drift_prekey_store_test.dart`

**Interfaces:**
- Consumes: `SignalDb`.
- Produces: `DriftPreKeyStore(SignalDb) implements PreKeyStore`; `DriftSignedPreKeyStore(SignalDb) implements SignedPreKeyStore`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/stores/drift_prekey_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/stores/drift_prekey_store.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  setUp(() => db = SignalDb.memory());
  tearDown(() => db.close());

  test('prekey round-trips, reports presence, and removes', () async {
    final store = DriftPreKeyStore(db);
    final record = generatePreKeys(1, 1).first;

    expect(await store.containsPreKey(record.id), isFalse);
    await store.storePreKey(record.id, record);
    expect(await store.containsPreKey(record.id), isTrue);

    final loaded = await store.loadPreKey(record.id);
    expect(loaded.serialize(), record.serialize());

    await store.removePreKey(record.id);
    expect(await store.containsPreKey(record.id), isFalse);
  });

  test('loadPreKey throws InvalidKeyIdException when missing', () async {
    final store = DriftPreKeyStore(db);
    expect(() => store.loadPreKey(999), throwsA(isA<InvalidKeyIdException>()));
  });

  test('signed prekey round-trips and lists', () async {
    final store = DriftSignedPreKeyStore(db);
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 1);

    await store.storeSignedPreKey(signed.id, signed);
    expect(await store.containsSignedPreKey(signed.id), isTrue);
    expect((await store.loadSignedPreKey(signed.id)).serialize(),
        signed.serialize());
    expect((await store.loadSignedPreKeys()).length, 1);

    await store.removeSignedPreKey(signed.id);
    expect(await store.containsSignedPreKey(signed.id), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/stores/drift_prekey_store_test.dart`
Expected: FAIL — `DriftPreKeyStore` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/stores/drift_prekey_store.dart
import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';

class DriftPreKeyStore implements PreKeyStore {
  DriftPreKeyStore(this._db);

  final SignalDb _db;

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final row = await (_db.select(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No prekey with id $preKeyId');
    }
    return PreKeyRecord.fromBuffer(row.record);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _db.into(_db.signalPrekeys).insertOnConflictUpdate(
          SignalPrekeysCompanion.insert(
            prekeyId: preKeyId,
            record: record.serialize(),
          ),
        );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final row = await (_db.select(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await (_db.delete(_db.signalPrekeys)
          ..where((t) => t.prekeyId.equals(preKeyId)))
        .go();
  }
}

class DriftSignedPreKeyStore implements SignedPreKeyStore {
  DriftSignedPreKeyStore(this._db);

  final SignalDb _db;

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .getSingleOrNull();
    if (row == null) {
      throw InvalidKeyIdException('No signed prekey with id $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(row.record);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final rows = await _db.select(_db.signalSignedPrekeys).get();
    return rows
        .map((r) => SignedPreKeyRecord.fromSerialized(r.record))
        .toList();
  }

  @override
  Future<void> storeSignedPreKey(
      int signedPreKeyId, SignedPreKeyRecord record) async {
    await _db.into(_db.signalSignedPrekeys).insertOnConflictUpdate(
          SignalSignedPrekeysCompanion.insert(
            signedPrekeyId: signedPreKeyId,
            record: record.serialize(),
          ),
        );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final row = await (_db.select(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await (_db.delete(_db.signalSignedPrekeys)
          ..where((t) => t.signedPrekeyId.equals(signedPreKeyId)))
        .go();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/stores/drift_prekey_store_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/stores/drift_prekey_store.dart test/core/crypto/stores/drift_prekey_store_test.dart
git commit -m "feat(crypto): drift-backed PreKeyStore + SignedPreKeyStore"
```

---

### Task 6: DriftIdentityStore (TOFU + change events)

**Files:**
- Create: `lib/core/crypto/stores/drift_identity_store.dart`
- Test: `test/core/crypto/stores/drift_identity_store_test.dart`

**Interfaces:**
- Consumes: `SignalDb`, `KeyVault` (`readIdentity`, `readRegistrationId` from Task 2).
- Produces: `DriftIdentityStore(SignalDb db, KeyVault vault) implements IdentityKeyStore`.

**Trust policy (from the spec):** `isTrustedIdentity` always returns true (TOFU + accept-on-change); `saveIdentity` returns true when it replaced a *different* existing key and records a `signalIdentityChanges` row.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/stores/drift_identity_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/key_vault.dart';
import 'package:sakinah/core/crypto/secure_store.dart';
import 'package:sakinah/core/crypto/signal_keys.dart';
import 'package:sakinah/core/crypto/stores/drift_identity_store.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late KeyVault vault;
  late DriftIdentityStore store;

  setUp(() async {
    db = SignalDb.memory();
    vault = KeyVault(InMemorySecureStore());
    await vault.savePrivate(
        generateBundle(deviceId: 'd', oneTimePrekeyCount: 1).private);
    store = DriftIdentityStore(db, vault);
  });
  tearDown(() => db.close());

  test('exposes the local identity pair and registration id', () async {
    expect(await store.getIdentityKeyPair(), isA<IdentityKeyPair>());
    expect(await store.getLocalRegistrationId(), isA<int>());
  });

  test('first save is trust-on-first-use: no change event', () async {
    final addr = SignalProtocolAddress('bob', 1);
    final bob = generateIdentityKeyPair().getPublicKey();

    final replaced = await store.saveIdentity(addr, bob);

    expect(replaced, isFalse, reason: 'nothing was replaced on first use');
    expect((await store.getIdentity(addr))!.serialize(), bob.serialize());
    expect(await db.select(db.signalIdentityChanges).get(), isEmpty);
  });

  test('changed identity is accepted AND recorded', () async {
    final addr = SignalProtocolAddress('bob', 1);
    await store.saveIdentity(addr, generateIdentityKeyPair().getPublicKey());

    final newKey = generateIdentityKeyPair().getPublicKey();
    final replaced = await store.saveIdentity(addr, newKey);

    expect(replaced, isTrue);
    expect((await store.getIdentity(addr))!.serialize(), newKey.serialize());
    final changes = await db.select(db.signalIdentityChanges).get();
    expect(changes, hasLength(1));
    expect(changes.single.name, 'bob');
  });

  test('isTrustedIdentity accepts a changed key (accept-but-warn policy)',
      () async {
    final addr = SignalProtocolAddress('bob', 1);
    await store.saveIdentity(addr, generateIdentityKeyPair().getPublicKey());

    final trusted = await store.isTrustedIdentity(
        addr, generateIdentityKeyPair().getPublicKey(), Direction.sending);

    expect(trusted, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/stores/drift_identity_store_test.dart`
Expected: FAIL — `DriftIdentityStore` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/stores/drift_identity_store.dart
import 'package:drift/drift.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';
import '../key_vault.dart';

/// IdentityKeyStore backed by Drift, with the local identity pair read from the
/// Keychain.
///
/// Trust policy: trust-on-first-use, and accept a changed identity but record it
/// so chat can surface "their security code changed". A changed key is far more
/// often a reinstall than an attack; blocking would break the common case.
class DriftIdentityStore implements IdentityKeyStore {
  DriftIdentityStore(this._db, this._vault);

  final SignalDb _db;
  final KeyVault _vault;

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final serialized = await _vault.readIdentity();
    if (serialized == null) {
      throw StateError('No local Signal identity — call ensureRegistered first');
    }
    return IdentityKeyPair.fromSerialized(serialized);
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final id = await _vault.readRegistrationId();
    if (id == null) {
      throw StateError('No local registration id — call ensureRegistered first');
    }
    return id;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final row = await (_db.select(_db.signalIdentities)
          ..where((t) =>
              t.name.equals(address.getName()) &
              t.deviceNum.equals(address.getDeviceId())))
        .getSingleOrNull();
    if (row == null) return null;
    return IdentityKey.fromBytes(row.identityKey, 0);
  }

  /// Returns true when this REPLACED a different existing key (libsignal's
  /// contract), and records a change event in that case.
  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;

    final existing = await getIdentity(address);
    final changed =
        existing != null && !_sameKey(existing, identityKey);

    await _db.into(_db.signalIdentities).insertOnConflictUpdate(
          SignalIdentitiesCompanion.insert(
            name: address.getName(),
            deviceNum: address.getDeviceId(),
            identityKey: identityKey.serialize(),
          ),
        );

    if (changed) {
      await _db.into(_db.signalIdentityChanges).insert(
            SignalIdentityChangesCompanion.insert(
              name: address.getName(),
              deviceNum: address.getDeviceId(),
            ),
          );
    }
    return changed;
  }

  /// Accept-but-warn: never block. The change is recorded in [saveIdentity].
  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
          IdentityKey? identityKey, Direction direction) async =>
      true;

  bool _sameKey(IdentityKey a, IdentityKey b) {
    final x = a.serialize();
    final y = b.serialize();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/stores/drift_identity_store_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/stores/drift_identity_store.dart test/core/crypto/stores/drift_identity_store_test.dart
git commit -m "feat(crypto): drift-backed IdentityKeyStore with TOFU + change events"
```

---

### Task 7: DriftSignalStore composite

**Files:**
- Create: `lib/core/crypto/stores/drift_signal_store.dart`
- Test: `test/core/crypto/stores/drift_signal_store_test.dart`

**Interfaces:**
- Consumes: `DriftSessionStore`, `DriftPreKeyStore`, `DriftSignedPreKeyStore`, `DriftIdentityStore`.
- Produces: `DriftSignalStore(SignalDb db, KeyVault vault) implements SignalProtocolStore` — delegates every method to the four stores. This is what `SessionCipher.fromStore` / `SessionBuilder.fromSignalStore` take.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/stores/drift_signal_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/key_vault.dart';
import 'package:sakinah/core/crypto/secure_store.dart';
import 'package:sakinah/core/crypto/signal_keys.dart';
import 'package:sakinah/core/crypto/stores/drift_signal_store.dart';
import 'package:sakinah/core/storage/signal_db.dart';

void main() {
  test('satisfies SignalProtocolStore across all four interfaces', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final generated = generateBundle(deviceId: 'd', oneTimePrekeyCount: 1);
    await vault.savePrivate(generated.private);

    final store = DriftSignalStore(db, vault);
    expect(store, isA<SignalProtocolStore>());

    // identity
    expect(await store.getLocalRegistrationId(),
        generated.private.registrationId);
    // session
    final addr = SignalProtocolAddress('bob', 1);
    await store.storeSession(addr, SessionRecord());
    expect(await store.containsSession(addr), isTrue);
    // prekey
    final pk = generatePreKeys(1, 1).first;
    await store.storePreKey(pk.id, pk);
    expect(await store.containsPreKey(pk.id), isTrue);
    // signed prekey
    final spk = generateSignedPreKey(
        IdentityKeyPair.fromSerialized(generated.private.identitySerialized), 1);
    await store.storeSignedPreKey(spk.id, spk);
    expect(await store.containsSignedPreKey(spk.id), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/stores/drift_signal_store_test.dart`
Expected: FAIL — `DriftSignalStore` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/stores/drift_signal_store.dart
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../storage/signal_db.dart';
import '../key_vault.dart';
import 'drift_identity_store.dart';
import 'drift_prekey_store.dart';
import 'drift_session_store.dart';

/// The composite libsignal expects (`SessionCipher.fromStore` /
/// `SessionBuilder.fromSignalStore`). Pure delegation — each concern stays in
/// its own store so it can be tested in isolation.
class DriftSignalStore implements SignalProtocolStore {
  DriftSignalStore(SignalDb db, KeyVault vault)
      : _sessions = DriftSessionStore(db),
        _prekeys = DriftPreKeyStore(db),
        _signedPrekeys = DriftSignedPreKeyStore(db),
        _identities = DriftIdentityStore(db, vault);

  final DriftSessionStore _sessions;
  final DriftPreKeyStore _prekeys;
  final DriftSignedPreKeyStore _signedPrekeys;
  final DriftIdentityStore _identities;

  // --- IdentityKeyStore
  @override
  Future<IdentityKeyPair> getIdentityKeyPair() => _identities.getIdentityKeyPair();
  @override
  Future<int> getLocalRegistrationId() => _identities.getLocalRegistrationId();
  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) =>
      _identities.getIdentity(address);
  @override
  Future<bool> saveIdentity(
          SignalProtocolAddress address, IdentityKey? identityKey) =>
      _identities.saveIdentity(address, identityKey);
  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
          IdentityKey? identityKey, Direction direction) =>
      _identities.isTrustedIdentity(address, identityKey, direction);

  // --- SessionStore
  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) =>
      _sessions.loadSession(address);
  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _sessions.getSubDeviceSessions(name);
  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) =>
      _sessions.storeSession(address, record);
  @override
  Future<bool> containsSession(SignalProtocolAddress address) =>
      _sessions.containsSession(address);
  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _sessions.deleteSession(address);
  @override
  Future<void> deleteAllSessions(String name) => _sessions.deleteAllSessions(name);

  // --- PreKeyStore
  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) => _prekeys.loadPreKey(preKeyId);
  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _prekeys.storePreKey(preKeyId, record);
  @override
  Future<bool> containsPreKey(int preKeyId) => _prekeys.containsPreKey(preKeyId);
  @override
  Future<void> removePreKey(int preKeyId) => _prekeys.removePreKey(preKeyId);

  // --- SignedPreKeyStore
  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int id) =>
      _signedPrekeys.loadSignedPreKey(id);
  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() =>
      _signedPrekeys.loadSignedPreKeys();
  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) =>
      _signedPrekeys.storeSignedPreKey(id, record);
  @override
  Future<bool> containsSignedPreKey(int id) =>
      _signedPrekeys.containsSignedPreKey(id);
  @override
  Future<void> removeSignedPreKey(int id) => _signedPrekeys.removeSignedPreKey(id);
}
```

If the analyzer reports unimplemented members (the composite's interface may expose more), implement each by delegating to the matching store — do not stub anything with `throw UnimplementedError`.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/core/crypto/stores/drift_signal_store_test.dart`
Expected: PASS.
Run: `flutter analyze lib/core/crypto`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/stores/drift_signal_store.dart test/core/crypto/stores/drift_signal_store_test.dart
git commit -m "feat(crypto): composite DriftSignalStore"
```

---

### Task 8: PreKeyBundleSource (injected, with Supabase impl)

**Files:**
- Create: `lib/core/crypto/prekey_bundle_source.dart`
- Test: `test/core/crypto/prekey_bundle_source_test.dart`

**Interfaces:**
- Consumes: `fetch_prekey_bundles` RPC (Task 1).
- Produces:
  - `class DeviceBundle { final int deviceNum, registrationId; final Uint8List identityPub, signedPrekeyPub, signedPrekeySig; final int signedPrekeyId; final int? oneTimePrekeyId; final Uint8List? oneTimePrekeyPub; }`
  - `abstract class PreKeyBundleSource { Future<List<DeviceBundle>> bundlesFor(String userId); }`
  - `class SupabasePreKeyBundleSource implements PreKeyBundleSource` (takes a `SupabaseClient`)
  - `DeviceBundle.toPreKeyBundle()` → libsignal `PreKeyBundle`

**Why injected:** the whole session layer must be unit-testable with no server, since local Supabase is off.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/prekey_bundle_source_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/prekey_bundle_source.dart';

void main() {
  test('DeviceBundle converts to a libsignal PreKeyBundle', () {
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 7);
    final otp = generatePreKeys(1, 1).first;

    final b = DeviceBundle(
      deviceNum: 2,
      registrationId: 1234,
      identityPub: identity.getPublicKey().serialize(),
      signedPrekeyId: 7,
      signedPrekeyPub: signed.getKeyPair().publicKey.serialize(),
      signedPrekeySig: signed.signature,
      oneTimePrekeyId: otp.id,
      oneTimePrekeyPub: otp.getKeyPair().publicKey.serialize(),
    );

    final bundle = b.toPreKeyBundle();
    expect(bundle.getDeviceId(), 2);
    expect(bundle.getSignedPreKeyId(), 7);
    expect(bundle.getPreKeyId(), otp.id);
  });

  test('DeviceBundle without a one-time prekey still converts (exhausted)', () {
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 1);

    final b = DeviceBundle(
      deviceNum: 1,
      registrationId: 9,
      identityPub: identity.getPublicKey().serialize(),
      signedPrekeyId: 1,
      signedPrekeyPub: signed.getKeyPair().publicKey.serialize(),
      signedPrekeySig: signed.signature,
      oneTimePrekeyId: null,
      oneTimePrekeyPub: null,
    );

    final bundle = b.toPreKeyBundle();
    expect(bundle.getPreKeyId(), isNull);
    expect(bundle.getPreKey(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/prekey_bundle_source_test.dart`
Expected: FAIL — `prekey_bundle_source.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/prekey_bundle_source.dart
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One device's published bundle. [oneTimePrekeyId]/[oneTimePrekeyPub] are null
/// when that device's one-time prekeys are exhausted — the handshake then
/// proceeds from the signed prekey alone, which is expected, not an error.
class DeviceBundle {
  const DeviceBundle({
    required this.deviceNum,
    required this.registrationId,
    required this.identityPub,
    required this.signedPrekeyId,
    required this.signedPrekeyPub,
    required this.signedPrekeySig,
    required this.oneTimePrekeyId,
    required this.oneTimePrekeyPub,
  });

  final int deviceNum;
  final int registrationId;
  final Uint8List identityPub;
  final int signedPrekeyId;
  final Uint8List signedPrekeyPub;
  final Uint8List signedPrekeySig;
  final int? oneTimePrekeyId;
  final Uint8List? oneTimePrekeyPub;

  PreKeyBundle toPreKeyBundle() => PreKeyBundle(
        registrationId,
        deviceNum,
        oneTimePrekeyId,
        oneTimePrekeyPub == null
            ? null
            : Curve.decodePoint(oneTimePrekeyPub!, 0),
        signedPrekeyId,
        Curve.decodePoint(signedPrekeyPub, 0),
        signedPrekeySig,
        IdentityKey.fromBytes(identityPub, 0),
      );

  factory DeviceBundle.fromRow(Map<String, dynamic> row) => DeviceBundle(
        deviceNum: row['device_num'] as int,
        registrationId: row['registration_id'] as int,
        identityPub: _bytes(row['identity_pub'])!,
        signedPrekeyId: row['signed_prekey_id'] as int,
        signedPrekeyPub: _bytes(row['signed_prekey_pub'])!,
        signedPrekeySig: _bytes(row['signed_prekey_sig'])!,
        oneTimePrekeyId: row['one_time_prekey_id'] as int?,
        oneTimePrekeyPub: _bytes(row['one_time_prekey_pub']),
      );

  /// Supabase returns bytea as a `\x…` hex string over PostgREST.
  static Uint8List? _bytes(Object? v) {
    if (v == null) return null;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    final s = v as String;
    final hex = s.startsWith(r'\x') ? s.substring(2) : s;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

abstract class PreKeyBundleSource {
  /// Every registered device of [userId] (self or spouse). Consumes one
  /// one-time prekey per device server-side.
  Future<List<DeviceBundle>> bundlesFor(String userId);
}

class SupabasePreKeyBundleSource implements PreKeyBundleSource {
  SupabasePreKeyBundleSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<DeviceBundle>> bundlesFor(String userId) async {
    final rows = await _client.rpc(
      'fetch_prekey_bundles',
      params: {'p_target_user': userId},
    );
    if (rows is! List) return const [];
    return rows
        .map((r) => DeviceBundle.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/prekey_bundle_source_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/prekey_bundle_source.dart test/core/crypto/prekey_bundle_source_test.dart
git commit -m "feat(crypto): injectable prekey bundle source"
```

---

### Task 9: SignalSessionService — encrypt/decrypt with fan-out

**Files:**
- Create: `lib/core/crypto/signal_session_service.dart`
- Test: `test/core/crypto/signal_session_service_test.dart`

**Interfaces:**
- Consumes: `DriftSignalStore`, `PreKeyBundleSource`, `DeviceBundle`, `SignalDb`, `KeyVault`.
- Produces:
  - `class EncryptedCopy { final String userId; final int deviceNum; final Uint8List ciphertext; final int cipherType; }`
  - `class SignalSessionService { SignalSessionService({required SignalDb db, required KeyVault vault, required PreKeyBundleSource bundles, required String selfUserId, required int selfDeviceNum}); Future<List<EncryptedCopy>> encryptFor({required String recipientUserId, required Uint8List plaintext}); Future<Uint8List> decryptFrom({required String senderUserId, required int senderDeviceNum, required Uint8List ciphertext, required int cipherType}); }`

**Fan-out rule:** copies go to **every device of `recipientUserId`**, plus **every device of `selfUserId` except `selfDeviceNum`** (so your sent messages reach your own other devices). When recipient == self, only the self-device fan-out applies.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/crypto/signal_session_service_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sakinah/core/crypto/key_vault.dart';
import 'package:sakinah/core/crypto/prekey_bundle_source.dart';
import 'package:sakinah/core/crypto/secure_store.dart';
import 'package:sakinah/core/crypto/signal_keys.dart';
import 'package:sakinah/core/crypto/signal_session_service.dart';
import 'package:sakinah/core/storage/signal_db.dart';

/// One simulated device: its own DB, vault and published bundle.
class _Device {
  _Device(this.userId, this.deviceNum);
  final String userId;
  final int deviceNum;
  late SignalDb db;
  late KeyVault vault;
  late GeneratedKeyBundle generated;
  late SignalSessionService service;
}

class _FakeBundles implements PreKeyBundleSource {
  _FakeBundles(this.devices);
  final List<_Device> devices;

  @override
  Future<List<DeviceBundle>> bundlesFor(String userId) async {
    return devices.where((d) => d.userId == userId).map((d) {
      final p = d.generated.public;
      final otp = p.oneTimePrekeys.first;
      return DeviceBundle(
        deviceNum: d.deviceNum,
        registrationId: p.registrationId,
        identityPub: p.identityPub,
        signedPrekeyId: p.signedPrekeyId,
        signedPrekeyPub: p.signedPrekeyPub,
        signedPrekeySig: p.signedPrekeySig,
        oneTimePrekeyId: otp.id,
        oneTimePrekeyPub: otp.pub,
      );
    }).toList();
  }
}

/// Builds a fully independent device: its own in-memory DB and its own isolated
/// vault, with its identity and prekeys already loaded. Devices never share
/// state, so any number can be active at once.
Future<_Device> _makeDevice(String userId, int deviceNum,
    List<_Device> registry) async {
  final d = _Device(userId, deviceNum);
  d.db = SignalDb.memory();
  d.vault = KeyVault(InMemorySecureStore());
  d.generated = generateBundle(deviceId: '$userId-$deviceNum');
  await d.vault.savePrivate(d.generated.private);
  await d.vault.saveDeviceNum(deviceNum);
  d.service = SignalSessionService(
    db: d.db,
    vault: d.vault,
    bundles: _FakeBundles(registry),
    selfUserId: userId,
    selfDeviceNum: deviceNum,
  );
  // Its own prekeys must be in its store so incoming prekey messages resolve.
  for (final entry in d.generated.private.oneTimePrekeysSerialized.entries) {
    await d.service.store
        .storePreKey(entry.key, PreKeyRecord.fromBuffer(entry.value));
  }
  await d.service.store.storeSignedPreKey(
    d.generated.public.signedPrekeyId,
    SignedPreKeyRecord.fromSerialized(d.generated.private.signedPrekeySerialized),
  );
  return d;
}

void main() {
  test('round-trip: alice encrypts, bob decrypts', () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    final copies = await alice.service.encryptFor(
      recipientUserId: 'bob',
      plaintext: Uint8List.fromList(utf8.encode('as-salamu alaykum')),
    );
    expect(copies, hasLength(1));
    expect(copies.single.cipherType, CiphertextMessage.prekeyType,
        reason: 'first message to a device must be a prekey message (3)');

    final plain = await bob.service.decryptFrom(
      senderUserId: 'alice',
      senderDeviceNum: 1,
      ciphertext: copies.single.ciphertext,
      cipherType: copies.single.cipherType,
    );
    expect(utf8.decode(plain), 'as-salamu alaykum');
  });

  test('fan-out: 2 bob devices + alice second device => 3 copies', () async {
    final registry = <_Device>[];
    final alice1 = await _makeDevice('alice', 1, registry);
    final alice2 = await _makeDevice('alice', 2, registry);
    final bob1 = await _makeDevice('bob', 1, registry);
    final bob2 = await _makeDevice('bob', 2, registry);
    registry.addAll([alice1, alice2, bob1, bob2]);

    final copies = await alice1.service.encryptFor(
      recipientUserId: 'bob',
      plaintext: Uint8List.fromList(utf8.encode('hi')),
    );

    expect(copies, hasLength(3));
    expect(
      copies.map((c) => '${c.userId}:${c.deviceNum}').toSet(),
      {'bob:1', 'bob:2', 'alice:2'},
      reason: 'both of bob devices plus alice own other device',
    );
  });

  test('second message to the same device is a whisper message (2)', () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    await alice.service.encryptFor(
        recipientUserId: 'bob', plaintext: Uint8List.fromList([1]));
    final second = await alice.service.encryptFor(
        recipientUserId: 'bob', plaintext: Uint8List.fromList([2]));

    expect(second.single.cipherType, CiphertextMessage.whisperType);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/crypto/signal_session_service_test.dart`
Expected: FAIL — `SignalSessionService` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/signal_session_service.dart
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../storage/signal_db.dart';
import 'key_vault.dart';
import 'prekey_bundle_source.dart';
import 'stores/drift_signal_store.dart';

/// One encrypted copy of a message, addressed to a single device.
class EncryptedCopy {
  const EncryptedCopy({
    required this.userId,
    required this.deviceNum,
    required this.ciphertext,
    required this.cipherType,
  });

  final String userId;
  final int deviceNum;
  final Uint8List ciphertext;

  /// [CiphertextMessage.prekeyType] (3) for the first message to a device,
  /// [CiphertextMessage.whisperType] (2) afterwards.
  final int cipherType;
}

/// The only crypto API the rest of the app uses. Nothing above this layer
/// should import libsignal.
class SignalSessionService {
  SignalSessionService({
    required SignalDb db,
    required KeyVault vault,
    required PreKeyBundleSource bundles,
    required String selfUserId,
    required int selfDeviceNum,
  })  : store = DriftSignalStore(db, vault),
        _bundles = bundles,
        _selfUserId = selfUserId,
        _selfDeviceNum = selfDeviceNum;

  /// Exposed so tests can seed this device's own prekeys.
  final DriftSignalStore store;
  final PreKeyBundleSource _bundles;
  final String _selfUserId;
  final int _selfDeviceNum;

  /// Encrypt one copy per recipient device, plus per this user's OTHER devices
  /// so sent messages appear there too.
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) async {
    final targets = <({String userId, int deviceNum})>[];

    if (recipientUserId != _selfUserId) {
      for (final b in await _bundles.bundlesFor(recipientUserId)) {
        targets.add((userId: recipientUserId, deviceNum: b.deviceNum));
      }
    }
    for (final b in await _bundles.bundlesFor(_selfUserId)) {
      if (b.deviceNum == _selfDeviceNum) continue;
      targets.add((userId: _selfUserId, deviceNum: b.deviceNum));
    }

    final copies = <EncryptedCopy>[];
    for (final t in targets) {
      final address = SignalProtocolAddress(t.userId, t.deviceNum);
      await _ensureSession(address);
      final cipher = SessionCipher.fromStore(store, address);
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

  Future<Uint8List> decryptFrom({
    required String senderUserId,
    required int senderDeviceNum,
    required Uint8List ciphertext,
    required int cipherType,
  }) async {
    final address = SignalProtocolAddress(senderUserId, senderDeviceNum);
    final cipher = SessionCipher.fromStore(store, address);

    if (cipherType == CiphertextMessage.prekeyType) {
      // X3DH: processing this establishes the session on our side.
      return cipher.decrypt(PreKeySignalMessage(ciphertext));
    }
    return cipher.decryptFromSignal(SignalMessage.fromSerialized(ciphertext));
  }

  /// X3DH only when we have no session for this address yet.
  Future<void> _ensureSession(SignalProtocolAddress address) async {
    if (await store.containsSession(address)) return;

    final bundles = await _bundles.bundlesFor(address.getName());
    final match = bundles
        .where((b) => b.deviceNum == address.getDeviceId())
        .toList();
    if (match.isEmpty) {
      throw StateError(
          'No published bundle for ${address.getName()}:${address.getDeviceId()}');
    }
    final builder = SessionBuilder.fromSignalStore(store, address);
    await builder.processPreKeyBundle(match.first.toPreKeyBundle());
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_session_service_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/signal_session_service.dart test/core/crypto/signal_session_service_test.dart
git commit -m "feat(crypto): SignalSessionService with multi-device fan-out"
```

---

### Task 10: The guarantees — restart survival, out-of-order, exhaustion, identity change

**Files:**
- Modify: `test/core/crypto/signal_session_service_test.dart` (append)

**Interfaces:**
- Consumes: everything from Task 9. No production code should be needed; if a test fails, fix the production code rather than the assertion.

**This is the point of the whole sub-project.** Restart survival in particular is the silent-failure mode that destroys chat history.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/crypto/signal_session_service_test.dart`:

```dart
  test('RESTART SURVIVAL: a session rebuilt from the DB still decrypts',
      () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    final first = await alice.service.encryptFor(
        recipientUserId: 'bob',
        plaintext: Uint8List.fromList(utf8.encode('before restart')));

    await bob.service.decryptFrom(
      senderUserId: 'alice',
      senderDeviceNum: 1,
      ciphertext: first.single.ciphertext,
      cipherType: first.single.cipherType,
    );

    // Simulate an app restart: brand new service over the SAME db + vault.
    final revived = SignalSessionService(
      db: bob.db,
      vault: bob.vault,
      bundles: _FakeBundles(registry),
      selfUserId: 'bob',
      selfDeviceNum: 1,
    );

    final second = await alice.service.encryptFor(
        recipientUserId: 'bob',
        plaintext: Uint8List.fromList(utf8.encode('after restart')));

    final plain = await revived.decryptFrom(
      senderUserId: 'alice',
      senderDeviceNum: 1,
      ciphertext: second.single.ciphertext,
      cipherType: second.single.cipherType,
    );
    expect(utf8.decode(plain), 'after restart',
        reason: 'ratchet state must persist across a restart');
  });

  test('OUT-OF-ORDER: messages delivered 3,1,2 all decrypt', () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    final msgs = <EncryptedCopy>[];
    for (final t in ['one', 'two', 'three']) {
      final c = await alice.service.encryptFor(
          recipientUserId: 'bob',
          plaintext: Uint8List.fromList(utf8.encode(t)));
      msgs.add(c.single);
    }

    final got = <String>[];
    for (final i in [2, 0, 1]) {
      final plain = await bob.service.decryptFrom(
        senderUserId: 'alice',
        senderDeviceNum: 1,
        ciphertext: msgs[i].ciphertext,
        cipherType: msgs[i].cipherType,
      );
      got.add(utf8.decode(plain));
    }
    expect(got, ['three', 'one', 'two']);
  });

  test('PREKEY EXHAUSTION: session still establishes from the signed prekey',
      () async {
    final registry = <_Device>[];
    final alice = await _makeDevice('alice', 1, registry);
    final bob = await _makeDevice('bob', 1, registry);
    registry.addAll([alice, bob]);

    // Bundle source that has run out of one-time prekeys.
    final exhausted = _ExhaustedBundles([bob]);
    final svc = SignalSessionService(
      db: alice.db,
      vault: alice.vault,
      bundles: exhausted,
      selfUserId: 'alice',
      selfDeviceNum: 1,
    );

    final copies = await svc.encryptFor(
        recipientUserId: 'bob', plaintext: Uint8List.fromList(utf8.encode('hi')));

    expect(copies, hasLength(1));
    expect(copies.single.cipherType, CiphertextMessage.prekeyType);
  });
}

/// Bundle source whose devices have no one-time prekeys left.
class _ExhaustedBundles implements PreKeyBundleSource {
  _ExhaustedBundles(this.devices);
  final List<_Device> devices;

  @override
  Future<List<DeviceBundle>> bundlesFor(String userId) async {
    return devices.where((d) => d.userId == userId).map((d) {
      final p = d.generated.public;
      return DeviceBundle(
        deviceNum: d.deviceNum,
        registrationId: p.registrationId,
        identityPub: p.identityPub,
        signedPrekeyId: p.signedPrekeyId,
        signedPrekeyPub: p.signedPrekeyPub,
        signedPrekeySig: p.signedPrekeySig,
        oneTimePrekeyId: null,
        oneTimePrekeyPub: null,
      );
    }).toList();
  }
}
```

Note: the closing `}` of `main()` moves above `_ExhaustedBundles` — place the class at file scope.

- [ ] **Step 2: Run tests**

Run: `flutter test test/core/crypto/signal_session_service_test.dart`
Expected: all PASS. If restart survival fails, the bug is in `DriftSessionStore.storeSession` (state not durably written) — fix the store, never the test.

- [ ] **Step 3: Run the full suite**

Run: `flutter test test/core`
Expected: all PASS. (Repository/integration tests elsewhere need local Supabase and are out of scope for this run.)

- [ ] **Step 4: Commit**

```bash
git add test/core/crypto/signal_session_service_test.dart
git commit -m "test(crypto): restart survival, out-of-order, prekey exhaustion"
```

---

### Task 11: Registration + prekey replenishment

**Files:**
- Modify: `lib/core/crypto/signal_session_service.dart`
- Create: `lib/core/crypto/signal_registration.dart`
- Test: `test/core/crypto/signal_registration_test.dart`

**Interfaces:**
- Consumes: `register_device_bundle` RPC (Task 1), `KeyVault`, `generateBundle`, `DriftSignalStore`.
- Produces:
  - `abstract class DeviceRegistrar { Future<int> register({required String deviceId, required int registrationId, required Uint8List identityPub, required int signedPrekeyId, required Uint8List signedPrekeyPub, required Uint8List signedPrekeySig}); Future<void> uploadOneTimePrekeys({required int deviceNum, required Map<int, Uint8List> prekeys}); Future<int> unconsumedPrekeyCount(int deviceNum); }`
  - `class SupabaseDeviceRegistrar implements DeviceRegistrar`
  - `SignalSessionService.ensureRegistered({required DeviceRegistrar registrar})` and `replenishPrekeysIfLow({required DeviceRegistrar registrar, int threshold = 10, int topUpTo = 20})`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/crypto/signal_registration_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/crypto/key_vault.dart';
import 'package:sakinah/core/crypto/secure_store.dart';
import 'package:sakinah/core/crypto/signal_registration.dart';

class _FakeRegistrar implements DeviceRegistrar {
  int? registeredDeviceNum;
  Map<int, Uint8List> uploaded = {};
  int remaining = 0;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    registeredDeviceNum = 1;
    return 1;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async =>
      uploaded.addAll(prekeys);

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async => remaining;
}

void main() {
  test('ensureRegistered generates, registers and persists the device number',
      () async {
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    final deviceNum = await ensureRegistered(vault: vault, registrar: registrar);

    expect(deviceNum, 1);
    expect(await vault.readDeviceNum(), 1);
    expect(await vault.hasIdentity(), isTrue);
    expect(await vault.readRegistrationId(), isNotNull);
    expect(registrar.uploaded, isNotEmpty);
  });

  test('ensureRegistered is idempotent — a second call keeps the identity',
      () async {
    final vault = KeyVault(InMemorySecureStore());
    final registrar = _FakeRegistrar();

    await ensureRegistered(vault: vault, registrar: registrar);
    final firstIdentity = await vault.readIdentity();

    await ensureRegistered(vault: vault, registrar: registrar);

    expect(await vault.readIdentity(), firstIdentity,
        reason: 'regenerating the identity would break every session');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: FAIL — `signal_registration.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/crypto/signal_registration.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'key_vault.dart';
import 'signal_keys.dart';

abstract class DeviceRegistrar {
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  });

  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  });

  Future<int> unconsumedPrekeyCount(int deviceNum);
}

class SupabaseDeviceRegistrar implements DeviceRegistrar {
  SupabaseDeviceRegistrar(this._client);

  final SupabaseClient _client;

  @override
  Future<int> register({
    required String deviceId,
    required int registrationId,
    required Uint8List identityPub,
    required int signedPrekeyId,
    required Uint8List signedPrekeyPub,
    required Uint8List signedPrekeySig,
  }) async {
    final res = await _client.rpc('register_device_bundle', params: {
      'p_device_id': deviceId,
      'p_registration_id': registrationId,
      'p_identity_pub': identityPub,
      'p_signed_prekey_id': signedPrekeyId,
      'p_signed_prekey_pub': signedPrekeyPub,
      'p_signed_prekey_sig': signedPrekeySig,
    });
    return res as int;
  }

  @override
  Future<void> uploadOneTimePrekeys({
    required int deviceNum,
    required Map<int, Uint8List> prekeys,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('signal_one_time_prekeys').upsert([
      for (final e in prekeys.entries)
        {
          'user_id': uid,
          'device_num': deviceNum,
          'prekey_id': e.key,
          'pub': e.value,
        }
    ]);
  }

  @override
  Future<int> unconsumedPrekeyCount(int deviceNum) async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('signal_one_time_prekeys')
        .select('prekey_id')
        .eq('user_id', uid)
        .eq('device_num', deviceNum)
        .isFilter('consumed_at', null);
    return (rows as List).length;
  }
}

/// Generate + publish this device's identity once. Idempotent: an existing
/// identity is never regenerated, because that would break every session.
Future<int> ensureRegistered({
  required KeyVault vault,
  required DeviceRegistrar registrar,
  int oneTimePrekeyCount = 20,
}) async {
  final existingNum = await vault.readDeviceNum();
  if (await vault.hasIdentity() && existingNum != null) return existingNum;

  var deviceId = await vault.deviceId();
  deviceId ??= const Uuid().v4();
  await vault.saveDeviceId(deviceId);

  final generated =
      generateBundle(deviceId: deviceId, oneTimePrekeyCount: oneTimePrekeyCount);
  await vault.savePrivate(generated.private);

  final pub = generated.public;
  final deviceNum = await registrar.register(
    deviceId: deviceId,
    registrationId: pub.registrationId,
    identityPub: pub.identityPub,
    signedPrekeyId: pub.signedPrekeyId,
    signedPrekeyPub: pub.signedPrekeyPub,
    signedPrekeySig: pub.signedPrekeySig,
  );
  await vault.saveDeviceNum(deviceNum);

  await registrar.uploadOneTimePrekeys(
    deviceNum: deviceNum,
    prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
  );
  return deviceNum;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/core/crypto/signal_registration_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Run full core suite + analyze**

Run: `flutter test test/core`
Expected: all PASS.
Run: `flutter analyze lib/core`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/core/crypto/signal_registration.dart test/core/crypto/signal_registration_test.dart
git commit -m "feat(crypto): device registration + prekey upload"
```

---

## Self-Review

**Spec coverage:**
- Migration: device_num, normalized prekeys, `fetch_prekey_bundles`, `register_device_bundle`, cipher_type comment fix → Task 1 ✅
- Drift DB (5 tables) → Task 3 ✅
- Four stores → Tasks 4, 5, 6; composite → Task 7 ✅
- Identity key in Keychain, TOFU + change events → Tasks 2, 6 ✅
- `SignalSessionService` (encryptFor fan-out / decryptFrom) → Task 9 ✅
- Injected bundle source → Task 8 ✅
- `ensureRegistered`, prekey replenishment → Task 11 ✅
- Test matrix (round-trip, restart survival, out-of-order, fan-out, prekey type constants, exhaustion, identity change) → Tasks 6, 9, 10 ✅

**Gap found and closed while planning:** the spec assumed `getLocalRegistrationId()` would work, but nothing persisted the registration id (`PrivateBundle` lacked it) or the device number. Added as Task 2, which Tasks 6/9/11 depend on.

**Deviations from spec, deliberate:**
- `identityChanges` is exposed as a **Drift table** (`signalIdentityChanges`) rather than a `Stream<IdentityChange>` on the service. Sub-project 2 renders history from the DB anyway, and a table is queryable/joinable; a stream would add lifecycle for no gain. The data the spec asked for is all there.
- `replenishPrekeysIfLow` is a free function pair on `DeviceRegistrar` + `ensureRegistered` in `signal_registration.dart` rather than a method on the service, keeping the service focused on encrypt/decrypt.

**Placeholder scan:** none — every code step carries complete code. Task 7 Step 3 notes to delegate any additional composite members rather than stub them.

**Type consistency:** `DeviceBundle`, `EncryptedCopy`, `PreKeyBundleSource.bundlesFor`, `DeviceRegistrar.register/uploadOneTimePrekeys/unconsumedPrekeyCount`, `KeyVault.readRegistrationId/saveDeviceNum/readDeviceNum`, `DriftSignalStore(db, vault)` are used consistently across tasks. `CiphertextMessage.prekeyType/whisperType` used throughout (never literals).

**Known verification limit:** Task 1's RPCs are exercised only by `db push` + `migration list`; there is no DB integration test because local Supabase/Docker is off. The RPC bodies get their real workout in sub-project 2, against Cloud.
