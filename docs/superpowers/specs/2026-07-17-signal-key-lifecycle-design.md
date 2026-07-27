# Sakīnah — E2E Chat, Sub-project 1.5: Signal Key Lifecycle

**Date:** 2026-07-17
**Status:** Design approved, pending spec review
**Follows:** `2026-07-16-signal-session-layer-design.md` (sub-project 1, complete)
**Blocks:** sub-project 2 (text chat)

## Why this exists

Sub-project 1's final review found four issues that share one root cause: **the key-id lifecycle was never designed**. Each is individually capable of silently breaking messaging, and none can be safely papered over in the chat UI later.

| Issue | Consequence today |
|---|---|
| `encryptFor` fetches bundles for recipient AND self on **every send**, and `fetch_prekey_bundles` **consumes** a one-time prekey per device | ~N+2 prekeys burned per message purely for device-roster discovery; an active conversation drains a 20-key pool in a handful of messages |
| No replenishment path (`unconsumedPrekeyCount` has zero callers) | 20 prekeys at registration, never topped up; then every handshake silently downgrades to signed-prekey-only |
| Signed prekey id hardcoded to `1` | Re-registration overwrites spk id 1; any in-flight `PreKeySignalMessage` referencing the old one becomes permanently undecryptable |
| One-time prekey ids always restart at `1` | A naive replenish reissues consumed ids with **different key material** → silently undecryptable messages |

Additionally, sub-project 1 shipped with **no integration tests at all** — Docker was off, so both RPCs and the bytea write path were verified by inspection only. That posture is what allowed **C1** (nothing populated the prekey stores) and **C2** (bytea sent as a JSON int array) to reach the final review. **C2's fix is still unproven against a real database.**

## Decisions (agreed)

1. **Docker + local Supabase is the dev/test environment now.** Real integration tests run against local Postgres. Supabase **Cloud is for production deployment later**, once everything works locally.
2. **Signed prekey rotation is made SAFE, not scheduled.** Monotonic ids + retention of previous signed prekeys, so re-registration rotates instead of corrupting. No background scheduler — the app has no background-job infrastructure and building one now would be speculative.
3. **Roster and handshake are split** into two RPCs so an established session consumes zero prekeys.

## Components

### 1. Roster / handshake split (fixes exhaustion)

New migration. Replaces `fetch_prekey_bundles(p_target_user)`:

- **`list_devices(p_target_user uuid)`** → the target's `device_num`s. **Consumes nothing.** Security definer; same authorisation as before (target must be the caller **or** a member of the caller's active couple).
- **`fetch_prekey_bundle(p_target_user uuid, p_device_num integer)`** → **one** device's bundle, atomically consuming **one** unused one-time prekey (`for update skip locked`, as today). Returns a null one-time prekey when exhausted — the handshake then proceeds from the signed prekey alone. Same authorisation.

`fetch_prekey_bundles` (plural) is dropped; its only caller is `SupabasePreKeyBundleSource`, so this is a clean swap.

**Client:** `PreKeyBundleSource` becomes:
```dart
Future<List<int>> deviceNumsFor(String userId);              // roster, non-consuming
Future<DeviceBundle?> bundleFor(String userId, int deviceNum); // handshake, consuming
```
`SignalSessionService.encryptFor` calls `deviceNumsFor` for the fan-out roster, then calls `bundleFor` **only** for devices where `containsSession` is false. An established conversation consumes **zero** prekeys per message.

### 2. Monotonic key ids

New Drift table `signal_meta(key text primary key, value text)`, holding `next_prekey_id` and `next_signed_prekey_id`.

**It must be a persisted counter, not `max(id)+1`.** Consumed one-time prekeys are *deleted* from the local store (`DriftPreKeyStore.removePreKey`), so `max()` walks backwards and would reissue an id with **different key material** — the spouse's stored bundle and ours would disagree, producing silently undecryptable messages.

The counter lives in Drift rather than the Keychain: it is state, not a secret, and it shares a lifecycle with the prekeys it numbers (wiped together, and it travels with a future encrypted DB backup).

`signal_keys.dart` gains a way to generate a prekey batch and a signed prekey **from a given starting id**, rather than hardcoding `1`. Default behaviour for a fresh device is unchanged (starts at 1).

### 3. Safe signed-prekey rotation

- Signed prekey ids come from `next_signed_prekey_id` (monotonic).
- Rotation **retains** previous signed prekeys in `signal_signed_prekeys`. libsignal resolves an incoming `PreKeySignalMessage` by the spk id it names, so a retained old spk keeps in-flight messages decryptable.
- Re-registration (including the resume path) therefore rotates safely instead of overwriting id 1.
- **Pruning** old signed prekeys after a retention window is explicitly **deferred** — retention is unbounded for now, which is safe (only wasteful) for a two-person app.

### 4. Replenishment

```dart
Future<void> replenishPrekeysIfLow({
  required SignalDb db,
  required KeyVault vault,
  required DeviceRegistrar registrar,
  int threshold = 10,
  int topUpTo = 20,
});
```
Counts unconsumed prekeys server-side via the existing `unconsumedPrekeyCount` (which finally gets a caller), and if below `threshold`, generates the shortfall **starting from `next_prekey_id`**, stores them locally, uploads the publics, and advances the counter. Called from `ensureRegistered` on app start.

Failure is **non-fatal** — log and retry next launch. A device that fails to top up still works; its handshakes degrade to signed-prekey-only, which is a forward-secrecy downgrade but not an outage.

### 5. Integration tests (Docker) — the real deliverable

`supabase start` + `supabase db reset` locally. Tests against local Postgres, proving for the first time:

| Test | Proves |
|---|---|
| **bytea round-trip**: write via `register_device_bundle`, read back via `fetch_prekey_bundle`, assert bytes identical | **the C2 fix** — the only path that has never touched a database |
| `list_devices` consumes nothing (count unchanged before/after) | the exhaustion fix |
| `fetch_prekey_bundle` consumes exactly one, and a second call gets a *different* prekey | atomic consumption |
| exhausted device returns a row with null one-time prekey (not a skipped device) | a device stays reachable |
| two concurrent registrations of new devices get distinct `device_num`s | the advisory lock (migration `…000004`) |
| replenishment tops up to `topUpTo` and never reissues a consumed id | the counter |

**Bonus:** the onboarding / scoreboard / preferences integration tests written earlier have been unrunnable with Docker off. They come back to life, so the full `flutter test` suite should pass again.

## Error handling

- Replenishment failure → non-fatal, retried next launch.
- A device in the roster with no fetchable bundle → typed failure; the caller surfaces it rather than silently dropping the device (a silently dropped device can never read messages).
- Prekey exhaustion → not an error; signed-prekey-only handshake.
- Existing `AppFailure` pattern (`core/errors/failures.dart`).

## Out of scope

- Pruning retained signed prekeys (deferred; retention is unbounded).
- Scheduled/background rotation (no background-job infrastructure yet).
- Chat UI, message model, media (sub-projects 2 and 3).
- Encrypted backup (deferred; the Drift split keeps it feasible).
- Deploying these migrations to Cloud — that happens once local testing is green.
