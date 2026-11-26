# Our Wall — shared feed + Android share-sheet

## Summary

A private, two-person feed where a couple drops the reels, YouTube videos,
TikToks, articles and short notes they would otherwise DM each other across
five apps. Either spouse can react, comment, pin and file items into
collections; the other sees it appear live and gets a push. On Android the app
is a Share-menu target, so sharing a reel from Instagram lands straight in the
"Add to our Wall" sheet.

Product source: `Sakinah_Product_Technical_Plan.docx` → Pillar D "Shared feed
('Our Wall')", MVP must-have "Shared feed 'Our Wall' + OS share-sheet".

## Success criteria

- Sharing a link from Instagram/YouTube/Chrome on Android reaches a posted Wall
  item in 2–3 taps.
- The spouse sees the new item appear live (no refresh) and receives a push.
- Reactions and comments sync live between the two phones.
- The Wall reads as a polished, modern part of Lovinity (dark-first black +
  gold, existing type and motion), not a bolted-on list.
- Nobody outside the couple can read anything; nobody can post as, or delete
  the content of, their spouse.

## Decisions (agreed)

1. **Privacy: RLS-protected, server-readable** (same model as prayer logs),
   not end-to-end encrypted. History survives reinstalls/new phones; previews
   are simple. The app must not imply the Wall is E2E like chat.
2. **Layout: "story cards"** — one item per row with a large preview and the
   sharer's note as a gold-ruled quote — with a **horizontal pinned row on top**
   (layout A + C's pinned row, chosen from mockups).
3. **Link previews are fetched on the sharing phone**, not by a server
   function: no deploy, and no server-side "fetch any URL" (SSRF) surface.
4. **Android share intake is a small hand-written bridge** (manifest
   intent-filter + Kotlin MethodChannel), no third-party package.
5. **Clipboard is never read silently.** If the clipboard has text, the add
   sheet shows a "Paste copied link" pill; one tap reads and fills it. Avoids
   the iOS paste banner and Android 13+ clipboard toast.
6. **Push on new items and new comments only**, never on reactions. Fixed
   copy, no item content in the notification.

## Screens and UX

### 1. Feed — `/home/wall`
- Header: "Our Wall" + "N things shared this week" + both spouses' avatars.
- **Pinned row**: horizontal cards for pinned items (title, collection,
  sharer), shown only when something is pinned.
- **Collection chips**: All · Recipes · Places · Home · Funny · Deen. Single
  select; filters the feed (pinned row is not filtered).
- **Story cards**, newest first:
  - preview image (or branded placeholder) with a source pill (YouTube,
    Instagram, TikTok, Article, Note) and a play glyph for video sources;
  - title + domain;
  - the sharer's note as a quote with a gold left rule;
  - footer: sharer + relative time; reaction summary chips (own reactions
    outlined gold) and comment count.
  - Tap the **preview** → open the link externally (its native app when
    installed). Tap **anywhere else** → item detail.
  - Note-only items render as a text card (no preview area).
  - A small gold dot marks spouse items newer than the user's last visit to
    the Wall. The last-visit timestamp is stored on-device in secure storage
    under `wall.last_visit.<user id>` (already a dependency; per account, so
    accounts sharing a device don't mix). It updates when the feed is left.
- **+ button** (gold, bottom-right) → add sheet.
- **Empty state**: short warm prompt ("Share your first find") + button that
  opens the add sheet.
- **Loading**: shimmer skeletons shaped like story cards (`LovShimmerBox`).

### 2. Add sheet (modal bottom sheet)
- Link field; when the clipboard has text, a "Paste copied link" pill.
- When a link is present: compact preview row (thumbnail, title, domain) that
  fills in as the preview loads (shimmer while loading).
- Optional note field.
- Optional collection chips (single select, deselectable).
- Primary button "Share with <spouse name>"; disabled until there is a link or
  a note. With no link, the item posts as a note.
- Opened pre-filled when content arrives from the Android Share menu.

### 3. Item detail — `/home/wall/:id`
- Large preview (hero transition from the feed card), title, domain, "shared
  by X · time", note quote.
- "Open in <Source> ↗" button.
- Reaction bar: 🤍 😂 🔥 🤲 😮 ⭐ — each emoji toggles independently, so one
  person may leave several different reactions on an item (matches the
  existing `(item_id, user_id, reaction)` primary key). Optimistic, with a
  scale bounce + light haptic.
- Comment thread (own comments right-aligned on accent-soft bubbles, spouse's
  left), with a reply composer pinned to the bottom.
- App-bar actions: pin/unpin toggle; ⋯ menu → change collection, delete
  (author only, with confirmation).

### 4. Home tile — "Latest on our Wall"
- New card on the home screen directly after `ScoreboardCard`: latest item's
  thumbnail/title, sharer and time, plus the unseen-items dot. Empty state
  invites the first share. Tap → `/home/wall`.

### Motion and polish
- Feed cards enter with the existing `LovStagger` / `LovEnter` motion;
  live-arriving items slide in.
- Card → detail uses a `Hero` on the preview.
- Reactions respond instantly (optimistic) with a short scale bounce and
  `HapticFeedback.lightImpact`.
- Dark and light themes both supported through existing `LovColors` tokens;
  placeholders use a source-tinted gradient so failed images still look
  intentional.

## Architecture

New feature folder `lib/features/wall/`, following the existing
`data / domain / presentation` split.

| Unit | Responsibility |
|---|---|
| `data/wall_repository.dart` | Supabase access: realtime streams of items, reactions and comments for a couple; add item, delete item, set pinned, set collection, toggle reaction, add/delete comment. |
| `data/link_preview_service.dart` | Fetches a URL (5 s timeout, size cap, http/https only) and returns `LinkPreview{title, imageUrl, siteName}`. YouTube and TikTok use their public oEmbed endpoints; everything else parses Open Graph / Twitter-card / `<title>` tags. Parsing is a pure function over HTML/JSON for unit testing. |
| `domain/link_detect.dart` | Pure helpers: extract the first http(s) URL from arbitrary shared text; classify source (`youtube`, `instagram`, `tiktok`, `article`, `note`) from the host. |
| `domain/wall_models.dart` | `WallItem`, `WallReaction`, `WallComment`, `WallCollection` (enum mapped to the DB strings). |
| `domain/wall_providers.dart` | Feed stream for the current couple, selected-collection filter, pinned items, per-item reaction summary and comment count, last-visit tracking. |
| `presentation/` | `wall_screen.dart`, `wall_item_card.dart`, `wall_pinned_row.dart`, `add_to_wall_sheet.dart`, `wall_item_screen.dart`, `wall_reaction_bar.dart`, `wall_home_tile.dart`. |
| `lib/core/platform/share_intake.dart` | Listens on a MethodChannel for text shared into the app (cold start + while running) and exposes it as a stream; the app shell routes it to `/home/wall` with the add sheet open and pre-filled. |

**Routing** (`lib/core/router/app_router.dart`): add `wall` and `wall/:id`
under `/home`. `routeForTap` in `lib/app.dart` maps notification type `wall`
→ `/home/wall`.

**New dependencies** (added via `flutter pub add`, latest versions):
`url_launcher`, `cached_network_image`, `html`.

### Data flow — posting a link
1. User pastes/receives a link → `link_detect` extracts and classifies it.
2. `link_preview_service` fetches the preview on-device (≤ 5 s).
3. On "Share", `wall_repository.addItem` inserts into `feed_items` with
   `couple_id`, `added_by`, `url`, `title`, `description`, `image_url`,
   `source`, `collection`, `note`.
4. The DB insert trigger calls `dispatch_push(spouse, 'wall', …)`.
5. Both phones' realtime streams emit the new row; the feed updates.

## Database (one new migration)

Tables `feed_items`, `feed_reactions`, `feed_comments` already exist
(`20260712000002_full_schema.sql`), with a blanket couple-member RLS policy
(`<table>_couple_rls`, `for all`) and realtime publication.

The migration:

1. **Replaces the blanket policies with per-operation policies**:

   | Table | select | insert | update | delete |
   |---|---|---|---|---|
   | `feed_items` | couple member | couple member **and** `added_by = auth.uid()` | couple member (pin/collection by either spouse) | `added_by = auth.uid()` |
   | `feed_comments` | couple member | couple member **and** `author_id = auth.uid()` | — (no edits) | `author_id = auth.uid()` |
   | `feed_reactions` | couple member | couple member **and** `user_id = auth.uid()` | — | `user_id = auth.uid()` |

   `feed_items` updates must not change `added_by`, `couple_id`, `url` or
   `created_at` — enforced with a `before update` trigger that raises if any
   of those columns change (RLS can't compare old vs new).

2. **Adds check constraints**:
   - `feed_items.url` is null or matches `^https?://`, length ≤ 2048;
   - `feed_items.source` ∈ {`youtube`, `instagram`, `tiktok`, `article`,
     `note`} (null allowed);
   - `feed_items.collection` ∈ {`recipes`, `places`, `home`, `funny`, `deen`}
     (null allowed);
   - `feed_items.note` length ≤ 1000; `title` ≤ 300; `description` ≤ 1000;
   - `url is not null or note is not null` (an item has a link or a note);
   - `feed_comments.body` length 1–1000;
   - `feed_reactions.reaction` ∈ {`heart`, `laugh`, `fire`, `dua`, `wow`,
     `star`} (stored as keys; the UI maps them to 🤍 😂 🔥 🤲 😮 ⭐).
   - The migration first removes/normalises any existing rows that would
     violate a new constraint, so it applies cleanly to Cloud.

3. **Adds push triggers** (security definer, best-effort via the existing
   `dispatch_push`, which never raises):
   - `after insert on feed_items` → push the spouse of `added_by`:
     title `"<display_name> shared something"`, body
     `"New on your Wall 💛"`.
   - `after insert on feed_comments` → push the spouse of `author_id`:
     title `"<display_name> replied"`, body `"New comment on your Wall"`.
   - Spouse is resolved from `couples` (`member_a`/`member_b`) for the row's
     `couple_id`; `display_name` from `public.users`, falling back to
     "Your partner" when empty.

## Push function

`supabase/functions/push-dispatch/logic.ts`: add `"wall"` to
`ALLOWED_TYPES` and update the type error message; add a test that `wall` is
accepted and an unknown type is still rejected. Requires redeploying the
function (`supabase functions deploy push-dispatch`) — documented in the
README alongside the existing push setup.

## Android share-sheet

- `android/app/src/main/AndroidManifest.xml`: an `intent-filter` on
  `MainActivity` for `android.intent.action.SEND` with `text/plain`.
- `MainActivity.kt`: on `onCreate` and `onNewIntent`, read
  `Intent.EXTRA_TEXT` (and `EXTRA_SUBJECT` as an optional title hint) from
  `ACTION_SEND` intents and deliver it over a `MethodChannel`
  (`lovinity/share`). Cold-start text is held until Dart asks for it
  (`getInitialShare`); later shares are pushed (`onShare`).
- Dart `share_intake.dart` exposes the stream; the app shell waits until the
  user is signed in and paired, then navigates to `/home/wall` with the add
  sheet open and pre-filled. If the user is signed out or unpaired, the
  shared text is ignored (it is not held across sign-in).
- Image/video shares are out of scope (text/links only).

## Error handling

| Situation | Behaviour |
|---|---|
| Preview fetch fails / times out (5 s) | Item still posts with `title` = domain, no image; card shows the branded placeholder. |
| Thumbnail URL later fails (e.g. expired Instagram CDN link) | `cached_network_image` error builder → branded placeholder. |
| Shared text has no URL | Pre-fills the note field instead. |
| Insert fails (offline/server) | Sheet stays open with the user's input; inline error + Retry. No offline queue in v1. |
| Reaction toggle fails | Optimistic state rolls back; small snackbar. |
| Delete | Confirmation dialog; shown only for the author's own items/comments. |
| Push misconfigured | `dispatch_push` is already best-effort; posting is never blocked. |

## Testing

- **Unit**: `link_detect` (URL extraction from mixed text, trailing
  punctuation, multiple URLs, no URL, host → source classification incl.
  `youtu.be`, `m.youtube.com`, `vm.tiktok.com`); preview parsing against saved
  fixtures (YouTube oEmbed JSON, TikTok oEmbed JSON, an article with OG tags,
  a page with only `<title>`, a page with nothing); reaction key ↔ emoji
  mapping.
- **Repository / RLS integration** (local Supabase, existing pattern):
  add/list/pin/collection/react/comment round-trip; spouse **cannot** delete
  the other's item or comment; nobody can insert with another user's
  `added_by`/`author_id`/`user_id`; a non-member cannot read the couple's
  rows; constraint violations are rejected; the update guard blocks changing
  `added_by`/`url`.
- **Widget**: story card variants (preview, placeholder, note-only, own vs
  spouse reaction styling), collection chip filtering, pinned row visibility,
  add-sheet states (empty → link → preview loading → ready; note-only enables
  the button), reaction toggle optimistic update, empty state.
- **Push function**: `wall` type accepted; unknown type rejected.
- **App routing**: `routeForTap(NotificationTap(type: 'wall'))` →
  `/home/wall`.

## Out of scope (this version)

iOS share extension; image/video uploads to the Wall; memory timeline / "on
this day"; "watch later, together" queue; search; editing an item's note or
link after posting (delete and re-post instead); per-item push deep link (taps
open the feed); offline posting queue.
