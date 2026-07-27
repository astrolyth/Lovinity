# Sakīnah — Floating Chat Button + Unread Badge

**Date:** 2026-07-19
**Status:** Design approved
**Builds on:** E2E text chat (sub-project 2)

## Summary

Replace the home-screen chat *card* with a **floating chat button** (bottom-right, Messenger-style) carrying an **unread-message count badge**. Doing so also wires up the missing **read receipts**: opening the chat marks incoming messages read, which clears the badge and flips the spouse's messages to the "read" tick.

## Why read receipts come along for the ride

`ChatRepository.markRead` exists but **has no caller** — nothing marks an incoming message as read, so the sender's "read" tick never fires and there's no notion of "unread" to count. The badge needs both, so this change adds the mark-read-on-open step that completes the receipt loop designed in sub-project 2.

## Decisions (agreed)

1. A message counts as **read when the chat screen is opened** (not per-visible-bubble). Clears the badge and sends the read receipt.
2. Badge count comes from the **local store** (instant, offline-capable).
3. Badge caps display at **"99+"**; the **button is always visible** on home (the badge only appears when count > 0).

## Components

### 1. `ChatStore.watchUnreadCount(String selfUserId) → Stream<int>`

A Drift count-stream of `chat_messages` where `sender_id != selfUserId` **and** `read_at is null` (incoming messages not yet read). Incoming messages are stored by `handleInboxRow` with `readAt = null`, so this is the unread set.

### 2. `unreadChatCountProvider` (`StreamProvider<int>`)

Watches `chatStoreProvider.watchUnreadCount(selfUserId)` for the signed-in user; emits `0` when signed out.

### 3. `ChatService.markConversationRead()`

Marks every local incoming unread message read:
- **Local:** set `readAt = now` on those rows (via a `ChatStore.markIncomingRead(selfUserId)` helper) so `watchUnreadCount` drops to 0.
- **Server:** call `repo.markRead(messageId)` for each, so the spouse's receipt pump flips their sent message to `read`. Best-effort — a failed server call does not block the local badge clearing (retried the next time the chat is opened).

Called from `ChatScreen` when it mounts (once the service is ready).

### 4. Home floating button

- Remove `_ChatTile` (and its class) from the home scroll column.
- Pass a `floatingActionButton` to home's `SakScaffold` (already supported; default bottom-right position).
- The button: a `FloatingActionButton` with `Icons.chat_bubble` (filled), wrapped in Material 3's `Badge` (`Badge.count` / `label`) showing `unreadChatCountProvider`. Badge hidden when count == 0; label is `count > 99 ? '99+' : '$count'`. Tap → `context.go('/home/chat')`.

## Data flow

Incoming message → `handleInboxRow` stores it (`readAt` null) → `watchUnreadCount` emits +1 → the home badge updates live. User taps the button → chat opens → `markConversationRead` → local `readAt` set (badge → 0) + server `markRead` per message → spouse's receipt pump shows "read".

## Error handling

- Server `markRead` failures are swallowed per-message (local read state still applies; badge clears). No crash, no blocking.
- `watchUnreadCount` with no signed-in user / empty store emits `0`.
- `AppFailure` pattern unchanged.

## Testing

- **Store:** `watchUnreadCount` counts only incoming (`sender_id != self`) unread rows; drops to 0 after `markIncomingRead`; own sent messages never counted.
- **Service:** `markConversationRead` sets local `readAt` on incoming unread messages and calls `repo.markRead` once per such message (not for already-read or own messages).
- **Widget (home):** the floating button renders; the badge shows the count and is hidden at 0; capped at "99+".

## Out of scope

- Push notifications (its own next sub-project — with the E2E constraint that message text can't ride in the push payload).
- Per-message "seen" precision / scroll-into-view read tracking.
- Unread indicators anywhere other than the home floating button.
