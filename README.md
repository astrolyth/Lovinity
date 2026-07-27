# Lovinity

> وَجَعَلَ بَيْنَكُم مَّوَدَّةً وَرَحْمَةً — *"And He placed between you affection and mercy"* (Qurʾān 30:21)

A private, two-person Flutter app helping a Muslim husband and wife grow closer to Allah and to each other — daily deen, connection, and long-distance rituals inside an end-to-end encrypted space of two.

**Built so far:** app shell + design system, email OTP **and** email/password auth (with password reset), role-based onboarding (gender → husband/wife), pairing (the "space of two"), prayer-time engine, shared prayer log, daily verse/hadith/question, duas, gratitude, menstrual cycle tracker, cycle-aware prayer scoring, role-specific care dashboards, settings, and **end-to-end encrypted chat** (Signal session layer + text messages, replies, encrypted reactions, delivered/read receipts, typing).

Design docs live in [`docs/superpowers/specs/`](docs/superpowers/specs/).

> **Platforms:** iOS, Android, and macOS. **Web is not supported** — the local database (Drift/`sqlite3`) uses `dart:ffi`, which the web compiler forbids. **Windows/Linux desktop builds aren't a supported target** — untested, and one dependency (`mobile_scanner`, currently unused in-app) has no desktop-Windows implementation. A **Windows PC works fine as a dev machine** targeting an Android emulator/device; see [Windows setup](#windows-setup-dev-machine--android-target).

---

## Contents

1. [Prerequisites](#prerequisites)
2. [Windows setup (dev machine → Android target)](#windows-setup-dev-machine--android-target)
3. [Installation from scratch](#installation-from-scratch)
4. [Environment files, explained](#environment-files-explained)
5. [Email testing — Mailpit (free, no account)](#email-testing--mailpit-free-no-account)
6. [Run path A — local Supabase (Docker)](#run-path-a--local-supabase-docker)
7. [Run path B — Supabase Cloud (no Docker)](#run-path-b--supabase-cloud-no-docker)
8. [Choosing a target device](#choosing-a-target-device)
9. [Tests](#tests)
10. [Push notifications (Firebase / FCM)](#push-notifications-firebase--fcm)
11. [Project layout](#project-layout)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install these once per machine, regardless of OS:

| Tool | Version | Install |
|---|---|---|
| **Flutter** | 3.44+ | `flutter --version` — [install guide](https://docs.flutter.dev/get-started/install) |
| **Git** | any recent | `git --version` |
| **Supabase CLI** | latest | macOS: `brew install supabase/tap/supabase`; Windows/Linux: [CLI install guide](https://supabase.com/docs/guides/local-development/cli/getting-started) |
| **Docker Desktop** | latest | only needed for **path A** (local Supabase) — [docker.com](https://www.docker.com/products/docker-desktop/) |
| **Xcode 16+** | — | macOS only, for iOS/macOS builds |
| **Android Studio / Android SDK 34+** | — | for Android builds, any OS |

Run `flutter doctor` after installing and resolve anything it flags before continuing.

---

## Windows setup (dev machine → Android target)

This repo doesn't have a working Windows **desktop** build — it's untested, and `mobile_scanner` (a declared dependency, currently unused in-app) has no Windows implementation, so `flutter run -d windows` isn't guaranteed to build. A Windows PC is a fully supported **development machine** for building and running the app on **Android** though; these steps get you there. (macOS/Linux developers can skip to [Installation from scratch](#installation-from-scratch).)

1. **Flutter** — [install for Windows](https://docs.flutter.dev/get-started/install/windows), add `flutter\bin` to `PATH`, then run `flutter doctor`.
2. **Android Studio** — install it, then in *SDK Manager* install **Android SDK 34+**, and in *Device Manager* create at least one virtual device (emulator). `flutter doctor` should show the Android toolchain as ✅.
3. **Git for Windows** — [git-scm.com](https://git-scm.com/download/win). Run this README's `bash` code blocks in the bundled **Git Bash** (or WSL) so they work as-is; PowerShell can run the simple `cp`/one-line commands too, but multi-line blocks assume a bash-like shell.
4. **Docker Desktop** — only needed for **path A** (local Supabase). [Install it](https://www.docker.com/products/docker-desktop/) and enable the **WSL 2 backend** when prompted (required on Windows).
5. **Supabase CLI** — the Homebrew command in [Prerequisites](#prerequisites) is macOS-only. On Windows, install via [Scoop](https://scoop.sh/):

   ```powershell
   scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
   scoop install supabase
   ```

   Or skip installing it and prefix every `supabase ...` command in this README with `npx`, e.g. `npx supabase start`.

From here, follow [Installation from scratch](#installation-from-scratch) as written, then target the emulator/device instead of iOS/macOS:

```bash
flutter devices                                                   # confirm the emulator/device is listed
flutter run -d emulator-5554 --dart-define-from-file=config/supabase.local.json
```

Everything else — Supabase (Docker or Cloud), Mailpit, `.env`, `flutter test` — behaves identically to macOS/Linux once the target is Android.

---

## Installation from scratch

These steps take a brand-new machine to a running app. Do them in order.

**1. Clone the repo**

```bash
git clone <this-repo-url> lovinity
cd lovinity
```

**2. Install Flutter packages**

```bash
flutter pub get
```

**3. Create your local env files from the tracked examples**

Nothing secret is committed to git — every real config file below is gitignored, and a `*.example.*` version is tracked instead so a fresh clone always has a template to copy:

```bash
cp .env.example .env
cp config/supabase.local.example.json config/supabase.local.json
cp config/supabase.cloud.example.json config/supabase.cloud.json
```

**4. Pick a backend path and fill in the copied files**

- **Path A (local Docker Supabase)** — recommended for day-to-day development (schema changes, migrations, RLS work). See [Run path A](#run-path-a--local-supabase-docker).
- **Path B (Supabase Cloud)** — no Docker required, talks to the team's hosted project. See [Run path B](#run-path-b--supabase-cloud-no-docker).

Both paths read app config from `config/supabase.local.json` / `config/supabase.cloud.json`. Auth email needs no extra setup for local dev — it's caught by the bundled Mailpit inbox (see [Email testing](#email-testing--mailpit-free-no-account)).

**5. Run the app**

```bash
flutter run --dart-define-from-file=config/supabase.local.json   # path A
# or
flutter run --dart-define-from-file=config/supabase.cloud.json   # path B
```

---

## Environment files, explained

Every developer's machine needs three local files. All three are gitignored — only the `*.example.*` versions are tracked, so `git status` should never show the real ones.

| Real file (gitignored) | Tracked example | Used for |
|---|---|---|
| `.env` | `.env.example` | Local Supabase connection details (auto-generated); optional self-hosted-Mailpit SMTP vars (blank for local dev) |
| `config/supabase.local.json` | `config/supabase.local.example.json` | App `--dart-define` config for path A (local Docker Supabase) |
| `config/supabase.cloud.json` | `config/supabase.cloud.example.json` | App `--dart-define` config for path B (Supabase Cloud) |

**`.env`** is read two ways:

- The Flutter/dev-tooling values (`STUDIO_URL`, `MAILPIT_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `S3_*`, …) are just a convenience snapshot of `supabase status`. After `supabase start`, regenerate them any time with:
  ```bash
  supabase status -o env >> .env
  ```
- `MAILPIT_SMTP_HOST` / `MAILPIT_SMTP_USER` / `MAILPIT_SMTP_PASS` are **only** needed if you enable `[auth.email.smtp]` in `supabase/config.toml` to point at a self-hosted Mailpit (cloud/staging). For local dev leave them blank — the bundled Mailpit inbox needs no credentials. See [Email testing](#email-testing--mailpit-free-no-account).

**`config/supabase.*.json`** feed the app at compile time via `--dart-define-from-file`. Never commit real ones — the anon/publishable key for path B and the URL for path A are per-environment.

```jsonc
// config/supabase.local.json (path A) — the anon key below is Supabase's
// fixed local-dev demo key; it's identical on every machine, no need to
// look it up unless you changed supabase/config.toml's JWT secret.
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_ANON_KEY": "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  "OTP_LENGTH": 6
}
```

```jsonc
// config/supabase.cloud.json (path B) — from Supabase dashboard →
// Project Settings → API. Use the anon / publishable key, never service_role.
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<anon / publishable key>",
  "OTP_LENGTH": 6
}
```

---

## Email testing — Mailpit (free, no account)

All auth email (OTP codes, signup confirmation, password reset) is caught by **[Mailpit](https://mailpit.axllent.org/)** — a fake SMTP inbox with a web UI. Mailpit is **100% free, open-source, and self-hosted**: no account, no API key, no external service, no rate limits. Supabase's local stack **bundles Mailpit and runs it automatically** — there is nothing to install or configure for local development.

### Path A (local Docker) — zero setup

`supabase start` already runs Mailpit for you. GoTrue routes every auth email into it because `[auth.email.smtp]` in [`supabase/config.toml`](supabase/config.toml) is left **disabled** (its presence would override the built-in inbox). To read a code:

1. Open the Mailpit web UI: **<http://127.0.0.1:54324>**
2. Click the latest message.
3. Copy the 6-digit code (or click the confirm/reset link).

That's it — no `.env` values are needed for local email.

### Path B (Cloud) — pick one

Supabase Cloud does not bundle Mailpit, so choose whichever fits:

- **Simplest & recommended for testing:** do all email-based flows (signup, OTP, password reset) against **Path A**, where Mailpit already catches everything. Cloud is then only needed for non-email work.
- **Cloud with Mailpit too (still free, you host it):** run the Mailpit container on any host reachable from the internet (a small VPS, a free-tier container host, etc.) with its SMTP port exposed:

  ```bash
  docker run -d --restart unless-stopped \
    -p 8025:8025 -p 1025:1025 axllent/mailpit
  ```

  Then in the Supabase **dashboard → Authentication → SMTP**, point custom SMTP at that host's `1025` (host/user/pass as configured) and read mail at its `:8025` web UI. For a local-only stack you'd instead set `MAILPIT_SMTP_HOST`/`MAILPIT_SMTP_USER`/`MAILPIT_SMTP_PASS` in `.env` and flip `[auth.email.smtp] enabled = true` in `config.toml`.
- **Supabase's built-in Cloud email:** fine for a couple of manual tests, but rate-limited — not for repeated testing.

> **Bottom line:** for day-to-day testing, use **Path A** and read mail at <http://127.0.0.1:54324>. It's free, instant, and needs no setup.

---

## Run path A — local Supabase (Docker)

Everything runs on your machine: Postgres, Auth, Realtime, Storage. Best for schema/migration work.

```bash
# 1. Start the local stack (Docker must be running)
supabase start

# 2. Apply all migrations from scratch (+ seed data)
supabase db reset

# 3. Print the local URL + anon key (and optionally refresh .env)
supabase status
supabase status -o env >> .env
```

Confirm `config/supabase.local.json` matches (see [example above](#environment-files-explained)), then run:

```bash
flutter run --dart-define-from-file=config/supabase.local.json
```

- **Auth emails (OTP / signup confirm / password reset):** open the bundled **Mailpit** inbox at <http://127.0.0.1:54324> — see [Email testing](#email-testing--mailpit-free-no-account).
- To reset the database at any time: `supabase db reset`. To stop the stack: `supabase stop`.

---

## Run path B — Supabase Cloud (no Docker)

No Docker; the app talks to the team's hosted Supabase project. Production-style. Migrations are pushed over the network (`db push` does **not** need Docker).

```bash
# 1. Link this repo to the cloud project (one-time)
supabase login
supabase link --project-ref <project-ref>     # ref = the subdomain of the project URL

# 2. Push all local migrations to the cloud database
supabase db push
```

Fill in `config/supabase.cloud.json` from **Supabase dashboard → Project Settings → API** (see [example above](#environment-files-explained)), then run:

```bash
flutter run --dart-define-from-file=config/supabase.cloud.json
```

**Dashboard auth setup (already done for the shared project — only needed if you spin up a new one):**

1. **Authentication → Providers → Email:** set **Email OTP Length** to **6** (or match `OTP_LENGTH` in the config to whatever the project issues).
2. **Authentication → Email Templates:** *Confirm signup*, *Magic Link*, and *Reset Password* templates must each include `{{ .Token }}` (the defaults only contain a link).
3. **Authentication → SMTP:** for repeated email testing on Cloud, point custom SMTP at a self-hosted Mailpit host (see [Email testing](#email-testing--mailpit-free-no-account)); otherwise the built-in Cloud email works for a handful of manual tests.

---

## Choosing a target device

```bash
flutter devices                                   # list connected devices/simulators
flutter run -d <device-id> --dart-define-from-file=config/supabase.local.json
```

- **iOS Simulator:** its "location" is a hardcoded default (San Francisco). To get correct prayer times, set **Features → Location → Custom Location** to your real coordinates.
- **Physical iPhone:** open `ios/Runner.xcworkspace` in Xcode and set a Signing Team once, then `flutter run -d <device>`.

**Testing chat / pairing** needs **two** signed-in, paired accounts on **two** devices at once (e.g. two simulators, or an iOS simulator + the macOS app), both pointed at the same backend. Pair them with the invite code from the pairing screen. Both accounts' OTP/confirmation codes show up in the same Mailpit inbox (<http://127.0.0.1:54324>) — check timestamps/recipient address to tell them apart.

---

## Tests

```bash
flutter analyze
flutter test
```

> Some tests are **integration tests** that talk to a real local Supabase (repository, RPC, and end-to-end chat tests hit `127.0.0.1:54321`). They require **path A's `supabase start`** to be running; with the stack down, only the pure unit/widget tests pass.

---

## Push notifications (Firebase / FCM)

**Optional.** With none of this configured, the app builds, runs, and its chat/pairing RPCs all work exactly as before — push is simply inert. Everything in this section is for an operator who wants real push notifications; skip it for local development.

### What it does

When your partner sends you a chat message, or when your couple first becomes paired, your device gets a **content-free** push notification — e.g. "New message from your partner" or "You're connected". The server never puts message plaintext in a push: chat is end-to-end encrypted (Signal), so the backend can't read it anyway. The notification is just a wake-up nudge; tapping it (or the app already being open) triggers the existing inbox sync, which fetches and decrypts the real message locally. See `supabase/migrations/20260726000001_push_notifications.sql` and `supabase/functions/push-dispatch/README.md` for the server-side details, and [`docs/superpowers/plans/2026-07-26-push-notifications.md`](docs/superpowers/plans/2026-07-26-push-notifications.md) for the full design.

### Cost

- **FCM itself is free** on both platforms, no paid tier needed (Firebase Spark/free plan is enough).
- **Android push is fully free** — no extra account needed beyond a Firebase project.
- **iOS device push requires an Apple Developer account (US$99/yr)** to create an APNs auth key — this is an Apple/iOS requirement inherent to push on that platform, not something this project adds or could avoid.
- The **iOS Simulator cannot receive real push notifications** — you need a physical iPhone to test iOS push.
- The **Android emulator** can receive push, but only on an image that includes **Google Play services** (not a bare AOSP image).

### Step-by-step setup

**1. Create a Firebase project** at [console.firebase.google.com](https://console.firebase.google.com/) (the free Spark plan is sufficient).

**2. Add an Android app** to the Firebase project (package name must match `android/app/build.gradle.kts`'s `applicationId`), then download the generated `google-services.json` and place it at:

```
android/app/google-services.json
```

This path is gitignored — it's never committed. `android/app/build.gradle.kts` only applies the `com.google.gms.google-services` Gradle plugin when this file exists, so the Android build succeeds with or without it.

**3. Add an iOS app** to the same Firebase project (bundle ID must match `ios/Runner.xcodeproj`'s bundle identifier), then download `GoogleService-Info.plist` and place it at:

```
ios/Runner/GoogleService-Info.plist
```

Also gitignored. Optionally run `flutterfire configure` instead of doing steps 2–3 by hand — it downloads both files and can also generate `firebase_options.dart` for you.

**4. iOS only — create and upload an APNs auth key.** In the [Apple Developer portal](https://developer.apple.com/account/resources/authkeys/list) (requires the paid membership above), create an APNs Auth Key, then upload it in the Firebase console under **Project settings → Cloud Messaging → Apple app configuration**. Without this, iOS push silently never arrives even with the app fully wired up.

**5. Create a Firebase service-account key** for the edge function: Firebase console → **Project settings → Service accounts → Generate new private key**. This downloads a JSON file — keep it out of git (already covered by `.gitignore`'s `**/*serviceAccount*.json` / `**/*service-account*.json` patterns).

**6. Set the Supabase secrets and deploy the edge function:**

```bash
supabase secrets set \
  FCM_SERVICE_ACCOUNT="$(cat /path/to/firebase-service-account.json)" \
  FCM_PROJECT_ID="your-firebase-project-id" \
  PUSH_DISPATCH_SECRET="$(openssl rand -hex 32)"

supabase functions deploy push-dispatch
```

**7. Seed `private.push_config`** with the deployed function's URL and the same dispatch secret, so `dispatch_push()` stops being a no-op. Run this SQL against the target environment's database (dashboard SQL editor, or `supabase db execute`):

```sql
insert into private.push_config (id, function_url, dispatch_secret)
values (true, 'https://<project-ref>.supabase.co/functions/v1/push-dispatch',
        '<same value as PUSH_DISPATCH_SECRET>')
on conflict (id) do update
  set function_url    = excluded.function_url,
      dispatch_secret = excluded.dispatch_secret;
```

See [`supabase/functions/push-dispatch/README.md`](supabase/functions/push-dispatch/README.md) for the authoritative reference on required secrets, the function's request/response shape, and dead-token pruning — this section only summarizes it.

### Local testing caveats

- Push needs a real device (or, for Android, an emulator image with Google Play services) — the **iOS Simulator cannot receive real push**.
- `dispatch_push()` calls out over `pg_net` from Postgres; reaching a deployed edge function from the **local Docker stack (path A)** can be finicky depending on your network. Push is primarily exercised as a **cloud feature (path B)** — set up path B (or point local dev at a cloud project's `push-dispatch` function) if you want to see real notifications end-to-end.
- Until `private.push_config` is seeded, `dispatch_push()` is a silent no-op and chat/pairing behave exactly as they do without any of this setup.

---

## Project layout

```
lib/
├── core/
│   ├── config/          compile-time env (Env.supabaseUrl / OTP_LENGTH)
│   ├── crypto/          Signal session layer: key gen, KeyVault, SecureStore,
│   │   └── stores/      Drift-backed identity/session/prekey stores
│   ├── errors/          AppFailure hierarchy
│   ├── notifications/   PushService (FCM + local notifications, gracefully inert with no Firebase config)
│   ├── router/          go_router + auth / onboarding / pairing guards
│   ├── storage/         Drift database (Signal state + local chat history)
│   ├── theme/ time/ motion/ widgets/   design system + prayer/Hijri engine
├── features/            one folder per pillar (data / domain / presentation)
│   ├── auth/ onboarding/ pairing/      identity, gender/role, space-of-two
│   ├── prayer_log/ scoring/ cycle/     prayer tracking + cycle-aware scoring
│   ├── daily/ duas/ gratitude/ care/   deen content + wellbeing
│   ├── chat/            E2E messaging (payload, service, store, screen)
│   ├── settings/ home/ location/
└── shared/              models + app-scope providers

supabase/migrations/     schema, RLS, RPCs (source of truth for both paths)
supabase/functions/      Edge Functions (push-dispatch: FCM relay for push notifications)
supabase/config.toml     local stack config (bundled Mailpit inbox for auth email)
docs/superpowers/        design specs + implementation plans
config/                  dart-define configs (gitignored; *.example.json tracked)
.env                     local Supabase snapshot (gitignored; .env.example tracked)
```

---

## Troubleshooting

- **`refresh_token_not_found` on launch** — a stale session in the Keychain (common after `supabase db reset` wipes local auth). Uninstall the app from the device/simulator, or Simulator → *Erase All Content and Settings*, then re-run.
- **OTP code doesn't match** — the app's slot count (`OTP_LENGTH`) must equal the project's Email OTP Length. Request a fresh code after changing either.
- **No email arriving (path A)** — open the Mailpit web UI at <http://127.0.0.1:54324>; confirm the local stack is up (`supabase status`). Local auth email never goes to a real inbox, so don't check a personal email client. (Path B: if you enabled self-hosted Mailpit, verify the dashboard SMTP host/port are reachable.)
- **`Could not choose the best candidate function` (PGRST203)** — a migration left two overloads of an RPC; re-run `supabase db reset` (path A) after pulling the latest migrations.
- **dart-define changes not taking effect** — dart-defines are compile-time; stop and re-run (a hot restart won't pick them up).
