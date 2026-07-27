# push-dispatch

Edge Function that relays a content-free push notification to a user's
registered devices via [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/migrate-v1).

It is called only by `public.dispatch_push(user_id, type, title, body)`
(see `supabase/migrations/20260726000001_push_notifications.sql`), which
authenticates with a shared secret rather than a Supabase user JWT. That's why
this function has `verify_jwt = false` in `supabase/config.toml` — auth is
handled inside the function via the `Authorization: Bearer <dispatch secret>`
header, checked against `PUSH_DISPATCH_SECRET`.

**E2E note:** this function never sees message plaintext. It only forwards
the generic `type`/`title`/`body` chosen by the database (e.g. "New message
from your partner") — it has no way to decrypt ciphertext and doesn't try.

## Required secrets

Set these on the Supabase project (never commit real values):

```bash
supabase secrets set \
  FCM_SERVICE_ACCOUNT="$(cat /path/to/firebase-service-account.json)" \
  FCM_PROJECT_ID="your-firebase-project-id" \
  PUSH_DISPATCH_SECRET="$(openssl rand -hex 32)"
```

- `FCM_SERVICE_ACCOUNT` — the full JSON contents of a Firebase service-account
  key with the `Firebase Cloud Messaging API` role (Project settings → Service
  accounts → Generate new private key). Passed as a single JSON **string**.
- `FCM_PROJECT_ID` — the Firebase project ID (same project as the service
  account).
- `PUSH_DISPATCH_SECRET` — any long random secret. This exact value must also
  be seeded into `private.push_config.dispatch_secret` (below) — it's what
  `dispatch_push()` sends as `Authorization: Bearer <...>` and what this
  function checks incoming requests against.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically to
every deployed Edge Function by the Supabase platform — no need to set them
yourself. (For local `supabase functions serve`, the CLI also injects them
from your local stack.)

## Deploy

```bash
supabase functions deploy push-dispatch
```

`verify_jwt = false` is already set for this function in `supabase/config.toml`.

## Wire up `private.push_config`

Once deployed, note the function's URL (visible in the deploy output or the
dashboard, of the form
`https://<project-ref>.supabase.co/functions/v1/push-dispatch`), then seed the
single-row config table so `dispatch_push()` stops being a no-op:

```sql
insert into private.push_config (id, function_url, dispatch_secret)
values (true, 'https://<project-ref>.supabase.co/functions/v1/push-dispatch',
        '<same value as PUSH_DISPATCH_SECRET>')
on conflict (id) do update
  set function_url    = excluded.function_url,
      dispatch_secret = excluded.dispatch_secret;
```

Run this against the target environment's database (e.g. via `supabase db
execute` or the SQL editor in the dashboard). Until this row exists,
`dispatch_push()` silently no-ops and every RPC that calls it (chat send,
pairing activation) keeps working exactly as before — see the migration's
comments for the graceful-degradation rationale.

## Behavior

- `POST /` with header `Authorization: Bearer <PUSH_DISPATCH_SECRET>` and body
  `{ "user_id": "<uuid>", "type": "chat" | "pairing", "title": "<text>", "body": "<text>" }`.
- 401 if the bearer secret is missing or wrong.
- 400 if the body doesn't match the shape above.
- Loads all `device_push_tokens` rows for `user_id` using the service-role
  key (bypasses RLS by design — this is a trusted server-to-server call, not
  a user request).
- No tokens → `200 { "sent": 0, "pruned": 0 }`.
- Otherwise mints a Google OAuth2 access token from the service account and
  sends one FCM HTTP v1 message per token. Each token is handled
  independently, so one bad/dead token never aborts the rest of the batch.
- Any per-token response FCM reports as `UNREGISTERED` / `NOT_FOUND` (or a
  bare HTTP 404) is treated as a dead token and deleted from
  `device_push_tokens`.
- Response: `200 { "sent": <count>, "pruned": <count> }`.

## Tests

Pure logic (body validation, OAuth claim construction, FCM message shape,
dead-token classification) lives in `logic.ts` and is unit tested in
`index.test.ts` with **no network calls and no real credentials** (the test
file imports `logic.ts` directly, never `index.ts`, since `index.ts`'s
top-level `Deno.serve(...)` needs `--allow-net` just to be imported):

```bash
cd supabase/functions/push-dispatch
deno test
```

or from the repo root:

```bash
deno test supabase/functions/push-dispatch/index.test.ts
```

To type-check without running:

```bash
deno check supabase/functions/push-dispatch/index.ts
```
