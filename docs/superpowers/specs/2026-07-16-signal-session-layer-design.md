# Sakīnah — E2E Chat, Sub-project 1: Signal Session Layer

**Date:** 2026-07-16
**Status:** Design approved, pending spec review
**Package:** `libsignal_protocol_dart` 0.8.2 (already a dependency)

## Context

E2E encrypted chat with media is **three subsystems**, not one feature. Phase 0 shipped only key *generation* (~10% of the crypto). This spec covers **sub-project 1 only**: the session layer that everything else depends on.

| # | Sub-project | Status |
|---|---|---|
| **1** | **Signal session layer** — stores, X3DH, Double Ratchet, persistence, prekey lifecycle | **this spec** |
| 2 | Text chat — message model, realtime send/receive, UI | later |
| 3 | Encrypted media — Storage buckets, per-file AES key, upload/download | later |

Nothing here is user-visible. The deliverable is a **trustworthy, test-proven crypto foundation**. That is deliberate: E2E crypto that is "mostly working" is worse than none, because the failure modes are silent and users trust the padlock.

## Decisions (agreed)

1. **Session layer first**, no UI.
2. **Multi-device fan-out** — a user may have several devices; every message is encrypted once per recipient device *and* per the sender's own other devices.
3. **Drift/SQLite for stores; identity private key stays in the Keychain.** Chosen because it makes the deferred encrypted-backup feasible — you can encrypt/export a DB, not scattered Keychain entries.
4. **Encrypted backup later** — history loss on device loss is accepted for now, but the store is structured so backup/restore can be added without a rewrite.
5. **Identity change: accept but warn.** TOFU; on change, accept the new identity and record an event so chat can surface "their security code changed."

## What exists

- `generateBundle()` (`lib/core/crypto/signal_keys.dart`) — identity, registration id, signed prekey, 20 one-time prekeys.
- `KeyVault` (`lib/core/crypto/key_vault.dart`) — device id + private bundle in the Keychain.
- `signal_key_bundles` table, populated on sign-up.
- **Nothing else.** No stores, no X3DH, no `SessionCipher`, no session persistence, no prekey consumption.

## Verified API facts

- `CiphertextMessage.prekeyType = 3` (X3DH first message), `whisperType = 2` (subsequent).
  **The existing schema comment on `messages.cipher_type` — "1 (pre-key) or 3 (message)" — is wrong on both counts and must be corrected.**
- Store interfaces (`IdentityKeyStore`, `PreKeyStore`, `SignedPreKeyStore`, `SessionStore`, composite `SignalProtocolStore`) are all `Future`-based, so Drift-backed implementations fit directly.
- `SignalProtocolAddress` is `(String name, int deviceId)` — an **int**.

## Schema (migration)

### 1. Integer device number

`signal_key_bundles.device_id` is a UUID (text), but libsignal addresses require an **int**. Add:

- `device_num integer` on `signal_key_bundles`, `unique (user_id, device_num)`.
- Assigned by RPC `register_device_bundle(...)` (security definer), which allocates `max(device_num)+1` for the caller atomically and upserts the bundle. Client-side allocation would race across devices.

### 2. Normalize one-time prekeys

`one_time_prekeys` is currently a jsonb array, which **cannot be popped atomically** — handing the same prekey to two senders breaks the handshake. Replace with:

```
signal_one_time_prekeys(
  user_id uuid, device_num int, prekey_id int,
  pub bytea not null, consumed_at timestamptz,
  primary key (user_id, device_num, prekey_id)
)
```

### 3. `fetch_prekey_bundles(p_target_user uuid)` RPC

Security definer. Returns **one row per device** of the target: `device_num, registration_id, identity_pub, signed_prekey_id, signed_prekey_pub, signed_prekey_sig, one_time_prekey_id, one_time_prekey_pub`, atomically consuming one unused one-time prekey per device (`update … where consumed_at is null … returning`, `limit 1`). Returns a null one-time prekey when exhausted — the handshake then proceeds from the signed prekey alone.

**Authorisation:** callable when the target is the caller's **spouse or the caller themselves** (self is required to reach the sender's own other devices for fan-out).

### 4. Prekey replenishment

The client counts its unconsumed rows and tops up when below a threshold (10), inserting via existing own-row RLS. No new RPC.

## Drift database (`lib/core/storage/`)

| Table | Holds |
|---|---|
| `signal_sessions(name, device_num, record)` | ratchet/session state |
| `signal_prekeys(prekey_id, record)` | one-time prekey privates |
| `signal_signed_prekeys(signed_prekey_id, record)` | signed prekey privates |
| `signal_identities(name, device_num, identity_key, first_seen)` | trusted remote identities |
| `signal_identity_changes(name, device_num, changed_at)` | change events for the chat warning |

The **identity keypair and registration id remain in the Keychain** via `KeyVault`; the DB never holds them. Introduces `drift` + `build_runner` codegen (both already in `pubspec.yaml`, currently unused).

## Stores (`lib/core/crypto/stores/`)

`DriftSessionStore`, `DriftPreKeyStore`, `DriftSignedPreKeyStore`, `DriftIdentityKeyStore`, composed into a `SignalProtocolStore`. Each is a thin, independently testable adapter over one Drift table.

`DriftIdentityKeyStore` encodes the trust policy: `isTrustedIdentity` returns true (TOFU + accept-on-change); `saveIdentity` detects a differing key for a known address and writes a `signal_identity_changes` row.

## `SignalSessionService` (`lib/core/crypto/signal_session_service.dart`)

The **only** crypto API the rest of the app uses. Sub-project 2 must never touch libsignal directly.

```dart
Future<void> ensureRegistered();

/// Fan-out: one copy per recipient device + per the sender's own other devices.
Future<List<EncryptedCopy>> encryptFor({
  required String recipientUserId,
  required Uint8List plaintext,
});

Future<Uint8List> decryptFrom({
  required String senderUserId,
  required int senderDeviceNum,
  required Uint8List ciphertext,
  required int cipherType,
});

Stream<IdentityChange> identityChanges;
Future<void> replenishPrekeysIfLow();
```

`EncryptedCopy` = `(userId, deviceNum, ciphertext, cipherType)` where `cipherType` is `prekeyType (3)` for the first message to a device and `whisperType (2)` thereafter.

`encryptFor` establishes a session via `SessionBuilder.processPreKeyBundle` for any target device with no existing session, then encrypts with `SessionCipher`.

**Bundle source is injected** (an interface over the `fetch_prekey_bundles` RPC) so the service is unit-testable with a fake, no server required.

## Error handling

- **Prekey exhausted** → proceed with the signed prekey only (not an error).
- **No bundle for a user** (never registered) → typed failure; caller surfaces "they haven't set up their device yet."
- **Decrypt failure** (duplicate, corrupt, or unknown session) → typed failure; never crash the app, never silently drop.
- **Identity changed** → accept, record the event, continue.
- Failures use the existing `AppFailure` pattern in `core/errors/failures.dart`.

## Testing

The deliverable. All run **without UI or a server** — Drift in-memory + a fake bundle source.

| Test | Why |
|---|---|
| Round-trip encrypt→decrypt | baseline |
| **Restart survival** — rebuild the service from the DB, decrypt a message sent before the "restart" | **the #1 silent-failure mode; the most important test here** |
| Out-of-order delivery (3,1,2) | ratchet skipped-key handling |
| Fan-out: Alice×2 devices, Bob×2 → 3 copies, each decryptable only by its own device | the multi-device guarantee |
| First message is `prekeyType (3)`, subsequent are `whisperType (2)` | guards the corrected constants |
| Prekey exhaustion → session still establishes | signed-prekey fallback |
| Identity change → event recorded, encryption continues | trust policy |

The RPC and migration are verified by `supabase db push` plus SQL checks (local Supabase is off; the project runs against Cloud, so no integration test).

## Out of scope

- Chat UI, `messages` table changes, realtime wiring (sub-project 2).
- Media/attachments (sub-project 3).
- Encrypted backup/restore (deferred; the schema keeps it feasible).
- Safety-number display/verification UI — this spec only *records* identity changes.
- Sender-key / group messaging (`senderKeyType`) — the app is two-person by construction.
