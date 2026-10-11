# Chat Media Attachments & Emoji Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add end-to-end-encrypted photo and video attachments (with optional captions) plus an in-app emoji picker to the existing 1:1 couple chat, with zero backend changes needed for push notifications.

**Architecture:** Two-layer encryption. The existing Signal Double-Ratchet session (unchanged) encrypts a small JSON "pointer" message carrying a fresh random AES-256-GCM key/nonce, a Supabase Storage path, and an embedded low-res thumbnail. The actual photo/video bytes are encrypted client-side with that random key and uploaded as opaque ciphertext to a new private Storage bucket — the server never holds plaintext media or the key that decrypts it. Every attachment is tap-to-load (thumbnail only until tapped); nothing auto-downloads.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite, Supabase (Postgres + Storage + Realtime), `libsignal_protocol_dart` (unchanged), `cryptography` (new, for AES-256-GCM), `image_picker`, `flutter_image_compress`, `video_thumbnail`, `video_player`, `emoji_picker_flutter` (all new).

## Global Constraints

- Memoji support is explicitly out of scope for this plan.
- The in-app notification inbox/bell is a separate, unimplemented feature (`docs/superpowers/plans/2026-07-27-notification-inbox.md`) — do not build it here.
- No video re-encoding/transcoding: size control is only the picker's 60-second duration cap.
- No auto-download of any attachment, ever — only the embedded thumbnail shows without an explicit tap.
- Photo compression: max dimension 1600px, JPEG quality 80. Thumbnails: max dimension 200px, JPEG quality 60.
- `ChatService` must remain a pure Dart unit with no Flutter-plugin dependency, matching its current form — platform-dependent work (file picking, compression, disk caching) lives behind seams (`MediaPicker`, `MediaCache`), following the same pattern already used for `PushMessaging`/`PushTokenApi` in `lib/core/notifications/push_service.dart`.
- No new backend/push changes: `sendPhoto`/`sendVideo` must go through the existing `send_message` RPC exactly like `sendText`, so the existing generic content-free push fires unchanged.
- Full spec: `docs/superpowers/specs/2026-07-29-chat-media-attachments-design.md`.

---

## File Map

| File | Change |
|---|---|
| `pubspec.yaml` | Add 6 new dependencies |
| `lib/core/crypto/attachment_crypto.dart` | New — AES-256-GCM encrypt/decrypt helpers |
| `lib/features/chat/domain/chat_payload.dart` | Add `AttachmentKind`, `AttachmentPayload`, encode/decode cases |
| `lib/core/storage/signal_db.dart` | Extend `ChatMessages` table, schemaVersion 3→4, migration |
| `lib/features/chat/data/chat_store.dart` | Add `upsertAttachmentMessage`, `updateDownloadStatus`, `messageById` |
| `supabase/migrations/20260729000001_chat_media_storage.sql` | New — `chat-media` bucket + RLS |
| `supabase/tests/chat_media_storage_test.sql` | New — RLS assertions |
| `lib/features/chat/data/chat_repository.dart` | Add `uploadAttachment`, `downloadAttachment` |
| `lib/core/storage/media_cache.dart` | New — `MediaCache` seam + `FileMediaCache` |
| `lib/features/chat/domain/chat_service.dart` | Add `coupleId`, `cache`; `sendPhoto`, `sendVideo`, `downloadAttachment`, receive-side handling |
| `lib/features/chat/domain/chat_providers.dart` | Thread `coupleId`/`cache` into `chatServiceProvider`; add `mediaPickerProvider` |
| `lib/features/chat/presentation/media_picker.dart` | New — `MediaPicker` seam + `DevicePicker` |
| `lib/features/chat/presentation/message_bubble.dart` | Render attachment states |
| `lib/features/chat/presentation/photo_viewer_screen.dart` | New — full-screen photo viewer |
| `lib/features/chat/presentation/video_viewer_screen.dart` | New — full-screen video player |
| `lib/features/chat/presentation/chat_screen.dart` | Composer: attach button + bottom sheet, emoji button + panel |

---

### Task 1: Add media/crypto dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `image_picker`, `flutter_image_compress`, `video_thumbnail`, `video_player`, `cryptography`, `emoji_picker_flutter` packages available to every later task.

- [ ] **Step 1: Add the packages**

Run (each resolves to the latest version compatible with this project's SDK constraint):

```bash
flutter pub add image_picker flutter_image_compress video_thumbnail video_player cryptography emoji_picker_flutter
```

- [ ] **Step 2: Verify the app still analyzes and the existing test suite still passes**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all existing tests PASS (nothing in this task touches app code yet).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(chat): add media/crypto/emoji dependencies for attachments"
```

---

### Task 2: AES-256-GCM attachment encryption helper

**Files:**
- Create: `lib/core/crypto/attachment_crypto.dart`
- Test: `test/core/crypto/attachment_crypto_test.dart`

**Interfaces:**
- Produces:
  - `class EncryptedAttachment { final Uint8List key; final Uint8List nonce; final Uint8List ciphertext; }`
  - `Future<EncryptedAttachment> encryptAttachment(Uint8List plaintext)`
  - `Future<Uint8List> decryptAttachment({required Uint8List ciphertext, required Uint8List key, required Uint8List nonce})`

- [ ] **Step 1: Write the failing test**

Create `test/core/crypto/attachment_crypto_test.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/attachment_crypto.dart';

void main() {
  test('encryptAttachment/decryptAttachment round-trips arbitrary bytes', () async {
    final plaintext = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final enc = await encryptAttachment(plaintext);

    expect(enc.key, hasLength(32));
    expect(enc.nonce, hasLength(12));

    final decrypted = await decryptAttachment(
      ciphertext: enc.ciphertext,
      key: enc.key,
      nonce: enc.nonce,
    );
    expect(decrypted, plaintext);
  });

  test('two encryptions of the same plaintext use different keys, nonces, and ciphertext',
      () async {
    final plaintext = Uint8List.fromList([1, 2, 3, 4]);
    final a = await encryptAttachment(plaintext);
    final b = await encryptAttachment(plaintext);

    expect(a.key, isNot(b.key));
    expect(a.nonce, isNot(b.nonce));
    expect(a.ciphertext, isNot(b.ciphertext));
  });

  test('decryptAttachment throws on tampered ciphertext', () async {
    final plaintext = Uint8List.fromList([9, 9, 9]);
    final enc = await encryptAttachment(plaintext);
    final tampered = Uint8List.fromList(enc.ciphertext);
    tampered[0] ^= 0xFF;

    await expectLater(
      decryptAttachment(ciphertext: tampered, key: enc.key, nonce: enc.nonce),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('decryptAttachment throws with the wrong key', () async {
    final plaintext = Uint8List.fromList([9, 9, 9]);
    final enc = await encryptAttachment(plaintext);
    final wrongKey = Uint8List.fromList(List.filled(32, 1));

    await expectLater(
      decryptAttachment(ciphertext: enc.ciphertext, key: wrongKey, nonce: enc.nonce),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/attachment_crypto_test.dart`
Expected: FAIL — `lib/core/crypto/attachment_crypto.dart` does not exist (import error).

- [ ] **Step 3: Write the implementation**

Create `lib/core/crypto/attachment_crypto.dart`:

```dart
// lib/core/crypto/attachment_crypto.dart
//
// AES-256-GCM encryption for chat attachment bytes (photos/videos). This is a
// SEPARATE key from the Signal session: a fresh random key+nonce is generated
// per attachment, used only to encrypt that one attachment's bytes before
// upload to Supabase Storage. The key/nonce travel only inside the
// Signal-encrypted AttachmentPayload pointer (see chat_payload.dart) -- never
// alongside the ciphertext in Storage -- so Storage holds only opaque bytes
// it can never decrypt.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final _algorithm = AesGcm.with256bits();

/// One attachment's random key/nonce plus its encrypted bytes. [ciphertext]
/// is the GCM ciphertext with the 16-byte authentication tag appended, ready
/// to upload as-is.
class EncryptedAttachment {
  const EncryptedAttachment({
    required this.key,
    required this.nonce,
    required this.ciphertext,
  });

  /// 32 raw bytes (AES-256).
  final Uint8List key;

  /// 12 raw bytes (GCM nonce).
  final Uint8List nonce;

  final Uint8List ciphertext;
}

/// Encrypts [plaintext] under a freshly generated random key and nonce.
Future<EncryptedAttachment> encryptAttachment(Uint8List plaintext) async {
  final secretKey = await _algorithm.newSecretKey();
  final nonce = _algorithm.newNonce();
  final box = await _algorithm.encrypt(plaintext, secretKey: secretKey, nonce: nonce);
  final keyBytes = Uint8List.fromList(await secretKey.extractBytes());
  return EncryptedAttachment(
    key: keyBytes,
    nonce: Uint8List.fromList(nonce),
    ciphertext: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
  );
}

/// Decrypts [ciphertext] (as produced by [encryptAttachment]) using [key] and
/// [nonce]. Throws [SecretBoxAuthenticationError] if the ciphertext was
/// tampered with, or if [key]/[nonce] don't match what encrypted it.
Future<Uint8List> decryptAttachment({
  required Uint8List ciphertext,
  required Uint8List key,
  required Uint8List nonce,
}) async {
  const macLength = 16;
  final cipherBytes = ciphertext.sublist(0, ciphertext.length - macLength);
  final macBytes = ciphertext.sublist(ciphertext.length - macLength);
  final box = SecretBox(cipherBytes, nonce: nonce, mac: Mac(macBytes));
  final clear = await _algorithm.decrypt(box, secretKey: SecretKey(key));
  return Uint8List.fromList(clear);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/attachment_crypto_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/attachment_crypto.dart test/core/crypto/attachment_crypto_test.dart
git commit -m "feat(chat): add AES-256-GCM attachment encryption helper"
```

---

### Task 3: `AttachmentPayload` model

**Files:**
- Modify: `lib/features/chat/domain/chat_payload.dart`
- Test: `test/features/chat/chat_payload_test.dart`

**Interfaces:**
- Consumes: nothing new (pure Dart, `dart:convert`, `dart:typed_data` already imported).
- Produces:
  - `enum AttachmentKind { photo, video }`
  - `class AttachmentPayload extends ChatPayload` with fields: `kind` (`AttachmentKind`), `mimeType` (`String`), `sizeBytes` (`int`), `width`/`height`/`durationMs` (`int?`), `storageKey` (`String`), `encKey`/`nonce`/`thumbnailBytes` (`Uint8List`), `caption`/`replyToMessageId` (`String?`).
  - `encodePayload`/`decodePayload` handle the new `'attachment'` kind (round-trips through Signal encryption unchanged — this is pure JSON encode/decode, no crypto here).

Note: there is deliberately no separate "attachment id" field — the sender generates the chat message's own client-side id up front (exactly as `sendText` already does) and reuses it to build `storageKey` as `<couple_id>/<message_id>`, so no redundant identifier is needed in the payload (Task 8 does this).

- [ ] **Step 1: Write the failing test**

Add to `test/features/chat/chat_payload_test.dart` (append inside `main()`, after the existing reaction round-trip test):

```dart
  test('attachment round-trips a photo, including optional fields', () {
    final p = AttachmentPayload(
      kind: AttachmentKind.photo,
      mimeType: 'image/jpeg',
      sizeBytes: 123456,
      width: 1600,
      height: 1200,
      storageKey: 'couple-1/msg-1',
      encKey: Uint8List.fromList(List.filled(32, 7)),
      nonce: Uint8List.fromList(List.filled(12, 3)),
      thumbnailBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      caption: 'MashaAllah',
      replyToMessageId: 'm0',
    );
    final decoded = decodePayload(encodePayload(p)) as AttachmentPayload;

    expect(decoded.kind, AttachmentKind.photo);
    expect(decoded.mimeType, 'image/jpeg');
    expect(decoded.sizeBytes, 123456);
    expect(decoded.width, 1600);
    expect(decoded.height, 1200);
    expect(decoded.durationMs, isNull);
    expect(decoded.storageKey, 'couple-1/msg-1');
    expect(decoded.encKey, Uint8List.fromList(List.filled(32, 7)));
    expect(decoded.nonce, Uint8List.fromList(List.filled(12, 3)));
    expect(decoded.thumbnailBytes, Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(decoded.caption, 'MashaAllah');
    expect(decoded.replyToMessageId, 'm0');
  });

  test('attachment round-trips a video with durationMs and no caption/reply', () {
    final p = AttachmentPayload(
      kind: AttachmentKind.video,
      mimeType: 'video/mp4',
      sizeBytes: 999,
      durationMs: 45000,
      storageKey: 'couple-1/msg-2',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 2)),
      thumbnailBytes: Uint8List.fromList([9, 8, 7]),
    );
    final decoded = decodePayload(encodePayload(p)) as AttachmentPayload;

    expect(decoded.kind, AttachmentKind.video);
    expect(decoded.durationMs, 45000);
    expect(decoded.width, isNull);
    expect(decoded.height, isNull);
    expect(decoded.caption, isNull);
    expect(decoded.replyToMessageId, isNull);
  });

  test('attachment with malformed mediaKind never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"hologram","mime":"x","size":1,'
      '"storage":"s","key":"AAAA","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('attachment with numeric mime never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"photo","mime":123,"size":1,'
      '"storage":"s","key":"AAAA","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('attachment with non-base64 key never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"photo","mime":"image/jpeg","size":1,'
      '"storage":"s","key":"not-valid-base64!!","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_payload_test.dart`
Expected: FAIL — `AttachmentKind`/`AttachmentPayload` undefined.

- [ ] **Step 3: Implement `AttachmentPayload` and encode/decode**

In `lib/features/chat/domain/chat_payload.dart`, add the enum and class after `ReactionPayload` and before `UnsupportedPayload`:

```dart
enum AttachmentKind { photo, video }

class AttachmentPayload extends ChatPayload {
  const AttachmentPayload({
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    required this.storageKey,
    required this.encKey,
    required this.nonce,
    required this.thumbnailBytes,
    this.caption,
    this.replyToMessageId,
  });

  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  /// Path in the `chat-media` Storage bucket: `<couple_id>/<message_id>`.
  final String storageKey;

  /// 32-byte AES-256 key, random per attachment. Travels ONLY inside this
  /// Signal-encrypted pointer -- never alongside the ciphertext in Storage.
  final Uint8List encKey;

  /// 12-byte GCM nonce.
  final Uint8List nonce;

  /// Small JPEG, embedded inline so a preview renders with zero Storage
  /// round-trip.
  final Uint8List thumbnailBytes;
  final String? caption;
  final String? replyToMessageId;
}
```

Update `encodePayload`'s `switch`, adding a case before `UnsupportedPayload()`:

```dart
    AttachmentPayload() => {
        'v': _payloadVersion,
        'kind': 'attachment',
        'mediaKind': p.kind.name,
        'mime': p.mimeType,
        'size': p.sizeBytes,
        if (p.width != null) 'w': p.width,
        if (p.height != null) 'h': p.height,
        if (p.durationMs != null) 'dur': p.durationMs,
        'storage': p.storageKey,
        'key': base64Encode(p.encKey),
        'nonce': base64Encode(p.nonce),
        'thumb': base64Encode(p.thumbnailBytes),
        if (p.caption != null) 'caption': p.caption,
        if (p.replyToMessageId != null) 'reply': p.replyToMessageId,
      },
```

Update `decodePayload`'s `switch`, adding a case before the `_ => const UnsupportedPayload()` fallback:

```dart
      'attachment'
          when m['mediaKind'] is String &&
              (m['mediaKind'] == 'photo' || m['mediaKind'] == 'video') &&
              m['mime'] is String &&
              m['size'] is num &&
              m['storage'] is String &&
              m['key'] is String &&
              m['nonce'] is String &&
              m['thumb'] is String &&
              (m['w'] == null || m['w'] is num) &&
              (m['h'] == null || m['h'] is num) &&
              (m['dur'] == null || m['dur'] is num) &&
              (m['caption'] == null || m['caption'] is String) &&
              (m['reply'] == null || m['reply'] is String) =>
        AttachmentPayload(
          kind: m['mediaKind'] == 'video' ? AttachmentKind.video : AttachmentKind.photo,
          mimeType: m['mime'] as String,
          sizeBytes: (m['size'] as num).toInt(),
          width: (m['w'] as num?)?.toInt(),
          height: (m['h'] as num?)?.toInt(),
          durationMs: (m['dur'] as num?)?.toInt(),
          storageKey: m['storage'] as String,
          encKey: base64Decode(m['key'] as String),
          nonce: base64Decode(m['nonce'] as String),
          thumbnailBytes: base64Decode(m['thumb'] as String),
          caption: m['caption'] as String?,
          replyToMessageId: m['reply'] as String?,
        ),
```

`base64Decode` throwing `FormatException` on malformed input is caught by `decodePayload`'s existing top-level `try`/`catch (_) { return const UnsupportedPayload(); }` — no new error handling needed here.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_payload_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/domain/chat_payload.dart test/features/chat/chat_payload_test.dart
git commit -m "feat(chat): add AttachmentPayload with photo/video encode-decode"
```

---

### Task 4: Local schema — `ChatMessages` attachment columns + `ChatStore` methods

**Files:**
- Modify: `lib/core/storage/signal_db.dart`
- Modify: `lib/features/chat/data/chat_store.dart`
- Test: `test/features/chat/chat_store_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ChatMessages` table gains nullable columns: `attachmentKind`, `mimeType` (`TextColumn`), `sizeBytes`, `width`, `height`, `durationMs` (`IntColumn`), `storageKey`, `localMediaPath`, `downloadStatus` (`TextColumn`), `encKey`, `nonce`, `thumbnailBytes` (`BlobColumn`).
  - `SignalDb.schemaVersion` → `4`.
  - `ChatStore.upsertAttachmentMessage({required id, required senderId, required attachmentKind, required mimeType, required sizeBytes, width, height, durationMs, required storageKey, required encKey, required nonce, required thumbnailBytes, caption, replyToMessageId, required createdAt, required status, localMediaPath, downloadStatus = 'none'})`
  - `ChatStore.updateDownloadStatus({required id, required status, String? localMediaPath})`
  - `ChatStore.messageById(String id) -> Future<ChatMessageRow?>`

- [ ] **Step 1: Write the failing test**

Add to `test/features/chat/chat_store_test.dart` (add `import 'dart:typed_data';` at the top, and these tests inside `main()`):

```dart
  test('upsertAttachmentMessage stores every attachment field, retrievable via messageById',
      () async {
    await store.upsertAttachmentMessage(
      id: 'a1',
      senderId: 'me',
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: 1234,
      width: 800,
      height: 600,
      storageKey: 'couple-1/a1',
      encKey: Uint8List.fromList(List.filled(32, 7)),
      nonce: Uint8List.fromList(List.filled(12, 3)),
      thumbnailBytes: Uint8List.fromList([1, 2, 3]),
      caption: 'nice view',
      createdAt: DateTime(2026),
      status: 'sent',
    );

    final row = await store.messageById('a1');
    expect(row, isNotNull);
    expect(row!.attachmentKind, 'photo');
    expect(row.mimeType, 'image/jpeg');
    expect(row.sizeBytes, 1234);
    expect(row.width, 800);
    expect(row.height, 600);
    expect(row.durationMs, isNull);
    expect(row.storageKey, 'couple-1/a1');
    expect(row.encKey, Uint8List.fromList(List.filled(32, 7)));
    expect(row.nonce, Uint8List.fromList(List.filled(12, 3)));
    expect(row.thumbnailBytes, [1, 2, 3]);
    expect(row.body, 'nice view');
    expect(row.downloadStatus, 'none');
  });

  test('messageById returns null for an unknown id', () async {
    expect(await store.messageById('nope'), isNull);
  });

  test('updateDownloadStatus sets status and localMediaPath', () async {
    await store.upsertAttachmentMessage(
      id: 'a2',
      senderId: 'me',
      attachmentKind: 'video',
      mimeType: 'video/mp4',
      sizeBytes: 999,
      durationMs: 5000,
      storageKey: 'couple-1/a2',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: Uint8List.fromList([9]),
      createdAt: DateTime(2026),
      status: 'delivered',
    );

    await store.updateDownloadStatus(
        id: 'a2', status: 'downloaded', localMediaPath: '/tmp/a2.mp4');

    final row = await store.messageById('a2');
    expect(row!.downloadStatus, 'downloaded');
    expect(row.localMediaPath, '/tmp/a2.mp4');
  });

  test('a plain text message (no attachment fields) has null attachmentKind/downloadStatus',
      () async {
    await store.upsertMessage(id: 't1', senderId: 'a', body: 'hi',
        createdAt: DateTime(2026), status: 'sent');
    final row = await store.messageById('t1');
    expect(row!.attachmentKind, isNull);
    expect(row.downloadStatus, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: FAIL — `upsertAttachmentMessage`/`updateDownloadStatus`/`messageById` undefined, and the new columns don't exist on `ChatMessage`.

- [ ] **Step 3: Extend the Drift schema**

In `lib/core/storage/signal_db.dart`, add columns to the `ChatMessages` class (after `status`, before the `primaryKey` override):

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
  // Attachment fields -- all null for a plain text message. attachmentKind
  // is 'photo' | 'video' | null.
  TextColumn get attachmentKind => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get storageKey => text().nullable()();
  BlobColumn get encKey => blob().nullable()();
  BlobColumn get nonce => blob().nullable()();
  BlobColumn get thumbnailBytes => blob().nullable()();
  TextColumn get localMediaPath => text().nullable()();
  TextColumn get downloadStatus => text().nullable()(); // none|downloading|downloaded|failed
  @override
  Set<Column> get primaryKey => {id};
}
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
        },
      );
```

`wipeAll()` needs no change — it already does `await delete(chatMessages).go();`, which covers every column.

- [ ] **Step 4: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with no errors; `lib/core/storage/signal_db.g.dart` is regenerated with the new columns on the generated `ChatMessage` row class and `ChatMessagesCompanion`.

- [ ] **Step 5: Implement the new `ChatStore` methods**

In `lib/features/chat/data/chat_store.dart`, add after `messageExists`:

```dart
  Future<ChatMessageRow?> messageById(String id) {
    return (_db.select(_db.chatMessages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
```

Add after `upsertMessage`:

```dart
  Future<void> upsertAttachmentMessage({
    required String id,
    required String senderId,
    required String attachmentKind, // 'photo' | 'video'
    required String mimeType,
    required int sizeBytes,
    int? width,
    int? height,
    int? durationMs,
    required String storageKey,
    required Uint8List encKey,
    required Uint8List nonce,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
    required DateTime createdAt,
    required String status,
    String? localMediaPath,
    String downloadStatus = 'none',
  }) {
    return _db.into(_db.chatMessages).insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            id: id,
            senderId: senderId,
            body: Value(caption),
            replyToMessageId: Value(replyToMessageId),
            createdAt: createdAt,
            status: status,
            attachmentKind: Value(attachmentKind),
            mimeType: Value(mimeType),
            sizeBytes: Value(sizeBytes),
            width: Value(width),
            height: Value(height),
            durationMs: Value(durationMs),
            storageKey: Value(storageKey),
            encKey: Value(encKey),
            nonce: Value(nonce),
            thumbnailBytes: Value(thumbnailBytes),
            localMediaPath: Value(localMediaPath),
            downloadStatus: Value(downloadStatus),
          ),
        );
  }

  Future<void> updateDownloadStatus({
    required String id,
    required String status,
    String? localMediaPath,
  }) {
    return (_db.update(_db.chatMessages)..where((t) => t.id.equals(id))).write(
      ChatMessagesCompanion(
        downloadStatus: Value(status),
        localMediaPath:
            localMediaPath != null ? Value(localMediaPath) : const Value.absent(),
      ),
    );
  }
```

Add `import 'dart:typed_data';` to the top of `chat_store.dart` (needed for the `Uint8List` parameters).

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_store_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 7: Run the full test suite to catch any schema-change fallout**

Run: `flutter test --exclude-tags integration`
Expected: PASS (the new nullable columns must not break any existing `ChatMessage`/`ChatMessagesCompanion` usage).

- [ ] **Step 8: Commit**

```bash
git add lib/core/storage/signal_db.dart lib/core/storage/signal_db.g.dart \
        lib/features/chat/data/chat_store.dart test/features/chat/chat_store_test.dart
git commit -m "feat(chat): add attachment columns to local chat schema (v4)"
```

---

### Task 5: Supabase `chat-media` Storage bucket + RLS

**Files:**
- Create: `supabase/migrations/20260729000001_chat_media_storage.sql`
- Create: `supabase/tests/chat_media_storage_test.sql`

**Interfaces:**
- Consumes: `public.is_couple_member(uuid)` (already defined in `supabase/migrations/20260712000001_foundation.sql`).
- Produces: a private Storage bucket `chat-media`, with `select`/`insert` restricted to members of the couple named by the first path segment of the object name (`<couple_id>/<message_id>`).

- [ ] **Step 1: Write the failing SQL test**

Create `supabase/tests/chat_media_storage_test.sql`:

```sql
-- Plain psql assertion script for 20260729000001_chat_media_storage.sql.
-- Same style as supabase/tests/push_notifications_test.sql: DO blocks that
-- RAISE EXCEPTION on failure and RAISE NOTICE 'PASS: ...' on success, run
-- inside a transaction that is ROLLBACK'd at the end.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/chat_media_storage_test.sql

begin;

-- ------------------------------------------------------------------
-- Fixtures: three unrelated users, A+B paired, C left out.
-- ------------------------------------------------------------------
insert into auth.users (id) values
  ('99999999-2000-0000-0000-00000000000a'),
  ('99999999-2000-0000-0000-00000000000b'),
  ('99999999-2000-0000-0000-00000000000c');

insert into public.couples (id, member_a, member_b)
values ('99999999-2000-0000-0000-0000000000c1',
        '99999999-2000-0000-0000-00000000000a',
        '99999999-2000-0000-0000-00000000000b');

-- ------------------------------------------------------------------
-- 1. Couple member A can insert an object under their own couple's path.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000a';

insert into storage.objects (bucket_id, name)
values ('chat-media', '99999999-2000-0000-0000-0000000000c1/msg-1');

do $$
begin
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: couple member A could not insert under their own couple path';
  end if;
  raise notice 'PASS: couple member A inserted an object under their couple path';
end $$;

reset role;

-- ------------------------------------------------------------------
-- 2. The spouse (B) can read the same object.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000b';

do $$
begin
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: spouse B could not read the couple''s attachment object';
  end if;
  raise notice 'PASS: spouse B read the couple''s attachment object';
end $$;

reset role;

-- ------------------------------------------------------------------
-- 3. An outsider (C) cannot read the couple's object.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000c';

do $$
begin
  if exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: outsider C could read another couple''s attachment object';
  end if;
  raise notice 'PASS: outsider C cannot read another couple''s attachment object';
end $$;

-- ------------------------------------------------------------------
-- 4. An outsider (C) cannot insert into the couple's path.
-- ------------------------------------------------------------------
do $$
begin
  insert into storage.objects (bucket_id, name)
  values ('chat-media', '99999999-2000-0000-0000-0000000000c1/msg-2');
  -- If we get here, RLS did NOT block the insert -- that is the failure.
  raise exception 'RLS_DID_NOT_BLOCK';
exception
  when others then
    if sqlerrm = 'RLS_DID_NOT_BLOCK' then
      raise exception 'FAIL: outsider C was able to insert into another couple''s path';
    end if;
    raise notice 'PASS: outsider C cannot insert into another couple''s path (%)', sqlerrm;
end $$;

reset role;

rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run (requires local Supabase running: `supabase start`):

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f supabase/tests/chat_media_storage_test.sql
```

Expected: FAIL on step 1 — `insert into storage.objects ... values ('chat-media', ...)` violates a foreign key or the row is rejected because bucket `chat-media` doesn't exist yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260729000001_chat_media_storage.sql`:

```sql
-- Private Storage bucket for E2E-encrypted chat photo/video attachments.
-- Objects here are opaque AES-256-GCM ciphertext (see AttachmentPayload /
-- attachment_crypto.dart) -- Supabase never holds a decryption key, matching
-- the same "server never sees plaintext" guarantee as message_envelopes.
--
-- Path convention: <couple_id>/<message_id>. RLS reuses the couple
-- membership check already used elsewhere (public.is_couple_member), read
-- off the first path segment via storage.foldername(name).

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

create policy chat_media_select on storage.objects
  for select using (
    bucket_id = 'chat-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy chat_media_insert on storage.objects
  for insert with check (
    bucket_id = 'chat-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );
```

Apply it: `supabase db reset` (local stack) so the new migration runs.

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: 4x `PASS: ...` notices, script exits 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260729000001_chat_media_storage.sql \
        supabase/tests/chat_media_storage_test.sql
git commit -m "feat(chat): add private chat-media Storage bucket with couple-scoped RLS"
```

---

### Task 6: `ChatRepository` upload/download

**Files:**
- Modify: `lib/features/chat/data/chat_repository.dart`
- Test: `test/features/chat/chat_repository_test.dart`

**Interfaces:**
- Consumes: the `chat-media` bucket from Task 5.
- Produces:
  - `ChatRepository.uploadAttachment(String storageKey, Uint8List ciphertext) -> Future<void>`
  - `ChatRepository.downloadAttachment(String storageKey) -> Future<Uint8List>`

This file's existing tests are integration tests against real local Supabase (`@Tags(['integration'])`) — Mocktail cannot mock the Supabase builder chain, per the file's own header comment. The new methods follow the same convention.

- [ ] **Step 1: Write the failing test**

Add to `test/features/chat/chat_repository_test.dart` (add `import 'package:lovinity/features/chat/data/chat_repository.dart';` is already present; no new imports needed), inside `main()` after the existing test:

```dart
  test('uploadAttachment/downloadAttachment round-trips ciphertext via the couple path',
      () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await _pairCouple(clientA, clientB, stamp);
    final coupleId = await clientA.rpc('current_couple') as String;

    final senderRepo = ChatRepository(clientA);
    final recipientRepo = ChatRepository(clientB);
    final storageKey = '$coupleId/attachment-$stamp';
    final ciphertext = Uint8List.fromList(List.generate(64, (i) => i));

    await senderRepo.uploadAttachment(storageKey, ciphertext);
    final downloaded = await recipientRepo.downloadAttachment(storageKey);

    expect(downloaded, ciphertext);
  });

  test('an unrelated user cannot download another couple\'s attachment', () async {
    final clientA = _anonClient();
    final clientB = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await _pairCouple(clientA, clientB, stamp);
    final coupleId = await clientA.rpc('current_couple') as String;

    final senderRepo = ChatRepository(clientA);
    final storageKey = '$coupleId/attachment-outsider-$stamp';
    await senderRepo.uploadAttachment(storageKey, Uint8List.fromList([1, 2, 3]));

    final outsiderClient = _anonClient();
    final outsiderSignUp = await outsiderClient.auth.signUp(
      email: 'chat-outsider-$stamp@test.local',
      password: 'password123',
    );
    addTearDown(() => adminClient.auth.admin.deleteUser(outsiderSignUp.user!.id));
    final outsiderRepo = ChatRepository(outsiderClient);

    await expectLater(
      outsiderRepo.downloadAttachment(storageKey),
      throwsA(anything),
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run (requires `supabase start` and both migrations from Tasks 5 applied via `supabase db reset`):

```bash
flutter test --tags integration test/features/chat/chat_repository_test.dart
```

Expected: FAIL — `uploadAttachment`/`downloadAttachment` undefined on `ChatRepository`.

- [ ] **Step 3: Implement**

In `lib/features/chat/data/chat_repository.dart`, add `import 'dart:typed_data';` at the top, and these methods to the `ChatRepository` class (after `markRead`):

```dart
  static const _attachmentBucket = 'chat-media';

  Future<void> uploadAttachment(String storageKey, Uint8List ciphertext) =>
      _client.storage.from(_attachmentBucket).uploadBinary(storageKey, ciphertext);

  Future<Uint8List> downloadAttachment(String storageKey) =>
      _client.storage.from(_attachmentBucket).download(storageKey);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test --tags integration test/features/chat/chat_repository_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/chat_repository.dart test/features/chat/chat_repository_test.dart
git commit -m "feat(chat): add ChatRepository upload/download for encrypted attachments"
```

---

### Task 7: `MediaCache` seam (local decrypted-file cache)

**Files:**
- Create: `lib/core/storage/media_cache.dart`

**Interfaces:**
- Produces:
  - `abstract class MediaCache { Future<String> write(String key, Uint8List bytes); }`
  - `class FileMediaCache implements MediaCache`

This exists so `ChatService` (Task 8) stays a pure Dart unit with no platform-plugin dependency — the same reasoning as `PushMessaging`/`PushTokenApi` in `lib/core/notifications/push_service.dart`. `FileMediaCache` itself is thin glue over `path_provider`/`dart:io` and is not unit tested directly, same as that file's `_FirebaseMessagingAdapter`/`SupabasePushTokenApi` aren't — only its consumers are tested, against a fake.

- [ ] **Step 1: Implement**

Create `lib/core/storage/media_cache.dart`:

```dart
// lib/core/storage/media_cache.dart
//
// Where decrypted chat-attachment bytes are cached on disk, keyed by chat
// message id. A seam (not called directly as static path_provider/File calls)
// so ChatService's attachment methods stay unit-testable without a real
// Flutter plugin binding -- same reasoning as PushMessaging/PushTokenApi in
// core/notifications/push_service.dart. FileMediaCache itself is thin glue,
// not unit tested directly (same as that file's platform adapters);
// consumers are tested against a fake.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

abstract class MediaCache {
  /// Writes [bytes] to local storage keyed by [key] (the chat message id)
  /// and returns the absolute file path.
  Future<String> write(String key, Uint8List bytes);
}

class FileMediaCache implements MediaCache {
  @override
  Future<String> write(String key, Uint8List bytes) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/chat_media/$key');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/storage/media_cache.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/storage/media_cache.dart
git commit -m "feat(chat): add MediaCache seam for decrypted attachment file caching"
```

---

### Task 8: `ChatService` — send, receive, and download attachments

**Files:**
- Modify: `lib/features/chat/domain/chat_service.dart`
- Modify: `lib/features/chat/domain/chat_providers.dart`
- Modify: `test/features/chat/chat_service_test.dart`
- Modify: `test/integration/chat_e2e_test.dart`

**Interfaces:**
- Consumes: `AttachmentPayload`/`AttachmentKind` (Task 3), `encryptAttachment`/`decryptAttachment` (Task 2), `ChatStore.upsertAttachmentMessage`/`updateDownloadStatus`/`messageById` (Task 4), `ChatRepository.uploadAttachment`/`downloadAttachment` (Task 6), `MediaCache` (Task 7).
- Produces:
  - `ChatService` constructor gains two new **required** named params: `coupleId` (`String`), `cache` (`MediaCache`).
  - `ChatService.sendPhoto({required Uint8List bytes, required String mimeType, required int width, required int height, required Uint8List thumbnailBytes, String? caption, String? replyToMessageId}) -> Future<void>`
  - `ChatService.sendVideo({required Uint8List bytes, required String mimeType, required int durationMs, required Uint8List thumbnailBytes, String? caption, String? replyToMessageId}) -> Future<void>`
  - `ChatService.downloadAttachment(String messageId) -> Future<void>`
  - `_handleInboxRow` gains a `case AttachmentPayload():` arm.

**This is a breaking constructor change.** Every existing `ChatService(...)` call site must be updated in this task or the project will not compile: `lib/features/chat/domain/chat_providers.dart:38`, `test/features/chat/chat_service_test.dart` (4 sites: line 234, 577, 635, 659), `test/integration/chat_e2e_test.dart:88`.

- [ ] **Step 1: Write the failing tests**

In `test/features/chat/chat_service_test.dart`:

Add near the top (after the other imports):

```dart
import 'package:lovinity/core/crypto/attachment_crypto.dart';
import 'package:lovinity/core/storage/media_cache.dart';
```

Add this fake near the other fakes (e.g. after `_FakeChatRepo`):

```dart
class _FakeMediaCache implements MediaCache {
  final Map<String, Uint8List> written = {};

  @override
  Future<String> write(String key, Uint8List bytes) async {
    written[key] = bytes;
    return 'fake-cache/$key';
  }
}
```

Update the four existing `ChatService(...)` construction sites to add the two new required params. The `setUp` block's:

```dart
    chat = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
    );
```

becomes:

```dart
    chat = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      coupleId: 'couple-1',
      cache: _FakeMediaCache(),
    );
```

Apply the same two added lines (`coupleId: 'couple-1', cache: _FakeMediaCache(),`) to the other three `ChatService(...)` construction sites in this file (the ones at what are currently lines 577, 635, 659 — inside the `'serializes inbound processing...'`, `'sendText marks the message failed...'`, and `'a re-delivered reaction envelope...'` tests).

Add new tests at the end of `main()`, before the closing `}`:

```dart
  test('sendPhoto uploads ciphertext, sends an AttachmentPayload envelope, and stores a downloaded local row',
      () async {
    final bytes = Uint8List.fromList(List.generate(200, (i) => i % 256));
    final thumb = Uint8List.fromList([1, 2, 3]);

    await chat.sendPhoto(
      bytes: bytes,
      mimeType: 'image/jpeg',
      width: 800,
      height: 600,
      thumbnailBytes: thumb,
      caption: 'salam',
    );

    expect(repo.sendEnvelopesCalls, hasLength(1));
    final call = repo.sendEnvelopesCalls.single;
    expect(call.messageId, isNotNull);

    final row = await store.messageById(call.messageId!);
    expect(row, isNotNull);
    expect(row!.attachmentKind, 'photo');
    expect(row.mimeType, 'image/jpeg');
    expect(row.width, 800);
    expect(row.height, 600);
    expect(row.body, 'salam');
    expect(row.status, 'sent');
    // The sender already had the plaintext -- it's cached immediately, no
    // download round-trip needed for your own upload.
    expect(row.downloadStatus, 'downloaded');
    expect(row.localMediaPath, 'fake-cache/${call.messageId}');
  });

  test('sendVideo uploads ciphertext and sends an AttachmentPayload envelope with durationMs',
      () async {
    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
    final thumb = Uint8List.fromList([4, 5, 6]);

    await chat.sendVideo(
      bytes: bytes,
      mimeType: 'video/mp4',
      durationMs: 12000,
      thumbnailBytes: thumb,
    );

    final call = repo.sendEnvelopesCalls.single;
    final row = await store.messageById(call.messageId!);
    expect(row!.attachmentKind, 'video');
    expect(row.durationMs, 12000);
    expect(row.mimeType, 'video/mp4');
  });

  test('sendPhoto marks the message failed when upload throws', () async {
    final failingRepo = _FakeChatRepo();
    final db = SignalDb.memory();
    addTearDown(db.close);
    final localStore = ChatStore(db);
    final svc = ChatService(
      session: self1.service,
      repo: failingRepo,
      store: localStore,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      coupleId: 'couple-1',
      cache: _FakeMediaCache(),
    );
    failingRepo.failNextSend = true;

    await svc.sendPhoto(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/jpeg',
      width: 10,
      height: 10,
      thumbnailBytes: Uint8List.fromList([1]),
    );

    final rows = await localStore.watchConversation().first;
    expect(rows.single.status, 'failed');
  });

  test('handleInboxRow on an AttachmentPayload stores a delivered attachment row',
      () async {
    final cache = _FakeMediaCache();
    final svcWithCache = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      coupleId: 'couple-1',
      cache: cache,
    );

    final payload = AttachmentPayload(
      kind: AttachmentKind.photo,
      mimeType: 'image/jpeg',
      sizeBytes: 42,
      width: 100,
      height: 100,
      storageKey: 'couple-1/msg-att-1',
      encKey: Uint8List.fromList(List.filled(32, 5)),
      nonce: Uint8List.fromList(List.filled(12, 6)),
      thumbnailBytes: Uint8List.fromList([7, 7, 7]),
      caption: 'look',
    );
    final copies = await spouse1.service.encryptFor(
      recipientUserId: selfUserId,
      plaintext: encodePayload(payload),
    );
    final toSelf1 = copies.singleWhere((c) => c.userId == selfUserId && c.deviceNum == 1);

    final envelope = <String, dynamic>{
      'id': 'env-att-1',
      'message_id': 'msg-att-1',
      'sender_id': spouseUserId,
      'sender_device_num': 1,
      'recipient_device_num': 1,
      'ciphertext': _hexEnvelope(toSelf1.ciphertext),
      'cipher_type': toSelf1.cipherType,
      'created_at': DateTime.utc(2026, 1, 3).toIso8601String(),
    };

    await svcWithCache.handleInboxRow(envelope);

    final row = await store.messageById('msg-att-1');
    expect(row, isNotNull);
    expect(row!.attachmentKind, 'photo');
    expect(row.storageKey, 'couple-1/msg-att-1');
    expect(row.body, 'look');
    expect(row.status, 'delivered');
    expect(row.downloadStatus, 'none',
        reason: 'attachments are tap-to-load -- never auto-downloaded');
    expect(repo.markDeliveredCalls, contains('msg-att-1'));
  });

  test('downloadAttachment decrypts, caches, and marks the row downloaded', () async {
    final cache = _FakeMediaCache();
    final svcWithCache = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      coupleId: 'couple-1',
      cache: cache,
    );

    final plaintext = Uint8List.fromList([10, 20, 30, 40]);
    final enc = await encryptAttachment(plaintext);
    repo.attachmentBytes['couple-1/msg-dl-1'] = enc.ciphertext;

    await store.upsertAttachmentMessage(
      id: 'msg-dl-1',
      senderId: spouseUserId,
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: plaintext.length,
      storageKey: 'couple-1/msg-dl-1',
      encKey: enc.key,
      nonce: enc.nonce,
      thumbnailBytes: Uint8List.fromList([1]),
      createdAt: DateTime(2026),
      status: 'delivered',
    );

    await svcWithCache.downloadAttachment('msg-dl-1');

    final row = await store.messageById('msg-dl-1');
    expect(row!.downloadStatus, 'downloaded');
    expect(row.localMediaPath, 'fake-cache/msg-dl-1');
    expect(cache.written['msg-dl-1'], plaintext);
  });

  test('downloadAttachment marks the row failed when the repo download throws', () async {
    final cache = _FakeMediaCache();
    final svcWithCache = ChatService(
      session: self1.service,
      repo: repo,
      store: store,
      selfUserId: selfUserId,
      spouseUserId: spouseUserId,
      selfDeviceNum: 1,
      coupleId: 'couple-1',
      cache: cache,
    );

    await store.upsertAttachmentMessage(
      id: 'msg-dl-2',
      senderId: spouseUserId,
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: 4,
      storageKey: 'couple-1/does-not-exist',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: Uint8List.fromList([1]),
      createdAt: DateTime(2026),
      status: 'delivered',
    );

    await svcWithCache.downloadAttachment('msg-dl-2');

    final row = await store.messageById('msg-dl-2');
    expect(row!.downloadStatus, 'failed');
  });
```

`_FakeChatRepo` needs a small addition to support the two new tests above — add to its class body:

```dart
  final Map<String, Uint8List> attachmentBytes = {};
  final List<({String storageKey, Uint8List ciphertext})> uploadAttachmentCalls = [];

  @override
  Future<void> uploadAttachment(String storageKey, Uint8List ciphertext) async {
    uploadAttachmentCalls.add((storageKey: storageKey, ciphertext: ciphertext));
    attachmentBytes[storageKey] = ciphertext;
  }

  @override
  Future<Uint8List> downloadAttachment(String storageKey) async {
    final bytes = attachmentBytes[storageKey];
    if (bytes == null) throw Exception('no such attachment: $storageKey');
    return bytes;
  }
```

Now update `test/integration/chat_e2e_test.dart` so it still compiles. Add near the other fakes (or inline, right above `_makeParty`):

```dart
class _InMemoryMediaCache implements MediaCache {
  final Map<String, Uint8List> written = {};

  @override
  Future<String> write(String key, Uint8List bytes) async {
    written[key] = bytes;
    return 'memory://$key';
  }
}
```

Add `import 'dart:typed_data';` and `import 'package:lovinity/core/storage/media_cache.dart';` to its imports. Change `_makeParty`'s body to fetch the couple id and pass the two new params:

```dart
  p.repo = ChatRepository(client);
  p.store = ChatStore(p.db);
  final coupleId = await client.rpc('current_couple') as String;
  p.chat = ChatService(
    session: p.session,
    repo: p.repo,
    store: p.store,
    selfUserId: userId,
    spouseUserId: spouseId,
    selfDeviceNum: p.deviceNum,
    coupleId: coupleId,
    cache: _InMemoryMediaCache(),
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_service_test.dart`
Expected: FAIL — `coupleId`/`cache` params don't exist on `ChatService`; `sendPhoto`/`sendVideo`/`downloadAttachment` undefined.

- [ ] **Step 3: Implement**

In `lib/features/chat/domain/chat_service.dart`, add imports:

```dart
import 'package:uuid/uuid.dart';
import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/crypto/signal_session_service.dart';
import '../../../core/storage/media_cache.dart';
import '../data/chat_repository.dart';
import '../data/chat_store.dart';
import 'chat_payload.dart';
```

Update the constructor:

```dart
class ChatService {
  ChatService({
    required this.session,
    required this.repo,
    required this.store,
    required this.selfUserId,
    required this.spouseUserId,
    required this.selfDeviceNum,
    required this.coupleId,
    required this.cache,
  });

  final SignalSessionService session;
  final ChatRepository repo;
  final ChatStore store;
  final String selfUserId;
  final String spouseUserId;
  final int selfDeviceNum;
  final String coupleId;
  final MediaCache cache;
```

Add `sendPhoto`, `sendVideo`, and the shared `_sendAttachment` helper (after `sendText`):

```dart
  Future<void> sendPhoto({
    required Uint8List bytes,
    required String mimeType,
    required int width,
    required int height,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
  }) {
    return _sendAttachment(
      kind: AttachmentKind.photo,
      bytes: bytes,
      mimeType: mimeType,
      width: width,
      height: height,
      durationMs: null,
      thumbnailBytes: thumbnailBytes,
      caption: caption,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendVideo({
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
    required Uint8List thumbnailBytes,
    String? caption,
    String? replyToMessageId,
  }) {
    return _sendAttachment(
      kind: AttachmentKind.video,
      bytes: bytes,
      mimeType: mimeType,
      width: null,
      height: null,
      durationMs: durationMs,
      thumbnailBytes: thumbnailBytes,
      caption: caption,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> _sendAttachment({
    required AttachmentKind kind,
    required Uint8List bytes,
    required String mimeType,
    required int? width,
    required int? height,
    required int? durationMs,
    required Uint8List thumbnailBytes,
    required String? caption,
    required String? replyToMessageId,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    try {
      final enc = await encryptAttachment(bytes);
      final storageKey = '$coupleId/$id';

      // The sender already holds the plaintext -- cache it locally right
      // away so opening your own just-sent photo/video never re-downloads
      // it from Storage.
      final localPath = await cache.write(id, bytes);

      await store.upsertAttachmentMessage(
        id: id,
        senderId: selfUserId,
        attachmentKind: kind.name,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        width: width,
        height: height,
        durationMs: durationMs,
        storageKey: storageKey,
        encKey: enc.key,
        nonce: enc.nonce,
        thumbnailBytes: thumbnailBytes,
        caption: caption,
        replyToMessageId: replyToMessageId,
        createdAt: now,
        status: 'sending',
        localMediaPath: localPath,
        downloadStatus: 'downloaded',
      );

      await repo.uploadAttachment(storageKey, enc.ciphertext);

      final payload = AttachmentPayload(
        kind: kind,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        width: width,
        height: height,
        durationMs: durationMs,
        storageKey: storageKey,
        encKey: enc.key,
        nonce: enc.nonce,
        thumbnailBytes: thumbnailBytes,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );
      final copies = await session.encryptFor(
        recipientUserId: spouseUserId,
        plaintext: encodePayload(payload),
      );
      await repo.sendEnvelopes(
          senderDeviceNum: selfDeviceNum, copies: copies, messageId: id);
      await store.setStatus(id, 'sent');
    } catch (_) {
      try {
        await store.setStatus(id, 'failed');
      } catch (_) {
        // The optimistic write itself may have failed; nothing more to do.
      }
    }
  }

  /// Downloads and decrypts the attachment for [messageId] (a local row
  /// previously stored by `_handleInboxRow`'s AttachmentPayload case), caches
  /// the plaintext locally, and updates the row's download state. No-op if
  /// [messageId] isn't a known attachment row.
  Future<void> downloadAttachment(String messageId) async {
    final row = await store.messageById(messageId);
    final storageKey = row?.storageKey;
    final encKey = row?.encKey;
    final nonce = row?.nonce;
    if (storageKey == null || encKey == null || nonce == null) return;

    await store.updateDownloadStatus(id: messageId, status: 'downloading');
    try {
      final ciphertext = await repo.downloadAttachment(storageKey);
      final plaintext =
          await decryptAttachment(ciphertext: ciphertext, key: encKey, nonce: nonce);
      final path = await cache.write(messageId, plaintext);
      await store.updateDownloadStatus(
          id: messageId, status: 'downloaded', localMediaPath: path);
    } catch (_) {
      await store.updateDownloadStatus(id: messageId, status: 'failed');
    }
  }
```

Add the receive-side case to `_handleInboxRow`'s `switch (payload)` (before `case UnsupportedPayload():`):

```dart
      case AttachmentPayload():
        await store.upsertAttachmentMessage(
          id: messageId,
          senderId: senderId,
          attachmentKind: payload.kind.name,
          mimeType: payload.mimeType,
          sizeBytes: payload.sizeBytes,
          width: payload.width,
          height: payload.height,
          durationMs: payload.durationMs,
          storageKey: payload.storageKey,
          encKey: payload.encKey,
          nonce: payload.nonce,
          thumbnailBytes: payload.thumbnailBytes,
          caption: payload.caption,
          replyToMessageId: payload.replyToMessageId,
          createdAt: DateTime.parse(env['created_at'] as String),
          status: senderId == selfUserId ? 'sent' : 'delivered',
        );
        if (senderId != selfUserId) await repo.markDelivered(messageId);
```

Finally, wire the two new required params in `lib/features/chat/domain/chat_providers.dart`'s `chatServiceProvider`:

```dart
  return ChatService(
    session: session,
    repo: ref.read(chatRepositoryProvider),
    store: ref.read(chatStoreProvider),
    selfUserId: selfId,
    spouseUserId: couple.spouseOf(selfId),
    selfDeviceNum: deviceNum,
    coupleId: couple.id,
    cache: FileMediaCache(),
  );
```

Add `import '../../../core/storage/media_cache.dart';` to `chat_providers.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_service_test.dart test/features/chat/chat_providers_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 5: Run the full non-integration suite plus analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/domain/chat_service.dart lib/features/chat/domain/chat_providers.dart \
        test/features/chat/chat_service_test.dart test/integration/chat_e2e_test.dart
git commit -m "feat(chat): ChatService sendPhoto/sendVideo/downloadAttachment + receive handling"
```

---

### Task 9: `MediaPicker` seam (pick + compress + thumbnail)

**Files:**
- Create: `lib/features/chat/presentation/media_picker.dart`
- Modify: `lib/features/chat/domain/chat_providers.dart`

**Interfaces:**
- Consumes: `image_picker`, `flutter_image_compress`, `video_thumbnail`, `video_player` (Task 1).
- Produces:
  - `enum MediaSource { camera, gallery }`
  - `class PickedPhoto { final Uint8List bytes; final String mimeType; final int width; final int height; final Uint8List thumbnailBytes; }`
  - `class PickedVideo { final Uint8List bytes; final String mimeType; final int durationMs; final Uint8List thumbnailBytes; }`
  - `abstract class MediaPicker { Future<PickedPhoto?> pickPhoto(MediaSource source); Future<PickedVideo?> pickVideo(MediaSource source); }`
  - `class DevicePicker implements MediaPicker`
  - `mediaPickerProvider = Provider<MediaPicker>((ref) => DevicePicker())` in `chat_providers.dart`

`DevicePicker` is thin glue over three Flutter plugins and is not unit tested directly (same convention as `FileMediaCache` in Task 7 and the platform adapters in `push_service.dart`) — Task 12's composer widget test exercises the `MediaPicker` *interface* via a fake.

- [ ] **Step 1: Implement**

Create `lib/features/chat/presentation/media_picker.dart`:

```dart
// lib/features/chat/presentation/media_picker.dart
//
// Picks + compresses a photo or video for chat, and generates its embedded
// thumbnail. Lives in the presentation layer (not domain/ChatService) so
// ChatService stays a pure Dart unit with no Flutter-plugin dependency --
// same reasoning as core/notifications/push_service.dart's PushMessaging
// seam. DevicePicker itself is thin glue, not unit tested directly; the
// MediaPicker interface is what composer widget tests fake.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

enum MediaSource { camera, gallery }

class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.thumbnailBytes,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final Uint8List thumbnailBytes;
}

class PickedVideo {
  const PickedVideo({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
    required this.thumbnailBytes,
  });

  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  final Uint8List thumbnailBytes;
}

abstract class MediaPicker {
  /// Returns null if the user cancelled the picker.
  Future<PickedPhoto?> pickPhoto(MediaSource source);

  /// Returns null if the user cancelled the picker. Videos are capped at 60
  /// seconds at the picker level (no client-side re-encode).
  Future<PickedVideo?> pickVideo(MediaSource source);
}

class DevicePicker implements MediaPicker {
  final _picker = ImagePicker();

  @override
  Future<PickedPhoto?> pickPhoto(MediaSource source) async {
    final xfile = await _picker.pickImage(
      source: source == MediaSource.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (xfile == null) return null;

    final compressed = await FlutterImageCompress.compressWithFile(
      xfile.path,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
    );
    if (compressed == null) return null;

    final thumb = await FlutterImageCompress.compressWithFile(
      xfile.path,
      minWidth: 200,
      minHeight: 200,
      quality: 60,
    );
    if (thumb == null) return null;

    final decoded = await _decodeImage(compressed);
    return PickedPhoto(
      bytes: compressed,
      mimeType: 'image/jpeg',
      width: decoded.width,
      height: decoded.height,
      thumbnailBytes: thumb,
    );
  }

  @override
  Future<PickedVideo?> pickVideo(MediaSource source) async {
    final xfile = await _picker.pickVideo(
      source: source == MediaSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();

    final thumbBytes = await video_thumb.VideoThumbnail.thumbnailData(
      video: xfile.path,
      imageFormat: video_thumb.ImageFormat.JPEG,
      maxWidth: 200,
      quality: 60,
    );
    if (thumbBytes == null) return null;

    final controller = VideoPlayerController.file(File(xfile.path));
    await controller.initialize();
    final durationMs = controller.value.duration.inMilliseconds;
    await controller.dispose();

    return PickedVideo(
      bytes: bytes,
      mimeType: 'video/mp4',
      durationMs: durationMs,
      thumbnailBytes: thumbBytes,
    );
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }
}
```

Add the provider to `lib/features/chat/domain/chat_providers.dart` (add `import '../presentation/media_picker.dart';` at the top):

```dart
final mediaPickerProvider = Provider<MediaPicker>((ref) => DevicePicker());
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/chat/presentation/media_picker.dart lib/features/chat/domain/chat_providers.dart
git commit -m "feat(chat): add MediaPicker seam (pick, compress, thumbnail) for photo/video"
```

---

### Task 10: Full-screen photo viewer and video player

**Files:**
- Create: `lib/features/chat/presentation/photo_viewer_screen.dart`
- Create: `lib/features/chat/presentation/video_viewer_screen.dart`
- Test: `test/features/chat/photo_viewer_screen_test.dart` (new)
- Test: `test/features/chat/video_viewer_screen_test.dart` (new)

**Interfaces:**
- Produces: `class PhotoViewerScreen extends StatelessWidget { const PhotoViewerScreen({required String filePath}); }`, `class VideoViewerScreen extends StatefulWidget { const VideoViewerScreen({required String filePath}); }`. `message_bubble.dart` (Task 11) imports both screens created here.

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/photo_viewer_screen_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/photo_viewer_screen.dart';

// A minimal valid 1x1 PNG, so Image.file has real bytes to decode.
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('renders the given file as an Image with an AppBar to dismiss', (tester) async {
    final file = File('${Directory.systemTemp.path}/photo_viewer_test.png');
    await file.writeAsBytes(_onePixelPng);
    addTearDown(() => file.delete());

    await tester.pumpWidget(MaterialApp(home: PhotoViewerScreen(filePath: file.path)));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
```

Create `test/features/chat/video_viewer_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/video_viewer_screen.dart';

void main() {
  testWidgets('shows a loading indicator before the video plugin initializes',
      (tester) async {
    // No real video_player platform implementation is registered in a plain
    // widget test, so initialize() never resolves -- this only asserts the
    // pre-initialization loading state renders without crashing, plus the
    // play/pause FAB and dismiss AppBar are present.
    await tester.pumpWidget(
      const MaterialApp(home: VideoViewerScreen(filePath: '/tmp/does-not-need-to-exist.mp4')),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/photo_viewer_screen_test.dart test/features/chat/video_viewer_screen_test.dart`
Expected: FAIL — neither screen file exists yet.

- [ ] **Step 3: Implement**

Create `lib/features/chat/presentation/photo_viewer_screen.dart`:

```dart
// lib/features/chat/presentation/photo_viewer_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom view of a decrypted, locally-cached chat photo.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(filePath)),
        ),
      ),
    );
  }
}
```

Create `lib/features/chat/presentation/video_viewer_screen.dart`:

```dart
// lib/features/chat/presentation/video_viewer_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen playback of a decrypted, locally-cached chat video.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.filePath});

  final String filePath;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((_) {
      // No platform video implementation available (e.g. a plain widget
      // test) -- stays in the loading state rather than crashing.
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/photo_viewer_screen_test.dart test/features/chat/video_viewer_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/photo_viewer_screen.dart \
        lib/features/chat/presentation/video_viewer_screen.dart \
        test/features/chat/photo_viewer_screen_test.dart \
        test/features/chat/video_viewer_screen_test.dart
git commit -m "feat(chat): add full-screen photo viewer and video player screens"
```

---

### Task 11: `message_bubble.dart` — render attachment states

**Files:**
- Modify: `lib/features/chat/presentation/message_bubble.dart`
- Test: `test/features/chat/message_bubble_test.dart` (new)

**Interfaces:**
- Consumes: `ChatMessageRow.attachmentKind`/`thumbnailBytes`/`downloadStatus`/`localMediaPath` (Task 4), `PhotoViewerScreen`/`VideoViewerScreen` (Task 10).
- Produces: `MessageBubble` gains a new required callback `onDownloadAttachment: ValueChanged<String>` (called with the message id when the user taps an attachment whose `downloadStatus` is `'none'` or `'failed'`).

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/message_bubble_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/presentation/message_bubble.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  late ChatStore store;

  setUp(() {
    db = SignalDb.memory();
    store = ChatStore(db);
  });
  tearDown(() => db.close());

  Future<ChatMessageRow> attachmentRow({
    required String id,
    required String downloadStatus,
    String? localMediaPath,
  }) async {
    await store.upsertAttachmentMessage(
      id: id,
      senderId: 'spouse',
      attachmentKind: 'photo',
      mimeType: 'image/jpeg',
      sizeBytes: 10,
      storageKey: 'c/$id',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 1)),
      thumbnailBytes: Uint8List.fromList(List.filled(3, 9)),
      createdAt: DateTime(2026),
      status: 'delivered',
      downloadStatus: downloadStatus,
      localMediaPath: localMediaPath,
    );
    return (await store.messageById(id))!;
  }

  testWidgets('a not-yet-downloaded attachment shows the thumbnail and taps trigger onDownloadAttachment',
      (tester) async {
    final row = await attachmentRow(id: 'm1', downloadStatus: 'none');
    String? downloaded;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (id) => downloaded = id,
        ),
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();

    expect(downloaded, 'm1');
  });

  testWidgets('a downloading attachment shows a progress indicator and is not tappable to download again',
      (tester) async {
    final row = await attachmentRow(id: 'm2', downloadStatus: 'downloading');
    var downloadCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (_) => downloadCalls++,
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(downloadCalls, 0);
  });

  testWidgets('a failed attachment shows an error icon and tapping retries the download',
      (tester) async {
    final row = await attachmentRow(id: 'm3', downloadStatus: 'failed');
    String? downloaded;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (id) => downloaded = id,
        ),
      ),
    ));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(downloaded, 'm3');
  });

  testWidgets('a downloaded attachment opens a viewer on tap instead of calling onDownloadAttachment',
      (tester) async {
    final row = await attachmentRow(
      id: 'm4',
      downloadStatus: 'downloaded',
      localMediaPath: '/tmp/does-not-need-to-exist-for-this-assertion.jpg',
    );
    var downloadCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: row,
          isOwn: false,
          onReact: (_) {},
          onReply: () {},
          onDownloadAttachment: (_) => downloadCalls++,
        ),
      ),
    ));

    await tester.tap(find.byType(Image).first);
    await tester.pump();

    expect(downloadCalls, 0, reason: 'a downloaded attachment must not re-trigger a download');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/message_bubble_test.dart`
Expected: FAIL — `onDownloadAttachment` is not a recognized named parameter of `MessageBubble`.

- [ ] **Step 3: Implement**

In `lib/features/chat/presentation/message_bubble.dart`, add imports:

```dart
import '../../../core/theme/tokens.dart';
import '../data/chat_store.dart';
import 'photo_viewer_screen.dart';
import 'video_viewer_screen.dart';
```

Update the constructor to accept the new callback:

```dart
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.onReact,
    required this.onReply,
    required this.onDownloadAttachment,
  });

  final ChatMessageRow message;
  final bool isOwn;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;
  final ValueChanged<String> onDownloadAttachment;
```

Replace the body `Text(message.body ?? '', ...)` line inside `build` with a conditional that renders the attachment when present, keeping the optional caption below it:

```dart
              if (message.attachmentKind != null)
                _AttachmentContent(
                  message: message,
                  onDownloadAttachment: onDownloadAttachment,
                ),
              if (message.attachmentKind == null)
                Text(
                  message.body ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                )
              else if (message.body != null && message.body!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LovSpace.xs),
                  child: Text(
                    message.body!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
```

Add the new private widget at the bottom of the file, alongside `_Receipt`:

```dart
/// Renders one attachment message's media area: the embedded thumbnail is
/// always shown (no network needed); tap behavior depends on downloadStatus:
/// 'none'/'failed' triggers [onDownloadAttachment], 'downloading' is inert,
/// 'downloaded' opens a full-screen viewer.
class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({
    required this.message,
    required this.onDownloadAttachment,
  });

  final ChatMessageRow message;
  final ValueChanged<String> onDownloadAttachment;

  static const _size = 220.0;

  @override
  Widget build(BuildContext context) {
    final isVideo = message.attachmentKind == 'video';
    final thumb = message.thumbnailBytes;
    final status = message.downloadStatus;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LovRadius.md),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (thumb != null)
                Image.memory(thumb, fit: BoxFit.cover)
              else
                Container(color: Colors.black12),
              if (isVideo && status != 'downloading')
                const Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
              if (status == 'downloading') const CircularProgressIndicator(),
              if (status == 'failed')
                const Icon(Icons.error_outline, color: LovColors.error, size: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    if (message.downloadStatus == 'downloading') return;
    if (message.downloadStatus == 'downloaded' && message.localMediaPath != null) {
      _openViewer(context, message.localMediaPath!);
      return;
    }
    onDownloadAttachment(message.id);
  }

  void _openViewer(BuildContext context, String path) {
    if (message.attachmentKind == 'video') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => VideoViewerScreen(filePath: path)));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PhotoViewerScreen(filePath: path)));
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/message_bubble_test.dart`
Expected: PASS (all 4 tests).

Also update `test/features/chat/chat_screen_test.dart`'s single `MessageBubble` reference indirectly exercised via `ChatScreen` — it doesn't construct `MessageBubble` directly, so no change needed there; but re-run it to confirm:

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: PASS (this test doesn't build a `MessageBubble` with an attachment row, so the new required param doesn't affect it — but `chat_screen.dart` itself must pass `onDownloadAttachment` at its `MessageBubble(...)` call site, which Task 12 handles; until Task 12, `chat_screen.dart` will not compile with this bubble change in isolation — see the note in Step 5).

- [ ] **Step 5: Note on cross-task compilation**

`chat_screen.dart`'s existing `MessageBubble(...)` call site (in `chat_screen.dart`'s `itemBuilder`) will fail to compile once `onDownloadAttachment` becomes required, until Task 12 adds it. To keep every task's test-run green in isolation, add a minimal wiring in this task's implementation step: in `lib/features/chat/presentation/chat_screen.dart`, add `onDownloadAttachment: (id) => ref.read(chatServiceProvider).value?.downloadAttachment(id),` to the existing `MessageBubble(...)` call (same place `onReact`/`onReply` are already passed). Task 12 then only adds the composer's attach/emoji UI, not this wiring.

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/message_bubble.dart lib/features/chat/presentation/chat_screen.dart \
        test/features/chat/message_bubble_test.dart
git commit -m "feat(chat): render attachment thumbnails, download states, and tap-to-view in bubbles"
```

---

### Task 12: Composer — attach button + bottom sheet, emoji button + panel

**Files:**
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Test: `test/features/chat/chat_screen_test.dart`

**Interfaces:**
- Consumes: `mediaPickerProvider` (Task 9), `ChatService.sendPhoto`/`sendVideo` (Task 8), `emoji_picker_flutter`'s `EmojiPicker` widget (Task 1).
- Produces: `_ChatScreenState` gains `_attachPhoto`/`_attachVideo`/`_showAttachSheet`/`_toggleEmojiPicker`; `_Composer` gains `onAttach`/`onToggleEmoji` callbacks and two new leading `IconButton`s.

- [ ] **Step 1: Write the failing test**

Add to `test/features/chat/chat_screen_test.dart`, replacing its single existing test's `main()` body with the original test plus this new one (add `import 'package:lovinity/features/chat/presentation/media_picker.dart';` and `import 'dart:typed_data';` to the imports):

```dart
class _FakeMediaPicker implements MediaPicker {
  PickedPhoto? nextPhoto;

  @override
  Future<PickedPhoto?> pickPhoto(MediaSource source) async => nextPhoto;

  @override
  Future<PickedVideo?> pickVideo(MediaSource source) async => null;
}

  testWidgets('tapping the attach button shows Camera/Photo Library/Video options',
      (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(_FakeMediaPicker()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tapping the emoji button shows the emoji picker panel', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
        mediaPickerProvider.overrideWithValue(_FakeMediaPicker()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();

    expect(find.byType(EmojiPicker), findsNothing);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();
    expect(find.byType(EmojiPicker), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
```

Add `import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';` to the test file's imports too.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: FAIL — no `Icons.attach_file`/`Icons.emoji_emotions_outlined` buttons exist yet, no `mediaPickerProvider` override point is consumed.

- [ ] **Step 3: Implement**

In `lib/features/chat/presentation/chat_screen.dart`, add imports:

```dart
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../presentation/media_picker.dart';
```

(`media_picker.dart` is already in `presentation/`, so use a relative import: `import 'media_picker.dart';`.)

Add state to `_ChatScreenState`:

```dart
  bool _showEmojiPicker = false;
```

Add these methods to `_ChatScreenState` (near `_send`):

```dart
  Future<void> _attachPhoto(MediaSource source) async {
    final photo = await ref.read(mediaPickerProvider).pickPhoto(source);
    if (photo == null) return;
    final service = ref.read(chatServiceProvider).value;
    if (service == null) return;
    unawaited(service.sendPhoto(
      bytes: photo.bytes,
      mimeType: photo.mimeType,
      width: photo.width,
      height: photo.height,
      thumbnailBytes: photo.thumbnailBytes,
    ));
  }

  Future<void> _attachVideo(MediaSource source) async {
    final video = await ref.read(mediaPickerProvider).pickVideo(source);
    if (video == null) return;
    final service = ref.read(chatServiceProvider).value;
    if (service == null) return;
    unawaited(service.sendVideo(
      bytes: video.bytes,
      mimeType: video.mimeType,
      durationMs: video.durationMs,
      thumbnailBytes: video.thumbnailBytes,
    ));
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _attachPhoto(MediaSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _attachPhoto(MediaSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _attachVideo(MediaSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, emoji);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: start + emoji.length);
  }
```

Add `import 'dart:async';` is already present (used for `unawaited` in `_send`).

In `build()`, add the emoji panel just above `_Composer(...)` in the `Column`'s children:

```dart
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) => _insertEmoji(emoji.emoji),
              ),
            ),
```

Update the `MessageBubble(...)` call (already has `onDownloadAttachment` from Task 11) — no further change needed there.

Update the `_Composer(...)` call to pass the two new callbacks:

```dart
          _Composer(
            controller: _controller,
            enabled: ready,
            onChanged: (_) => typingChannel?.onKeystroke(),
            onSend: () => _send(chatService),
            onAttach: _showAttachSheet,
            onToggleEmoji: _toggleEmojiPicker,
          ),
```

Update the `_Composer` class itself:

```dart
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
    required this.onToggleEmoji,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onToggleEmoji;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LovSpace.lg,
        LovSpace.xs,
        LovSpace.lg,
        LovSpace.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: enabled ? onAttach : null,
            icon: const Icon(Icons.attach_file),
          ),
          IconButton(
            onPressed: enabled ? onToggleEmoji : null,
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: enabled ? 'Message…' : 'Setting up secure chat…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: LovSpace.lg,
                  vertical: LovSpace.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LovRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: LovSpace.sm),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_screen_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 5: Run the full non-integration suite plus analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_screen_test.dart
git commit -m "feat(chat): wire attach button and emoji picker into the composer"
```

---

### Task 13: Final verification pass

**Files:** none (verification only).

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full non-integration test suite**

Run: `flutter test --exclude-tags integration`
Expected: PASS, 0 failures.

- [ ] **Step 3: Full integration suite (requires `supabase start` + `supabase db reset` with both new migrations applied)**

Run: `flutter test --tags integration`
Expected: PASS, 0 failures — including the new `chat_repository_test.dart` attachment tests and the existing `chat_e2e_test.dart` (still exercising text messages end-to-end with the updated `ChatService` constructor).

- [ ] **Step 4: Manual smoke test (per this project's UI-verification convention)**

Run the app on an iOS or Android simulator/device against local Supabase, with two paired accounts (or the existing dev pairing setup). Verify:
- Sending a photo (camera and library) shows a thumbnail bubble immediately, and the recipient receives a push notification and, on tapping the bubble, downloads and views the full photo.
- Sending a video (≤60s) behaves the same, with a play-icon overlay and full-screen playback on tap.
- The emoji picker opens from the composer and inserted emoji appear in the text field.
- A caption typed alongside a picked photo/video renders under the media.
- Killing and reopening the app preserves already-downloaded media (`localMediaPath` persists) without re-downloading.

- [ ] **Step 5: Commit (only if Step 4 surfaced fixes)**

If manual testing found no issues, there is nothing to commit for this task — the feature is complete as of Task 12's commit.
