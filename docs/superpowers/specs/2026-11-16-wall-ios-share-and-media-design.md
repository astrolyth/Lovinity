# Our Wall — iOS Share menu + photo/video posts

Extends `2026-10-08-our-wall-design.md`. Two independent pieces, built in
this order: (A) iOS share extension, (B) photo/video posts.

## Why

The Wall is meant to be the one private place a couple keeps what they would
otherwise DM each other. Today only Android can share into it from other apps,
and only links and notes can be posted. The user wants the same experience on
iPhone and Android, and photos/videos alongside links.

## Goals

- iPhone: sharing a link (or text containing one) from Instagram, YouTube,
  TikTok, Safari, etc. opens Lovinity on the Wall with the add sheet
  pre-filled — the same result Android gives today.
- Both platforms: post a photo or a short video to the Wall from the camera
  or library, with an optional note and collection.
- The spouse sees photo/video posts live, gets the existing "shared
  something" push, and can react, comment and pin them like any item.

## Non-goals

- Sharing photos/videos *from other apps* into the Wall (share menu stays
  text/links on both platforms). Media comes from the in-app picker.
- End-to-end encryption for Wall media. **Decided by the user:** same rule as
  the rest of the Wall — private, couple-only, server-readable.
- Multiple photos per post, editing a post, a media gallery view.

## Anti-goals

- The share extension must not hold the user's session or talk to Supabase.
  It only hands text to the app.
- A Wall photo must never be readable by anyone outside the couple, including
  through a guessable storage path.

## Constraints (from the project)

- Text arrives in Dart through `lib/core/platform/share_intake.dart` on the
  `lovinity/share` MethodChannel (`getInitialShare` pull + `onShare` push).
  Android implements it in `MainActivity.kt`; app routing, sign-in/pairing
  checks and pre-filling the sheet already exist (`wall_share_routing.dart`).
- App Group `group.com.lovinity.lovinity` is already in
  `ios/Runner/Runner.entitlements`.
- No extension target exists in `ios/Runner.xcodeproj` yet (the
  `ios/LovinityWidget` sources are not part of the project — separate issue,
  not fixed here).
- `feed_items` already has `media_url` / `media_mime`; constraints currently
  require `url or note` and limit `source` to youtube/instagram/tiktok/
  article/note.
- Chat already picks, compresses and thumbnails media in
  `lib/features/chat/presentation/media_picker.dart` (photo 1600px q80,
  video ≤ 60 s, thumbnail via `get_thumbnail_video`).

## Approaches

**A. iOS share extension**

1. *Extension hands text to the app* (chosen): the extension reads the shared
   URL/text, saves it to the App Group, opens `lovinity://share`, and closes.
   The app reads it over the existing channel. Same flow and Dart code as
   Android; no auth in the extension.
2. *Extension posts directly*: its own compose UI posts to Supabase. Needs the
   session shared through keychain groups and a second UI to maintain; rejected
   (anti-goal).
3. *Third-party package* (`receive_sharing_intent`): does approach 1 for us,
   but the original Wall decision was a hand-written bridge with no package;
   rejected for consistency.

**B. Photo/video storage**

1. *Private Storage bucket `wall-media` with couple-member policies*
   (chosen; user picked "same rule as the Wall"). Shown through short-lived
   signed URLs.
2. *E2E-encrypted like chat attachments*: rejected by the user.

## Design — A. iOS share extension (my calls, correct me)

- New Xcode target **LovinityShare** (Share Extension, Swift, no storyboard
  UI), added to `ios/Runner.xcodeproj` with the `xcodeproj` Ruby gem
  (installed with CocoaPods) and embedded in Runner. Same App Group
  entitlement as Runner.
- Activation rule: web URLs and plain text (`NSExtensionActivationSupportsWebURLWithMaxCount = 1`,
  `NSExtensionActivationSupportsText`).
- On activation: take the first URL attachment, else the text attachment;
  write `{text, subject}` to `UserDefaults(suiteName: group…)` under
  `pending_share`; open `lovinity://share` through the responder chain; finish
  the request. Nothing saved if there is no text.
- Runner `Info.plist`: register URL scheme `lovinity`.
- `SceneDelegate.swift`: register the `lovinity/share` channel.
  `getInitialShare` returns and clears `pending_share`; on
  `scene(_:openURLContexts:)` for `lovinity://share`, read + clear it and call
  `onShare`. Same contract as `MainActivity.kt`.
- Dart: enable `ShareIntake` on iOS as well as Android (one condition change).
  Everything after the channel is unchanged.

## Design — B. Photo/video posts (my calls, correct me)

**Database (one migration)**
- `feed_items.source` also allows `photo`, `video`.
- `feed_items_has_content`: `url`, non-blank `note`, **or** `media_url`.
- `media_url` holds the storage path (not a URL); `media_mime` the type.
- Private bucket `wall-media` (`public = false`, 50 MiB limit, image/jpeg,
  video/mp4, video/quicktime). Paths: `<couple_id>/<item_id>/media.<ext>` and
  `<couple_id>/<item_id>/thumb.jpg`.
- Storage policies: read and upload when the first path segment is a couple
  the user belongs to (`is_couple_member`, same as `chat-media`); delete only
  own uploads (`owner = auth.uid()`).
- `feed_items_guard_update` already blocks changing `media_url`/`media_mime`.

**Posting**
- Add sheet gets a "Photo / Video" row (camera or library, via the chat
  `MediaPicker`). The video thumbnail is requested at card size (~800px)
  instead of chat's 200px.
- Order: generate `item_id` → upload media + thumbnail → insert the row with
  that id. If the insert fails, delete the uploaded files. The spouse never
  sees a row whose media is missing.
- Note and collection work as today; a link and media can't be combined in
  one post (the media replaces the link field).

**Showing**
- Repository resolves signed URLs (1 hour) for `thumb.jpg` and `media`;
  cached in memory per item for that hour.
- Story card: thumbnail as the preview, source pill "Photo"/"Video", play
  glyph for video. Tap preview → item detail (no external link).
- Item detail: full photo (pinch to zoom with `InteractiveViewer`) or video
  with `video_player` (play/pause, tap to show controls).

**Deleting**
- Author deletes the row, then the two files (best effort).
  `shortcut: a failed file delete leaves an orphan in storage; add a cleanup
  job if storage cost matters.`

## Error handling

| Situation | Behaviour |
|---|---|
| Share extension gets nothing usable | Closes without opening the app. |
| App opened from share while signed out/unpaired | Dropped, as on Android today. |
| Upload fails | Sheet stays open, inline error + Retry; nothing posted. |
| Signed URL fails / expired | Branded placeholder, refreshed on next load. |
| Video won't play | Placeholder with "Can't play this video". |

## Testing

- Dart unit: `SharedPayload` parsing unchanged; ShareIntake enabled on iOS.
- SQL: photo/video sources accepted; media-only item accepted; item with
  nothing still rejected; storage policies — couple member reads, outsider
  can't, spouse can't delete the other's file.
- Repository integration (local Supabase): upload → insert → signed URL →
  delete round trip; failed insert removes uploaded files.
- Widget: photo and video cards, add sheet media state.
- Device: iOS share extension built and run on the iPhone 17 Pro simulator;
  the share flow itself is checked by hand (Safari → Share → Lovinity), since
  the simulator's share sheet can't be driven from tests. Android emulator
  run of photo posting.

## Left to the builder

Exact widget layout inside the existing card/detail patterns; signed-URL
cache shape; whether the extension uses `NSExtensionPrincipalClass` or a
minimal storyboard (no UI either way).
