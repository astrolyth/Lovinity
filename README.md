# Sakīnah

> وَجَعَلَ بَيْنَكُم مَّوَدَّةً وَرَحْمَةً — *"And He placed between you affection and mercy"* (Qurʾān 30:21)

A private, two-person Flutter app helping a Muslim husband and wife grow closer to Allah and to each other — daily deen, connection, and long-distance rituals inside an end-to-end encrypted space of two.

**Built so far:** app shell + design system, email OTP **and** email/password auth (with password reset), role-based onboarding (gender → husband/wife), pairing (the "space of two"), prayer-time engine, shared prayer log, daily verse/hadith/question, duas, gratitude, menstrual cycle tracker, cycle-aware prayer scoring, role-specific care dashboards, settings, and **end-to-end encrypted chat** (Signal session layer + text messages, replies, encrypted reactions, delivered/read receipts, typing).

Design docs live in [`docs/superpowers/specs/`](docs/superpowers/specs/).

> **Platforms:** iOS, Android, and macOS. **Web is not supported** — the local database (Drift/`sqlite3`) uses `dart:ffi`, which the web compiler forbids. **Windows/Linux desktop builds aren't supported either** — `mobile_scanner` (QR pairing) has no desktop-Windows implementation — but a **Windows PC works fine as a dev machine** targeting an Android emulator/device; see [Windows setup](#windows-setup-dev-machine--android-target).

---

## Contents

1. [Prerequisites](#prerequisites)
2. [Windows setup (dev machine → Android target)](#windows-setup-dev-machine--android-target)
3. [Installation from scratch](#installation-from-scratch)
4. [Environment files, explained](#environment-files-explained)
5. [Email testing — everything goes to Mailtrap](#email-testing--everything-goes-to-mailtrap)
6. [Run path A — local Supabase (Docker)](#run-path-a--local-supabase-docker)
7. [Run path B — Supabase Cloud (no Docker)](#run-path-b--supabase-cloud-no-docker)
8. [Choosing a target device](#choosing-a-target-device)
9. [Tests](#tests)
10. [Project layout](#project-layout)
11. [Troubleshooting](#troubleshooting)

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

This repo doesn't have a working Windows **desktop** build — `mobile_scanner` (used for QR pairing) has no Windows implementation, so `flutter run -d windows` fails on the pairing screen. A Windows PC is a fully supported **development machine** for building and running the app on **Android** though; these steps get you there. (macOS/Linux developers can skip to [Installation from scratch](#installation-from-scratch).)

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

Everything else — Supabase (Docker or Cloud), Mailtrap, `.env`, `flutter test` — behaves identically to macOS/Linux once the target is Android.

---

## Installation from scratch

These steps take a brand-new machine to a running app. Do them in order.

**1. Clone the repo**

```bash
git clone <this-repo-url> sakinah
cd sakinah
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

Both paths read app config from `config/supabase.local.json` / `config/supabase.cloud.json`, and both read `MAILTRAP_SMTP_USER` / `MAILTRAP_SMTP_PASS` from the root `.env` — see the next two sections before running anything.

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
| `.env` | `.env.example` | Local Supabase connection details (auto-generated) **+ shared Mailtrap SMTP credentials** |
| `config/supabase.local.json` | `config/supabase.local.example.json` | App `--dart-define` config for path A (local Docker Supabase) |
| `config/supabase.cloud.json` | `config/supabase.cloud.example.json` | App `--dart-define` config for path B (Supabase Cloud) |

**`.env`** is read two ways:

- The Flutter/dev-tooling values (`STUDIO_URL`, `MAILPIT_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `S3_*`, …) are just a convenience snapshot of `supabase status`. After `supabase start`, regenerate them any time with:
  ```bash
  supabase status -o env >> .env
  ```
- `MAILTRAP_SMTP_USER` and `MAILTRAP_SMTP_PASS` are read by `supabase/config.toml` (`[auth.email.smtp]`, via `env(...)`) when you run `supabase start` — this is what makes local auth email land in Mailtrap instead of the default local inbox. **Ask a teammate for these two values** (they're the shared team Mailtrap inbox credentials, not something you generate yourself).

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

## Email testing — everything goes to Mailtrap

This project uses **one shared Mailtrap sandbox inbox** for all auth email (OTP codes, signup confirmation, password reset) across **every** environment and **every** machine:

- **Path B (Cloud)** already has custom SMTP configured in the Supabase dashboard to send through that Mailtrap inbox.
- **Path A (local Docker)** is configured the same way in [`supabase/config.toml`](supabase/config.toml) (`[auth.email.smtp]`), reading the inbox credentials from your local `.env` (`MAILTRAP_SMTP_USER` / `MAILTRAP_SMTP_PASS`) via `env(...)`.

So it doesn't matter whose laptop the project is running on, or whether it's pointed at local Docker or Cloud — **every auth email always lands in the same Mailtrap inbox.** To find a code:

1. Log in to [mailtrap.io](https://mailtrap.io) with the team's shared credentials (ask a teammate if you don't have them).
2. Open the project's sandbox inbox.
3. Find the latest message and copy the 6-digit code.

There is no need to check a personal email client, and — since local SMTP is overridden — the old Mailpit inbox (`http://127.0.0.1:54324`) will stay empty.

> Without `MAILTRAP_SMTP_USER`/`MAILTRAP_SMTP_PASS` set in `.env`, `supabase start` will still boot, but Auth will fail to send email (`env()` resolves to an empty string). Fill in `.env` **before** running path A.

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

- **Auth emails (OTP / signup confirm / password reset):** check the shared **Mailtrap** inbox — see [Email testing](#email-testing--everything-goes-to-mailtrap).
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
3. **Authentication → SMTP:** custom SMTP pointing at `sandbox.smtp.mailtrap.io` — this is what routes all Cloud auth email into the shared Mailtrap inbox (see [Email testing](#email-testing--everything-goes-to-mailtrap)).

---

## Choosing a target device

```bash
flutter devices                                   # list connected devices/simulators
flutter run -d <device-id> --dart-define-from-file=config/supabase.local.json
```

- **iOS Simulator:** its "location" is a hardcoded default (San Francisco). To get correct prayer times, set **Features → Location → Custom Location** to your real coordinates.
- **Physical iPhone:** open `ios/Runner.xcworkspace` in Xcode and set a Signing Team once, then `flutter run -d <device>`.

**Testing chat / pairing** needs **two** signed-in, paired accounts on **two** devices at once (e.g. two simulators, or an iOS simulator + the macOS app), both pointed at the same backend. Pair them with the invite code from the pairing screen. Both accounts' OTP/confirmation codes will show up in the same shared Mailtrap inbox — check timestamps/recipient address to tell them apart.

---

## Tests

```bash
flutter analyze
flutter test
```

> Some tests are **integration tests** that talk to a real local Supabase (repository, RPC, and end-to-end chat tests hit `127.0.0.1:54321`). They require **path A's `supabase start`** to be running; with the stack down, only the pure unit/widget tests pass.

---

## Project layout

```
lib/
├── core/
│   ├── config/          compile-time env (Env.supabaseUrl / OTP_LENGTH)
│   ├── crypto/          Signal session layer: key gen, KeyVault, SecureStore,
│   │   └── stores/      Drift-backed identity/session/prekey stores
│   ├── errors/          AppFailure hierarchy
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
supabase/config.toml     local stack config, incl. Mailtrap SMTP wiring
docs/superpowers/        design specs + implementation plans
config/                  dart-define configs (gitignored; *.example.json tracked)
.env                     local Supabase snapshot + Mailtrap creds (gitignored; .env.example tracked)
```

---

## Troubleshooting

- **`refresh_token_not_found` on launch** — a stale session in the Keychain (common after `supabase db reset` wipes local auth). Uninstall the app from the device/simulator, or Simulator → *Erase All Content and Settings*, then re-run.
- **OTP code doesn't match** — the app's slot count (`OTP_LENGTH`) must equal the project's Email OTP Length. Request a fresh code after changing either.
- **No email arriving anywhere** — check `MAILTRAP_SMTP_USER`/`MAILTRAP_SMTP_PASS` are set in `.env` (path A) or that Cloud SMTP is still configured in the dashboard (path B); then check the shared Mailtrap inbox, not Mailpit or your personal email.
- **`Could not choose the best candidate function` (PGRST203)** — a migration left two overloads of an RPC; re-run `supabase db reset` (path A) after pulling the latest migrations.
- **dart-define changes not taking effect** — dart-defines are compile-time; stop and re-run (a hot restart won't pick them up).
