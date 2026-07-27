# Phased push-notification system

Push notifications to **both** partners' devices when the other sends a chat
message (phase 1) or a couple-level update occurs (phase 2), built on the
existing E2E-encrypted chat + Supabase backend. Transport: **Firebase Cloud
Messaging (FCM)** — the free, standard cross-platform push channel for Flutter.

## Global Constraints (bind every task)

1. **E2E integrity — no plaintext ever leaves the device.** The server cannot
   read message content (Signal E2E). No push payload, DB column, edge-function
   log, or notification body may contain decrypted message text. Notifications
   are **content-free**: only a fixed category hint (`message`, `reaction`,
   `pairing`) chosen by the client is allowed to influence copy
   ("New message from your partner"). The hint is metadata, not plaintext.
2. **Graceful degradation — the app and chat must work with NO push config.**
   `flutter build`/`flutter analyze`/`flutter test` must pass on every platform
   (including the iOS Simulator) with **no** Firebase config files present; push
   simply becomes inert. `send_message` and every other RPC must **never fail**
   because push dispatch is unconfigured — dispatch is best-effort and silent
   when unconfigured.
3. **Free.** FCM only; no paid third-party push service. Android push is fully
   free. iOS device push requires an Apple Developer account for APNs — this is
   inherent to iOS and unavoidable; document it, do not work around it.
4. **Match existing patterns.** Riverpod providers + repository pattern;
   migration filenames `YYYYMMDDNNNNNN_name.sql`; `SECURITY DEFINER ... set
   search_path = public` RPC style (see `send_message`); no new state-mgmt or
   networking libraries beyond firebase/local-notifications.
5. **No secrets committed.** `google-services.json`, `GoogleService-Info.plist`,
   and any Firebase service-account JSON are gitignored; tracked docs/examples
   explain how to obtain and place them.

## Architecture

```
sender device                Supabase (Postgres + Edge)              recipient device(s)
─────────────                ──────────────────────────              ───────────────────
send_message RPC ─insert─►  messages + message_envelopes
        │                          │
        └─ after insert ──► dispatch_push(spouse, 'chat', kind)
                                   │  (pg_net POST, best-effort, silent if unconfigured)
                                   ▼
                          Edge fn: push-dispatch
                            • verify dispatch secret
                            • load device_push_tokens for user
                            • FCM HTTP v1 send (content-free) ─────► FCM ──► APNs/Android ──► device
                            • prune dead tokens                                    │
                                                                                   ▼
                                                                    PushService: show local
                                                                    notification / deep-link →
                                                                    inbox pump fetches + decrypts
```

Recipient copy is content-free; the app wakes, the inbox pump fetches the
envelope and decrypts locally (existing `ChatService.handleInboxRow`).

## Tasks

### Task 1 — Backend: device tokens, dispatch primitive, chat + pairing hooks

New migration `20260726000001_push_notifications.sql`:

- **Table `public.device_push_tokens`**: `id uuid pk default gen_random_uuid()`,
  `user_id uuid not null references public.users(id) on delete cascade`,
  `token text not null unique`, `platform text not null check (platform in
  ('ios','android'))`, `created_at timestamptz not null default now()`,
  `updated_at timestamptz not null default now()`. Index on `user_id`. RLS on;
  policies: a user may `select`/`delete` only rows where `user_id = auth.uid()`
  (writes go through the RPCs). Grant select, delete to authenticated.
- **RPC `register_push_token(p_token text, p_platform text)`** — SECURITY
  DEFINER, `set search_path = public`. Upsert on `token`: set `user_id =
  auth.uid()`, `platform`, `updated_at = now()`. Raises `not_authenticated` if
  `auth.uid()` is null. `on conflict (token) do update` so a token that moves
  to a new account is reassigned (prevents cross-account push leak). Grant
  execute to authenticated.
- **RPC `unregister_push_token(p_token text)`** — deletes the row for that token
  owned by `auth.uid()`. Grant execute to authenticated.
- **Config table `private.push_config`** (create schema `private` if absent):
  single row, `function_url text`, `dispatch_secret text`. No RLS grants to
  authenticated (server-only). Documented as manually seeded per environment;
  **empty/absent → dispatch is a silent no-op.**
- **Helper `public.dispatch_push(p_user_id uuid, p_type text, p_title text,
  p_body text)`** — SECURITY DEFINER. Reads the single `private.push_config`
  row; if none or `function_url` is null, `return` silently (constraint 2).
  Otherwise `perform net.http_post(url := function_url, headers := jsonb_build_object(
  'Content-Type','application/json','Authorization','Bearer '||dispatch_secret),
  body := jsonb_build_object('user_id',p_user_id,'type',p_type,'title',p_title,
  'body',p_body))`. Wrap the whole body so any pg_net error is swallowed
  (best-effort). Never raises.
- **Recreate `send_message`** (drop/create like the existing
  `20260719000001` migration) adding a param `p_notify_kind text default
  'message'`. Keep all existing behaviour identical. After the envelope loop +
  conversation bump, if `p_notify_kind <> 'silent'`, call
  `dispatch_push(recipient_user, 'chat', 'New message',
  case p_notify_kind when 'reaction' then 'Your partner reacted to a message'
  else 'New message from your partner' end)` **once per distinct recipient
  user** (the spouse — not per envelope, and not for own-device sync copies
  where recipient = sender). Preserve the existing grant; grant the new
  signature. Keep the old 3-arg signature working OR update the one Dart caller
  (see Task 3/4 note) — recreate with the added trailing default param so
  existing calls still resolve.
- **Phase-2 pairing event**: trigger `AFTER UPDATE ON public.couples` when
  `status` transitions to `'active'`, calling `dispatch_push` for BOTH members
  with `type='pairing'`, title "You're connected", body "You and your partner
  are now paired 💛". (Demonstrates the generic path with a second event type.)
- **Tests** `supabase/tests/push_notifications_test.sql` (pgTAP if available in
  the local stack, else a psql assertion script runnable via
  `supabase test db` or `psql`): register upsert reassigns a token across users;
  unregister deletes only own token; RLS blocks reading another user's tokens;
  `dispatch_push` with empty `push_config` does not raise; `send_message` with
  `p_notify_kind='silent'` inserts message+envelopes and does not raise when
  push is unconfigured.

### Task 2 — Edge Function `push-dispatch` (FCM HTTP v1)

`supabase/functions/push-dispatch/index.ts` (Deno/TypeScript):

- Read env: `FCM_SERVICE_ACCOUNT` (JSON string of a Firebase service account),
  `FCM_PROJECT_ID`, `PUSH_DISPATCH_SECRET`, plus the standard
  `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`.
- Verify the incoming `Authorization: Bearer <PUSH_DISPATCH_SECRET>`; 401 on
  mismatch.
- Parse body `{ user_id, type, title, body }`; validate shape; 400 on bad input.
- With a service-role Supabase client, select `token, platform` from
  `device_push_tokens where user_id = user_id`. If none, 200 `{sent:0}`.
- Mint a Google OAuth2 access token from the service account (JWT grant,
  scope `https://www.googleapis.com/auth/firebase.messaging`) — no external npm;
  use Web Crypto for RS256 signing.
- For each token, POST to
  `https://fcm.googleapis.com/v1/projects/<FCM_PROJECT_ID>/messages:send` with a
  content-free `notification {title, body}` + `data {type}` (for deep-link) +
  platform config (Android channel `chat`; APNs `sound default`,
  `content-available`). Collect results.
- Prune tokens FCM reports as `UNREGISTERED`/`NOT_FOUND` (delete from table).
- Return `{sent, pruned}`.
- Register the function in `supabase/config.toml` (`[functions.push-dispatch]
  verify_jwt = false`) — it authenticates via the dispatch secret, not a user
  JWT.
- **Tests** (`deno test`, no network): OAuth JWT claim construction; request
  payload builder produces content-free bodies; dead-token classification from a
  sample FCM error response. Guard so tests need no real credentials.
- Docs stub `supabase/functions/push-dispatch/README.md`: required secrets +
  `supabase functions deploy push-dispatch` + `supabase secrets set ...` +
  seeding `private.push_config`.

### Task 3 — Flutter: deps + `PushService` core (+ unit tests)

- `flutter pub add firebase_core firebase_messaging flutter_local_notifications`
  (latest, per repo convention).
- `lib/core/notifications/push_service.dart` — `PushService`:
  - `Future<bool> init()`: `Firebase.initializeApp()` in try/catch — on any
    error (no config), log once, mark `unavailable`, return false (constraint 2).
    Init `flutter_local_notifications` with an Android channel `chat`; request
    permission (`FirebaseMessaging.requestPermission`, Android 13
    POST_NOTIFICATIONS). Wire `onMessage` → show local notification;
    `onMessageOpenedApp` + `getInitialMessage` → expose a tapped-notification
    stream/callback carrying `data.type`.
  - `Future<void> registerToken(SupabaseClient, {required onNav})`: get FCM
    token, call `register_push_token` RPC; subscribe `onTokenRefresh` → re-register.
  - `Future<void> unregisterToken(SupabaseClient)`: read current token, call
    `unregister_push_token`, delete local token.
  - A `NotificationTap` model `{type}` and a way for the app to observe taps.
  - Everything no-ops safely when `unavailable`.
- `lib/core/notifications/notification_providers.dart`: `pushServiceProvider`.
- **Unit tests** `test/core/notifications/push_service_test.dart` (mocktail):
  registerToken calls the RPC with token+platform; unavailable service no-ops;
  tap payload with `type:'chat'` maps to the chat route target. (Firebase
  plugin channels are mocked; no real Firebase.)

### Task 4 — Flutter: lifecycle wiring, deep-link, app-level sync

- `main.dart`: define a top-level `@pragma('vm:entry-point')
  firebaseMessagingBackgroundHandler`; register it; `await
  pushService.init()` after `Supabase.initialize` (guarded — must not block boot
  if it throws).
- Token lifecycle: in `ensureRegisteredProvider` (runs post-auth) also call
  `pushService.registerToken(...)` after device registration succeeds; in
  `signOutProvider` call `pushService.unregisterToken(...)` **before**
  `authRepository.signOut()` (needs the session). Best-effort; never block
  sign-out/registration on push failure.
- Deep-link: on notification tap (`type` in {chat,message,reaction} → `/home/chat`;
  `pairing` → `/home`) navigate via the existing router. Wire the tap stream at
  the app shell.
- **App-level message sync**: today `inboxPumpProvider`/`receiptPumpProvider`
  are watched only in `chat_screen`. Mount them at the authenticated app shell
  (e.g. a `HomeShell`/root authed widget) so a push that wakes the app syncs +
  decrypts new messages and updates the unread badge even if chat isn't open.
  Keep the chat-screen watches (idempotent) or move them up — no double
  subscription.
- **Tests** for the routing/lifecycle glue that can be unit-tested (tap→route
  mapping already in Task 3; here: signOut path calls unregister; ensureRegistered
  path calls registerToken). Keep integration-only bits (real plugin) out of
  unit tests.

### Task 5 — Native platform config (build-safe without secrets)

- **Android**: apply `com.google.gms.google-services` **conditionally** — only
  when `android/app/google-services.json` exists (Gradle `if (file(...).exists())
  { apply plugin }`) so the repo builds without it; add the classpath/plugin
  version; `POST_NOTIFICATIONS` permission; default notification channel/icon
  metadata. Verify `flutter build apk --debug` (or at least `flutter analyze` +
  Gradle config) succeeds with **no** `google-services.json`.
- **iOS**: add Push Notifications capability + `aps-environment` entitlement;
  `UIBackgroundModes` `remote-notification` in Info.plist; ensure the app builds
  for the simulator with no `GoogleService-Info.plist` (Firebase init is
  guarded). Do not require an APNs key to compile.
- **.gitignore**: `android/app/google-services.json`,
  `ios/Runner/GoogleService-Info.plist`, any `*serviceAccount*.json`.
- Confirm the Flutter deps' Podfile/Gradle wiring resolves; run
  `flutter analyze`.

### Task 6 — Docs: README notification setup

Add a "Push notifications (Firebase / FCM)" section to `README.md`:

- What it does; content-free E2E design; graceful-degradation note (app works
  without any of this).
- **Free-ness**: FCM free on both platforms; Android fully free; iOS device push
  needs an Apple Developer account for APNs (state plainly).
- Step-by-step: create Firebase project → add Android app → download
  `google-services.json` → add iOS app → download `GoogleService-Info.plist` →
  `flutterfire configure` (optional) → upload APNs auth key to Firebase → set
  Supabase secrets (`FCM_SERVICE_ACCOUNT`, `FCM_PROJECT_ID`,
  `PUSH_DISPATCH_SECRET`) → `supabase functions deploy push-dispatch` → seed
  `private.push_config` (function_url + dispatch_secret) via SQL.
- Local testing note: FCM needs a real device/emulator with Google Play
  services; the iOS Simulator cannot receive real push (documented limitation).
- Cross-link the design/plan doc.

## Out of scope

- Rich/image notifications, notification actions (quick-reply).
- Per-event user preferences UI (mute) — the `p_notify_kind='silent'` hook and
  token table make this a later, small addition.
- Web push (web is unsupported per README).
- Real end-to-end delivery verification in CI (needs live Firebase creds +
  physical devices).

## Verification

- `flutter analyze` clean; `flutter test` green (new unit tests included).
- `supabase db reset` applies the migration; SQL tests pass; `send_message`
  still works with push unconfigured (constraint 2).
- Repo builds with no Firebase config files present (constraint 2).
- Manual real-device push is left to the operator after they complete the
  Firebase/APNs setup (documented; not verifiable here without their creds).
