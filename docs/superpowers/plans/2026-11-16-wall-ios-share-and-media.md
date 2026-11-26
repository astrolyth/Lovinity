# Wall: iOS Share menu + photo/video posts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhone can share links into the Wall like Android, and both platforms can post photos/videos to the Wall.

**Architecture:** A Swift share extension writes shared text to the existing App Group and opens `lovinity://share`; `SceneDelegate` serves it on the existing `lovinity/share` channel, so all Dart after the channel is reused. Media goes to a private `wall-media` Storage bucket (couple-member policies); `feed_items.media_url` holds the storage path; widgets resolve 1-hour signed URLs.

**Tech Stack:** Flutter/Riverpod, Supabase (Postgres + Storage), Swift (Share Extension), `xcodeproj` Ruby gem, existing `image_picker` / `flutter_image_compress` / `get_thumbnail_video` / `video_player`.

**Spec:** `docs/superpowers/specs/2026-11-16-wall-ios-share-and-media-design.md`

## Global Constraints

- App Group: `group.com.lovinity.lovinity`. Channel: `lovinity/share` (`getInitialShare`, `onShare`, payload `{text, subject}`).
- URL scheme: `lovinity`, share URL `lovinity://share`. App Group key: `pending_share`.
- Bucket `wall-media`, private, 50 MiB, mime `image/jpeg`, `video/mp4`, `video/quicktime`.
- Paths: `<couple_id>/<item_id>/media.jpg` | `media.mp4`; video thumbnail `<couple_id>/<item_id>/thumb.jpg`.
- New `source` keys: `photo`, `video`. Videos ≤ 60 s. One medium per post; no link + media.
- Signed URLs live 1 hour. Only the author deletes; files deleted best-effort after the row.
- No new dependencies. No E2E for Wall media. Extension never touches Supabase.

## Review Focus

- A share of text with no URL on iOS → arrives as a note pre-fill (same as Android; covered by existing Dart routing — Task A1 test asserts payload passes through unchanged).
- Upload succeeds, insert fails → uploaded files removed (Task B2 test).
- Outsider (not in couple) requests a signed URL for a couple path → refused (Task B1 SQL test).
- Spouse deletes the other's media file directly → refused (Task B1 SQL test).
- Item with no url, note or media → rejected (Task B1 SQL test).

---

### Task A1: iOS side of the share channel

**Files:**
- Modify: `ios/Runner/Info.plist` (add `CFBundleURLTypes` with scheme `lovinity`)
- Modify: `ios/Runner/SceneDelegate.swift`
- Modify: `lib/core/platform/share_intake.dart` (`_enabled` default: Android **or iOS**)
- Test: `test/core/platform/share_intake_test.dart`

**Interfaces:**
- Produces: App Group `UserDefaults` key `pending_share` = `["text": String, "subject": String?]`, read-and-cleared by `getInitialShare`; `onShare` invoked on `lovinity://share` open.

- [ ] **Step 1: Failing test** `ShareIntake is enabled on iOS`: with `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, a mock channel returning `{'text': 'https://youtu.be/x'}` for `getInitialShare` → `takeInitialShare()` returns payload with that text.
- [ ] **Step 2:** `flutter test test/core/platform/share_intake_test.dart` → FAIL (returns null).
- [ ] **Step 3:** Change `_enabled` default to `!kIsWeb && (android || iOS)`. In `SceneDelegate`: override `scene(_:willConnectTo:options:)` (call super, then register channel on the `FlutterViewController`'s `binaryMessenger`; also handle `connectionOptions.urlContexts`), and `scene(_:openURLContexts:)` → if `url.scheme == "lovinity" && url.host == "share"`, read + clear `pending_share` and `invokeMethod("onShare", payload)`. `getInitialShare` returns + clears `pending_share` (nil when absent).
- [ ] **Step 4:** test PASS; `flutter build ios --simulator --debug --dart-define-from-file=config/supabase.local.json` succeeds.
- [ ] **Step 5:** Commit `feat(wall): receive iOS shares on the lovinity/share channel`.

### Task A2: LovinityShare extension target

**Files:**
- Create: `ios/LovinityShare/ShareViewController.swift`, `ios/LovinityShare/Info.plist`, `ios/LovinityShare/LovinityShare.entitlements`
- Create: `ios/scripts/add_share_extension.rb` (idempotent `xcodeproj` script; run once, kept for reproducibility)
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (via the script)

**Interfaces:**
- Consumes: Task A1 key `pending_share`, URL `lovinity://share`.

- [ ] **Step 1:** `ShareViewController: UIViewController` (`NSExtensionPrincipalClass`, no storyboard). In `viewDidAppear`: load first `public.url` attachment, else `public.plain-text`; if found, write `pending_share` to `UserDefaults(suiteName: "group.com.lovinity.lovinity")`, open `lovinity://share` by walking the responder chain to `UIApplication` and calling `open(_:options:completionHandler:)`; then `extensionContext?.completeRequest`. Nothing found → complete without opening.
- [ ] **Step 2:** Info.plist: `NSExtensionPointIdentifier = com.apple.share-services`, activation rule `NSExtensionActivationSupportsWebURLWithMaxCount = 1`, `NSExtensionActivationSupportsText = true`, display name "Lovinity". Entitlements: App Group above.
- [ ] **Step 3:** Script adds target `LovinityShare` (bundle id `com.lovinity.lovinity.LovinityShare`, deployment target = Runner's, same team/signing settings as Runner), source + Info.plist + entitlements, and an "Embed Foundation Extensions" copy phase in Runner. Run `ruby ios/scripts/add_share_extension.rb`; re-running changes nothing.
- [ ] **Step 4:** `flutter build ios --simulator --debug …` succeeds and `build/ios/iphonesimulator/Runner.app/PlugIns/LovinityShare.appex` exists. Install on the iPhone 17 Pro simulator. Manual: Safari → Share → Lovinity → app opens on the Wall add sheet with the URL (user verifies).
- [ ] **Step 5:** Commit `feat(wall): iOS share extension`.

### Task B1: Database + storage for Wall media

**Files:**
- Create: `supabase/migrations/20261116000002_wall_media.sql`
- Create: `supabase/tests/wall_media_test.sql`

- [ ] **Step 1: Failing SQL test** (psql DO blocks, rolled back, `set role authenticated` + jwt claim): (a) member inserts `source='photo', media_url='<cid>/<id>/media.jpg', media_mime='image/jpeg'` with no url/note → succeeds; (b) row with no url, note or media → `check_violation`; (c) member inserts `storage.objects(bucket_id='wall-media', name='<cid>/x/media.jpg')` → ok; outsider insert/select on that path → denied/0 rows; (d) spouse deletes the other's object → 0 rows deleted.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Migration: replace `feed_items_source_check` (add `photo`,`video`) and `feed_items_has_content` (`url is not null or (note is not null and length(btrim(note))>0) or media_url is not null`); add `media_mime` check (`null` or in the 3 mimes); bucket insert with limits from Global Constraints; policies `wall_media_select`/`wall_media_insert` on `is_couple_member((storage.foldername(name))[1]::uuid)`, `wall_media_delete` with `owner = auth.uid()` too.
- [ ] **Step 4:** apply to local DB; test PASS; `our_wall_test.sql` still PASS.
- [ ] **Step 5:** Commit `feat(wall): media columns and wall-media bucket`.

### Task B2: Model + repository

**Files:**
- Modify: `lib/features/wall/domain/wall_models.dart`, `lib/features/wall/data/wall_repository.dart`
- Test: `test/features/wall/wall_repository_test.dart` (integration, existing pattern), `test/features/wall/wall_models_test.dart`

**Interfaces:**
- Produces:
  - `WallSource.photo('Photo')`, `WallSource.video('Video', isVideo: true)`
  - `WallItem.mediaPath: String?`, `WallItem.mediaMime: String?`, `bool get hasMedia`, `String? get thumbPath` (video → `<dir>/thumb.jpg`; photo → `mediaPath`)
  - `Future<WallItem> WallRepository.addMediaItem({required String coupleId, required String userId, required Uint8List bytes, required String mimeType, Uint8List? thumbnailBytes, WallCollection? collection, String? note})`
  - `Future<String> WallRepository.signedUrl(String path)` (3600 s)
  - `deleteItem(WallItem item)` (was `String itemId`): deletes the row, then media + thumb best-effort.

- [ ] **Step 1: Failing tests:** model — `fromRow` with `source:'video', media_url:'c/i/media.mp4'` → `thumbPath == 'c/i/thumb.jpg'`; photo → `thumbPath == mediaPath`. Repository — `addMediaItem` uploads, returns item with `hasMedia`, `signedUrl(item.thumbPath!)` downloads non-empty bytes over HTTP; a spouse `signedUrl` works, an outsider's fails; insert failure (pass an unknown `coupleId`) leaves no object under that path; `deleteItem` removes row and objects.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement; item id from `Uuid().v4()`; extension from mime (`jpg` / `mp4`); upload with `upsert: false`; on insert error remove uploaded paths then rethrow. Update all `deleteItem` callers (`grep -rn deleteItem lib test`).
- [ ] **Step 4:** `flutter test --concurrency=1 test/features/wall` PASS.
- [ ] **Step 5:** Commit `feat(wall): media items in the repository`.

### Task B3: Showing media

**Files:**
- Create: `lib/features/wall/presentation/wall_item_thumbnail.dart`
- Modify: `wall_item_card.dart`, `wall_pinned_row.dart`, `wall_home_tile.dart`, `wall_item_screen.dart`, `wall_providers.dart`
- Test: `test/features/wall/wall_widgets_test.dart`

**Interfaces:**
- Produces: `wallSignedUrlProvider = FutureProvider.family<String, String>` (path → URL; `keepAlive` closed after 50 min); `WallItemThumbnail({required WallItem item, double? height, double borderRadius, bool showSourcePill})` — media items use `wallSignedUrlProvider(item.thumbPath!)`, others `item.imageUrl`; both render `WallThumbnail`.

- [ ] **Step 1: Failing widget tests:** a video item card shows "Video" pill + play glyph and requests `thumb.jpg` (override provider to record paths); a photo card requests `media.jpg`; tapping a media card's preview opens detail (no `launchUrl`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Replace the four `WallThumbnail(... imageUrl: item.imageUrl ...)` sites with `WallItemThumbnail`. Detail: photo → `InteractiveViewer` over `Image.network(signed media)`; video → `VideoPlayerController.networkUrl(signed media)` with tap-to-play/pause, error → "Can't play this video". "Open in …" button hidden when `hasMedia`.
- [ ] **Step 4:** wall widget tests PASS; analyzer clean.
- [ ] **Step 5:** Commit `feat(wall): show photo and video posts`.

### Task B4: Posting media

**Files:**
- Modify: `lib/features/chat/presentation/media_picker.dart` (`pickVideo(MediaSource source, {int thumbnailMaxWidth = 200})`)
- Modify: `lib/features/wall/presentation/add_to_wall_sheet.dart`, `wall_providers.dart` (post action)
- Test: `test/features/wall/add_to_wall_sheet_test.dart`

**Interfaces:**
- Consumes: `mediaPickerProvider`, `WallRepository.addMediaItem`.

- [ ] **Step 1: Failing tests:** with a fake `MediaPicker` returning a `PickedPhoto`, tapping "Photo / Video" → library shows the picked preview, hides the link field, enables "Share with …"; posting calls `addMediaItem` with `mimeType: 'image/jpeg'`; a failing `addMediaItem` keeps the sheet open with the inline error + Retry; video posts pass `thumbnailBytes`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Add the media row (camera/library choice via the existing chat bottom-sheet pattern); Wall calls `pickVideo(source, thumbnailMaxWidth: 800)`; photo posts pass no thumbnail. Chat call sites unchanged (default 200).
- [ ] **Step 4:** wall + chat tests PASS.
- [ ] **Step 5:** Commit `feat(wall): post photos and videos`.

### Task B5: Device verification

**Files:**
- Modify: `integration_test/app_smoke_test.dart`

- [ ] **Step 1:** Extend the smoke test: before sign-in, the spouse posts a photo via `WallRepository.addMediaItem` (small generated JPEG); after reaching home, open `/home/wall` (tap the Wall home tile) and wait for the "Photo" pill.
- [ ] **Step 2:** Run on iPhone 17 Pro simulator and macOS: PASS. Run on an Android emulator if one is available; otherwise report it as not run.
- [ ] **Step 3:** Full `flutter test --concurrency=1` PASS, analyzer 0 errors/warnings, SQL tests PASS.
- [ ] **Step 4:** Commit `test(wall): on-device check of media posts`.
