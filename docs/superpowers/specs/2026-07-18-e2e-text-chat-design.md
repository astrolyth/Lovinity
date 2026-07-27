# Sakīnah — E2E Chat, Sub-project 2: Text Chat

**Date:** 2026-07-18
**Status:** Design approved, pending spec review
**Builds on:** sub-projects 1 + 1.5 (Signal session layer + key lifecycle, complete)
**Blocks:** sub-project 3 (encrypted media)

## Summary

Turn the crypto foundation into a working E2E text chat: send/receive with multi-device fan-out, one-shot decryption into a local-first plaintext history, delivered/read receipts, replies, encrypted reactions, and a typing indicator. Text only — media is sub-project 3.

## Two constraints that drive the whole design

1. **`encryptFor` returns a *list* of `EncryptedCopy`** (one ciphertext per recipient device + per the sender's own other devices). One logical message fans out to N ciphertext envelopes. The current `messages` table holds a single ciphertext and cannot represent this.
2. **Double Ratchet decryption is one-shot.** Once a device decrypts a ciphertext, the ratchet advances and that ciphertext can never be decrypted again. Therefore durable history must be **plaintext in local Drift per device**; the server ciphertext is single-use transport, not storage.

## Decisions (agreed)

1. Scope: core send/receive, replies, encrypted reactions, typing indicator.
2. Receipts: delivered + read, always on.
3. Reactions are **encrypted** — a typed payload through the same fan-out, so the server never learns emoji-on-message.
4. Reply target lives **inside the encrypted payload**, not a server column (the reply graph stays private; no server-side threading, which a 2-person chat doesn't need).
5. Server envelopes are **deleted after fetch** ⇒ reinstall starts with blank history (encrypted backup is deferred).
6. Local history is **plaintext at rest**, consistent with the existing Signal Drift DB; encrypted-at-rest is deferred (explicit accepted risk).

## Schema decision

**Envelope table** (chosen over flattening rows or a single ciphertext-per-row): `messages` = the logical message (metadata + receipts, no ciphertext); `message_envelopes` = one ciphertext row per target device. Maps 1:1 onto `encryptFor`'s `List<EncryptedCopy>`; keeps receipts/ordering on the message and per-device crypto on the envelope. Chat has never shipped, so `messages` has no production data and can be restructured cleanly.

## Server schema (migration)

### `messages` (restructured, logical-only)

`id, conversation_id, couple_id, sender_id, sender_device_num int, created_at, delivered_at, read_at`.

Removed: `ciphertext, cipher_type, device_id, recipient_id, attachment_*, ephemeral_until, reply_to` (attachments → sub-project 3; ephemeral deferred; recipient/device move to the envelope; reply target moves into the encrypted payload).

### `message_envelopes` (new)

```
id                 uuid pk
message_id         uuid not null references public.messages(id) on delete cascade
couple_id          uuid not null references public.couples(id) on delete cascade
recipient_id       uuid not null references public.users(id) on delete cascade
recipient_device_num integer not null
cipher_type        smallint not null   -- 3 = prekey (X3DH first msg), 2 = message (per libsignal)
ciphertext         bytea not null
created_at         timestamptz not null default now()
fetched_at         timestamptz
```
Indexes on `(recipient_id, fetched_at)` and `(message_id)`. **RLS:** couple-scoped via `is_couple_member(couple_id)`; a device may `select`/`delete` only rows where `recipient_id = auth.uid()`; inserts are couple-members (the sender writes all envelopes). Added to the `supabase_realtime` publication (verified via `db reset`, given the earlier missing-publication bug).

### `send_message(p_sender_device_num integer, p_envelopes jsonb)` RPC

Security definer. Atomically: resolves the caller's active couple + conversation (`get_or_create_conversation`), inserts one `messages` row (`sender_id = auth.uid()`, `sender_device_num` from the payload), inserts one `message_envelopes` row per element of `p_envelopes` (`{recipient_id, recipient_device_num, cipher_type, ciphertext(hex)}`), bumps `conversations.last_message_at`, and returns the new `message_id` + `created_at`. bytea passed as `\x` hex (the C2 lesson from sub-project 1.5).

### Receipt RPCs

`mark_delivered(p_message_id uuid)` and `mark_read(p_message_id uuid)` — set the timestamp on a message where the caller is the recipient side (couple member, not the sender). Idempotent (only set if null).

## Typed payload — `ChatPayload` (`lib/features/chat/domain/chat_payload.dart`)

Versioned, kind-tagged; `encode() → Uint8List`, `decode(Uint8List)`. Pure, no I/O.

- `text`  → `{v:1, kind:'text', body:String, replyToMessageId:String?}`
- `reaction` → `{v:1, kind:'reaction', targetMessageId:String, emoji:String, op:'add'|'remove'}`

Unknown `kind` / higher `v` → a typed `UnsupportedPayload` (forward-compat: a newer client's payload is skipped, not fatal). The server sees only the ciphertext of this.

## Local storage — Drift (existing Signal DB, new table group)

- `chat_messages`: `id (server uuid) pk, conversation_id, sender_id, body text?, reply_to_message_id text?, created_at, delivered_at?, read_at?, status text` (`sending|sent|delivered|read|failed` — `status` is the sender's own outbound state; inbound rows are stored already-final).
- `chat_reactions`: `(message_id, reactor_id, emoji)` pk, `created_at`.

Schema version bumped with a `MigrationStrategy` that creates the new tables on upgrade (the pattern established in sub-project 1.5 — existing installs must not crash). Plaintext at rest.

## Data flow

### Send (text or reaction)
1. Build `ChatPayload`, `encode()`.
2. `signalSessionService.encryptFor(recipientUserId: spouseId, plaintext)` → `List<EncryptedCopy>` (spouse devices + own other devices).
3. `send_message` RPC writes the message + envelopes; returns `message_id`.
4. **Optimistically** store locally: text → a `chat_messages` row keyed by `message_id`, `status: sent`; reaction → a `chat_reactions` row. (The sender already holds the plaintext; you cannot decrypt your own same-device envelope — the self-envelopes are for the sender's *other* devices.)

### Receive
1. Stream `message_envelopes` where `recipient_id = me`, filtered to `recipient_device_num = my device`, `fetched_at is null`.
2. `decryptFrom(senderUserId, senderDeviceNum, ciphertext, cipherType)` → bytes → `ChatPayload.decode`.
3. Apply by kind: `text` → upsert `chat_messages` (idempotent by `message_id`); `reaction` → upsert/remove `chat_reactions`.
4. `mark_delivered(message_id)`; delete my envelope row (spent). On chat open with the row visible → `mark_read(message_id)`.

### Receipts
The sender's UI watches the logical `messages` row's `delivered_at`/`read_at` (realtime) and renders Sent → Delivered → Read.

### Typing
Supabase Realtime **broadcast** on channel `chat:{conversationId}`, event `{typing: bool, userId}`, debounced (~3s stop). Not persisted, not encrypted.

## `ChatService` (`lib/features/chat/domain/chat_service.dart`)

The orchestration seam the UI talks to; it owns the encrypt→persist→send and receive→decrypt→store pipelines and depends on `SignalSessionService`, `ChatRepository`, and `ChatStore`. UI never touches crypto or Supabase directly.

## Error handling

- **Duplicate envelope** (realtime re-delivery, or reprocessing after a crash): local upsert keyed by `message_id` is idempotent; envelope delete is `if exists`.
- **Undecryptable envelope** — a `whisper (2)` arriving before its session exists (its `prekey (3)` sibling hasn't been processed): do not crash or drop; leave `fetched_at` null and retry on the next stream tick / app start. A bounded retry counter avoids an infinite loop on a genuinely corrupt envelope, after which it is logged and marked dead.
- **Send failure** (offline / RPC error): the optimistic `chat_messages` row goes `failed`; retryable from the UI.
- **Out-of-order** delivery: handled by the ratchet's skipped-key logic (tested in sub-project 1).
- Failures use the existing `AppFailure` pattern (`core/errors/failures.dart`).

## Testing

- **Unit:** `ChatPayload` round-trip (text, reply, reaction, remove); unknown-kind/version → `UnsupportedPayload`; `chat_messages` status transitions.
- **Integration (local Supabase + real crypto, sub-project 1.5's two-device harness):**
  - Alice sends → Bob's envelope decrypts to the exact plaintext.
  - Fan-out reaches Alice's *second* device (own-device sync).
  - `delivered_at`/`read_at` flip and are visible to the sender.
  - Encrypted reaction applies to the right target message on the other side.
  - Duplicate envelope delivery is idempotent (one local row).
  - Envelope is deleted after fetch; a spent ciphertext is never re-read.
  - A `whisper` arriving before its `prekey` sibling is retried, not dropped.
- **Widget:** message list renders sent/received bubbles with correct alignment + receipt ticks; composer sends; reply preview; reaction row; typing indicator appears/clears.

## Out of scope

- Media / attachments (sub-project 3).
- Ephemeral / disappearing messages.
- Message editing or deleting.
- Encrypted-at-rest local DB, and encrypted backup / cross-device history recovery (deferred).
- Safety-number verification UI (sub-project 1 records identity changes; surfacing them is later).
- Group chat (the app is two-person by construction).
