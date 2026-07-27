# Sakīnah — Email/Password Sign-up + Password Reset

**Date:** 2026-07-16
**Status:** Design approved
**Depends on:** existing auth (OTP sign-in, `AuthRepository`), onboarding, `handle_new_auth_user` trigger

## Summary

Add a proper email+password **sign-up** flow that collects the profile up front (name, gender, madhhab), and a **forgot/reset password** flow. Both are exercised end-to-end against Supabase Cloud with Mailtrap catching the emails.

## Decisions (agreed)

1. **Confirm email is ON.** `signUp` returns no session; the user verifies a 6-digit code before being signed in. More production-correct — password reset depends on the address being real.
2. **OTP sign-in keeps `shouldCreateUser: true`.** Two signup paths coexist: the **form** (complete profile) and **OTP** (creates a bare account, then the existing onboarding screen fills gender/madhhab). Onboarding stays live.
3. **Password reset uses OTP-code recovery**, not magic links. `resetPasswordForEmail` → code → `verifyOTP(type: recovery)` → `updateUser(password:)`. No deep-link/Universal-Links infrastructure; works in the simulator and with Mailtrap.
4. **Minimum password length: 8** client-side (server currently allows 6; recommend raising it to match).
5. **Reset is one screen** (code + new password + confirm), so there's no dangling "recovered session, password unchanged" state.

## Why profile fields go through signup metadata

With Confirm-email ON there is **no session at signup time**, so the client cannot write `public.users` (RLS needs `auth.uid()`). Instead the profile is passed as `signUp` **metadata**, and the existing `handle_new_auth_user` trigger — which already copies `display_name` — is extended to copy `gender` and `madhhab` server-side at `auth.users` insert.

This is also what makes onboarding auto-skip: the router sends users to `/onboarding` only when `gender IS NULL`, so a form signup arrives complete and bypasses it, while an OTP signup (no metadata) still lands there.

## Components

### 1. Migration — `20260716000002_signup_profile_metadata.sql`

Recreate `handle_new_auth_user` to copy `display_name`, `gender`, `madhhab` from `raw_user_meta_data`, **validated in SQL** so a bad client value cannot break signup or trip the CHECK constraint:

- `gender`: `in ('male','female')` else `null`
- `madhhab`: `in ('shafi','hanafi')` else `'shafi'`

### 2. `AuthRepository` additions

Following the existing `AuthException → AuthFailure` wrapping:

| Method | Purpose |
|---|---|
| `signUpWithProfile({email, password, displayName, gender, madhhab})` | signUp with profile metadata |
| `sendPasswordReset(email)` | `resetPasswordForEmail` |
| `verifySignupOtp({email, token})` | `verifyOTP(type: signup)` |
| `verifyRecoveryOtp({email, token})` | `verifyOTP(type: recovery)` |
| `updatePassword(newPassword)` | `updateUser(UserAttributes(password:))` |

### 3. Screens

- **`/auth/sign-up`** — name, email, gender chips, madhhab dropdown, password, confirm → `signUpWithProfile` → `/auth/otp?purpose=signup`.
- **`/auth/otp`** — generalized with an `OtpPurpose` (`signIn` | `signUp`); reuses the existing 6-slot input + 60s resend cooldown. `signIn` → `verifyEmailOtp`; `signUp` → `verifySignupOtp`.
- **`/auth/forgot-password`** — email → `sendPasswordReset` → `/auth/reset-password?email=`.
- **`/auth/reset-password`** — code + new password + confirm → `verifyRecoveryOtp` then `updatePassword` → signed in → `/home`.
- **`/auth/sign-in`** — add "Create account" and "Forgot password?" links.

### 4. Router

Register the three new routes. **Exempt `/auth/reset-password` from the signed-in redirect**: verifying the recovery code creates a session, and the existing guard bounces signed-in users off `/auth/*` → `/home`, which would yank the user off the screen before the new password is saved.

### 5. Validation

Name non-empty; email contains `@`; gender required; password ≥ 8; confirm must match. Errors surface inline via the existing `SakInlineError`.

## Error handling

Repository wraps `AuthException` into `AuthFailure`; screens catch `AppFailure` and render the message inline, with a generic fallback for unexpected errors — matching `sign_in_screen.dart`. Notable cases surfaced to the user: email already registered, invalid/expired code, weak password, rate-limited resend.

## Testing

- **Widget tests:** sign-up validation (mismatched passwords, short password, missing gender, invalid email, happy path invokes the repository), forgot-password validation, reset-password validation.
- **Migration:** verified via `supabase db push` + a SQL check that the trigger reads the new metadata keys.
- **Repository methods** hit live Supabase; local Supabase is off (project runs against Cloud), so these are verified manually through the Mailtrap flow rather than by an integration test.

## Operational steps (Supabase dashboard — manual)

1. Turn **Confirm email ON**.
2. **"Confirm signup"** email template must contain `{{ .Token }}`.
3. **"Reset Password"** email template must contain `{{ .Token }}` (default has only `{{ .ConfirmationURL }}`; without the token there is no code to enter).
4. Optionally raise **minimum password length** to 8 to match the client.

## Out of scope

- Magic-link / deep-link auth (Universal Links).
- Social sign-in.
- Changing password while signed in (Settings) — reset-by-email only for now.
