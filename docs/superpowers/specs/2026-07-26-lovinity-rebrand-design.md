# Lovinity rebrand

## Summary

Rename the app from Sakīnah to **Lovinity** end-to-end — Dart package, bundle identifiers, design-system class prefix, app copy, app icon, and color palette — using the provided logo (`assets/5db4bbe5-8e8a-4266-9ceb-2985892176e6.jpeg`) as the source of truth for the new visual identity.

## Decisions (agreed)

1. **Full technical rename**, not cosmetic-only: Dart package `sakinah` → `lovinity` (rewrites `package:sakinah/` in all 43 importing files), Android `applicationId` / iOS+macOS `PRODUCT_BUNDLE_IDENTIFIER` `com.sakinah.sakinah` → `com.lovinity.lovinity`. Accepted trade-off: existing installs are a fresh install, not an in-place upgrade.
2. **Design-system prefix `Sak*` → `Lov*`** across the 28 token/widget classes (`SakColors`, `SakButton`, `SakScaffold`, …) and their `sak_*.dart` files, since keeping `Sak`-prefixed classes inside a `lovinity` package would be inconsistent.
3. **Theme goes dark-first, black + gold**, replacing the "Modern Sanctuary" cool-off-white/deep-green palette. Dark mode is the hero look (near-black bg, bright gold accent, matches the logo directly); light mode becomes a warm cream/gold variant instead of the old cool off-white/green, so neither mode is off-brand. Colors are sampled directly from the logo's pixels (see Components).
4. **Typography unchanged**: Inter (body) + Space Grotesk (headers) + Amiri (Arabic) stay, just recolored. No new font family.
5. **Icon**: crop just the gold emblem (monogram + infinity + two praying figures + heart + crescent) off the top of the source logo — no wordmark/tagline text, since that doesn't read at launcher-icon sizes. Generate all platform icon sizes from that one master via `flutter_launcher_icons` rather than hand-placing each size. Splash screen regenerated the same way (`flutter_native_splash`) so the launch screen isn't left on the old palette.
6. **Full poster graphic** (with "LOVINITY" wordmark + tagline) is used once as an in-app brand moment: the sign-in screen hero, and a new Settings → About screen. Not tiled elsewhere.
7. **Out of scope, deliberately**: historical dated files under `docs/superpowers/specs/` are left alone (decision record, not live docs); the local folder name and git remote/repo name stay `CoupleDaily` (separate, deliberate decision with its own consequences — IDE paths, GitHub URL).

## Components

### 1. Naming & identifiers

- `pubspec.yaml`: `name: sakinah` → `name: lovinity`, description updated.
- All `package:sakinah/` imports (43 files) → `package:lovinity/`.
- `Sak*` classes → `Lov*` (scripted rename, longest-name-first to avoid partial-match corruption between e.g. `SakDigitSlots` / `SakDigitSlotsController`), files `sak_*.dart` → `lov_*.dart`.
- `MaterialApp.title` and in-app "Sakīnah"/"Sakinah" copy (auth, pairing screens) → "Lovinity".
- Android `applicationId` + `android:label`; iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER` (all build configs incl. RunnerTests) + `CFBundleName`/`CFBundleDisplayName`; Windows/Linux CMake product name — all updated for consistency even though desktop isn't a shipped target.
- `supabase/config.toml`'s `project_id` (local Docker container namespace label only, no external effect) updated to `lovinity`.

### 2. Color tokens (`LovColors`, formerly `SakColors`)

Sampled from the logo (`L`-stem highlight ≈ `#FFE165`/`#FFEE7F`, base gold ≈ `#F3B83A`/`#F5C549`, background ≈ `#000000`):

| Token | Dark (primary) | Light |
|---|---|---|
| background | `#0A0A0A` | `#FBF6EC` |
| surface | `#141414` | `#FFFFFF` |
| accent | `#F2C14E` | `#A6690F` |
| accentSoft | `#3A2E12` | `#F3E3C0` |
| textPrimary | `#F5F1E8` | `#1A1610` |

Remaining derived tokens (`surfaceMuted`, `surfaceSunken`, `accentInk`, `textSecondary`, `textTertiary`, `divider`) are tuned to the same warm black/cream family during implementation. `success`/`warning`/`error` stay close to their current hues (they're semantic, not brand) with only minor warmth adjustments if needed for contrast against the new surfaces.

### 3. Icon & splash pipeline

- Master icon: emblem-only crop of the logo, black background, centered — saved as a tracked asset.
- `flutter_launcher_icons` (dev dependency, latest) generates iOS/Android/macOS icon sets from that master.
- `flutter_native_splash` (dev dependency, latest) generates the launch screen (black background + emblem) so first paint matches the new brand instead of the old cream/green launch image.
- Full poster graphic saved as a tracked, properly named asset (not the random upload filename) for in-app use.

### 4. Verification

- `flutter analyze` and `flutter test` after the mechanical rename, before any manual pass.
- Manual run on a simulator/emulator across auth, home, prayer log, chat, and settings/about to confirm the theme reads correctly in both light and dark mode and nothing still says "Sakīnah".

## Out of scope

- Typography changes (see decision 4).
- Renaming the local project folder or git remote.
- Rewriting historical dated design docs.
- Windows/Linux desktop as a real build target (unrelated pre-existing limitation, see README).
