# Chat media attachments & emoji picker — design

## Context

`lib/features/chat/` is a working E2E-encrypted (Signal protocol) chat: text
messages and emoji reactions only. `ChatPayload` (`domain/chat_payload.dart`)
is a sealed class with `TextPayload`, `ReactionPayload`, and
`UnsupportedPayload`. There is no attachment support, no image/video/emoji
picker packages installed, and no Supabase Storage usage anywhere in the app.

This spec adds photo attachments, video attachments (capped ~60s), and an
in-app emoji picker for composing messages. Memoji support and the in-app
notification inbox (`docs/superpowers/plans/2026-07-27-notification-inbox.md`)
are explicitly out of scope — see "Out of scope" below.

## Goals

- Send/receive photo and video attachments in the existing 1:1 couple chat,
  preserving true end-to-end encryption (server never sees plaintext media or
  the key that decrypts it).
- Optional caption text on an attachment message.
- An in-app emoji picker in the composer (search/browse by category), usable
  for both new messages and reactions.
- Push notifications for attachment messages, reusing the existing
  content-free push pipeline — no new backend push logic.

## Out of scope

- Memoji (iOS-only; revisit later per prior decision).
- The in-app notification inbox/bell (separate, already-spec'd, unimplemented
  feature — `docs/superpowers/plans/2026-07-27-notification-inbox.md`).
- Video re-encoding/transcoding. Size is controlled only via a duration cap at
  the picker and no re-encode.
- Auto-download of any attachment. Every attachment is tap-to-load; only an
  embedded low-res thumbnail is ever shown without an explicit tap.
- Multi-device fan-out of attachment ciphertext blobs beyond what the existing
  `encryptFor` "other own devices" behavior already covers for the pointer
  message (the Storage object itself is fetched independently by whichever
  device decrypts the pointer).

## Architecture

### Two-layer encryption

1. **Pointer layer (existing Signal session, unchanged):** a new
   `AttachmentPayload` JSON pointer is encrypted exactly like a `TextPayload`
   today, via `SignalSessionService.encryptFor` and `ChatRepository.sendEnvelopes`
   → `send_message` RPC. No changes to the crypto core.
2. **Media layer (new):** the actual photo/video bytes are encrypted
   client-side with a **fresh random AES-256-GCM key generated per
   attachment**, and the ciphertext is uploaded to a new private Supabase
   Storage bucket. The key and nonce travel only inside the Signal-encrypted
   pointer (layer 1) — Supabase Storage holds only opaque ciphertext it can
   never decrypt.

This mirrors how Signal/WhatsApp handle attachments and keeps the "server
never sees plaintext" property that the existing text chat already has.

### `AttachmentPayload`

Added to `lib/features/chat/domain/chat_payload.dart` as a new `ChatPayload`
subtype:

```dart
enum AttachmentKind { photo, video }

class AttachmentPayload extends ChatPayload {
  final String attachmentId;       // uuid, also the Storage object name
  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;             // size of the encrypted blob in Storage
  final int? width, height;        // photo only
  final int? durationMs;           // video only
  final String storageKey;         // "<couple_id>/<attachment_id>"
  final Uint8List encKey;          // 32 bytes, AES-256
  final Uint8List nonce;           // 12 bytes, GCM
  final String thumbnailB64;       // small JPEG, embedded inline (no download)
  final String? caption;
  final String? replyToMessageId;
}
```

The thumbnail (~<15KB target) is embedded directly in the encrypted pointer,
not stored separately — it decrypts and renders the instant the message
arrives, before any Storage round-trip. `encodePayload`/`decodePayload` gain a
`'attachment'` case following the existing versioned-JSON-map pattern (bump
handling stays backward compatible: unknown/future kinds decode to
`UnsupportedPayload`, per the existing `_payloadVersion` guard).

### Send flow (`ChatService.sendPhoto` / `sendVideo`)

New methods alongside `sendText`/`sendReaction`, following the same
optimistic-row / try-catch-mark-failed shape as `sendText`:

1. Pick file (`image_picker`: camera or gallery for photo; video with
   `maxDuration: Duration(seconds: 60)`).
2. Compress:
   - Photo: `flutter_image_compress`, max dimension 1600px, JPEG quality 80.
   - Video: no re-encode — the duration cap at the picker is the only size
     control.
3. Generate a thumbnail:
   - Photo: downscaled copy of the compressed image (e.g. 200px, JPEG q60).
   - Video: extract the first frame via `video_thumbnail`, same downscale.
4. Generate a random 32-byte key + 12-byte nonce (`cryptography` package,
   `AesGcm.with256bits()`), encrypt the compressed media bytes.
5. Upload ciphertext to the `chat-media` Storage bucket at
   `<couple_id>/<attachment_id>` (couple id from the same source
   `ChatService`/providers already use).
6. Build `AttachmentPayload`, optimistic local row (status `sending`), then
   `session.encryptFor` + `repo.sendEnvelopes` exactly like `sendText` — same
   `send_message` RPC, same default `p_notify_kind` ('message'), so the
   existing generic push fires with zero backend changes.
7. On any failure at any step, mark the local row `failed` (matches existing
   `sendText` error handling — never throws to the caller).

### Receive flow (`ChatService._handleInboxRow`)

New `case AttachmentPayload():` arm alongside the existing `TextPayload`/
`ReactionPayload` cases: upserts a `ChatMessages` row with the attachment
columns populated and `downloadStatus = 'none'`. The embedded thumbnail
decodes and renders immediately; no Storage access happens until the user
taps the bubble.

### On-tap download (new: `ChatService.downloadAttachment(messageId)`)

1. Set `downloadStatus = 'downloading'`.
2. Fetch the ciphertext blob from `chat-media` at the row's `storageKey`.
3. Decrypt using the row's stored `encKey`/`nonce`.
4. Write plaintext to a local cache file (`path_provider` app-support
   directory, named by `attachmentId`).
5. Set `localMediaPath` + `downloadStatus = 'downloaded'`; on any failure,
   `downloadStatus = 'failed'` with a retry affordance in the UI.

### Storage bucket & RLS

New private bucket `chat-media`. Objects are named `<couple_id>/<attachment_id>`.
A `storage.objects` RLS policy restricts `select`/`insert` to authenticated
users who are a member of that `couple_id` — mirroring the couple-membership
check already used by the `message_envelopes` policies (implementation should
reuse whatever helper/pattern those policies use, e.g. a shared
`is_couple_member` check or an equivalent join against `public.couples`).
No new Postgres tables are needed for this bucket beyond the policy itself.

### Local schema (Drift, `lib/core/storage/signal_db.dart`)

`schemaVersion` 3 → 4. Extend `ChatMessages` with nullable columns:

- `attachmentKind` (text: `'photo'` | `'video'`, null for text messages)
- `mimeType` (text, nullable)
- `sizeBytes` (int, nullable)
- `width`, `height` (int, nullable)
- `durationMs` (int, nullable)
- `storageKey` (text, nullable)
- `encKey` (blob, nullable — 32 bytes)
- `nonce` (blob, nullable — 12 bytes)
- `thumbnailBytes` (blob, nullable)
- `localMediaPath` (text, nullable)
- `downloadStatus` (text, nullable: `'none' | 'downloading' | 'downloaded' | 'failed'`)

Storing the raw AES key locally is consistent with this DB's existing model —
it already holds Signal session/identity key material at rest (see the
`ChatMessages` doc comment: "consistent with the rest of this DB, which
already stores Signal key material"). `MigrationStrategy.onUpgrade` gets a
`if (from < 4) await m.addColumn(...)` block per new column, following the
existing `if (from < 2)` / `if (from < 3)` pattern. `wipeAll()` needs no
changes (it already deletes the whole `chatMessages` table).

`caption` reuses the existing nullable `body` column — an attachment message
with `body != null` renders the text as a caption under the media, same as
how a plain `TextPayload` message renders `body` alone.

### UI

- **Composer** (`chat_screen.dart` `_Composer`): add an attachment button
  (opens a bottom sheet: Camera, Photo Library, Video) and an emoji-toggle
  button that shows/hides an `emoji_picker_flutter` panel above the keyboard,
  inserting the tapped emoji at the cursor position in the existing
  `TextEditingController`.
- **`message_bubble.dart`**: new rendering branch when a message row has a
  non-null `attachmentKind`:
  - `photo`: `Image.memory(thumbnailBytes)` at bubble width; tap opens a
    full-screen viewer, triggering `downloadAttachment` if not already
    downloaded, showing a progress indicator while `downloadStatus ==
    'downloading'`.
  - `video`: thumbnail image with a centered play-icon overlay; tap
    downloads (if needed) then opens a full-screen `video_player`-based
    player.
  - `downloadStatus == 'failed'` shows a small retry affordance, styled like
    the existing failed-send (`!`) receipt treatment.
  - Optional caption (`body`) renders below the media, same text style as a
    normal message body.
  - Existing reaction/reply long-press actions (`_showActions`) apply
    unchanged to attachment bubbles.

### Notifications

No backend changes. `sendPhoto`/`sendVideo` call the same `send_message` RPC
used today by `sendText`, with the default `p_notify_kind = 'message'`, so the
existing trigger dispatches the same generic, content-free "New message from
your partner" push (`supabase/migrations/20260726000001_push_notifications.sql`).
Consistent with that migration's explicit design constraint, nothing
attachment-specific (filename, caption, thumbnail, media type) is ever placed
in a push payload.

### New dependencies (`pubspec.yaml`)

`image_picker`, `flutter_image_compress`, `video_thumbnail`, `video_player`,
`cryptography`, `emoji_picker_flutter`.

## Testing

- `chat_payload_test.dart`: `AttachmentPayload` encode/decode round-trip,
  including the `UnsupportedPayload` fallback for an unknown future kind.
- New unit tests for the AES-256-GCM encrypt/decrypt round-trip helper.
- `chat_service_test.dart`: `sendPhoto`/`sendVideo` against the existing
  mocked `ChatRepository`/`SignalSessionService`/`ChatStore` seams (same
  pattern already used for `sendText`/`sendReaction`), covering the
  optimistic-row-then-failed path on an upload/encrypt failure.
- Widget tests for the attachment bubble's four states: thumbnail-only,
  downloading, downloaded (playable/viewable), failed-with-retry.
- A SQL test for the new `chat-media` bucket RLS policy, alongside the
  existing `message_envelopes` policy tests in `supabase/tests/`.

## Migration / rollout notes

- Existing chat rows are unaffected — all new columns are nullable, and
  `attachmentKind IS NULL` is exactly today's text-message shape.
- The `chat-media` bucket must be created via a new Supabase migration
  (mirrors how `device_push_tokens` etc. were added in
  `20260726000001_push_notifications.sql`), not manually in the dashboard, so
  it applies consistently across environments.
