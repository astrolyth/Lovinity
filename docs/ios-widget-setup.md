# iOS home-screen widget — remaining Xcode setup

Everything the widget needs is written and committed **except one step that has
to happen in Xcode**: creating the widget extension *target*.

## Why this step is not scripted

An Xcode target lives in `ios/Runner.xcodeproj/project.pbxproj` — a file of
generated 24-character UUIDs linking targets, build phases, file references and
configuration lists. Adding a target by hand means inventing consistent UUIDs
across a `PBXNativeTarget`, its sources/frameworks/resources build phases, a
`PBXContainerItemProxy`, a target dependency, an *Embed App Extensions* copy
phase on Runner, and two build configurations.

Getting any of it subtly wrong does not fail loudly. It produces a project that
opens, builds, and ships an app with a broken or missing extension — and the
usual symptom is a widget that never appears in the gallery, with nothing in any
log to explain it. Worse, a malformed `project.pbxproj` can make the whole iOS
project unopenable, which is a bad thing to hand someone unasked.

Xcode generates all of this correctly in about a minute. That is the right tool
for this job.

## What is already done

| Piece | State |
|---|---|
| `ios/LovinityWidget/LovinityWidget.swift` | Written — timeline provider + SwiftUI view |
| `ios/LovinityWidget/LovinitySnapshot.swift` | Written — decodes the payload from the App Group |
| `ios/LovinityWidget/Info.plist` | Written — declares the WidgetKit extension point |
| `ios/LovinityWidget/LovinityWidget.entitlements` | Written — App Group |
| `ios/Runner/Runner.entitlements` | Updated — same App Group on the app side |
| Dart publisher | Done — `lib/features/widget/` |
| Android widget | Done and building |

## The step

1. Open the workspace (not the project):

   ```bash
   open ios/Runner.xcworkspace
   ```

2. **File → New → Target… → Widget Extension.**
   - Product Name: **`LovinityWidget`** — must match `kIosWidgetName` in
     `lib/features/widget/domain/widget_providers.dart`, and the `kind` string
     in `LovinityWidget.swift`.
   - Uncheck **Include Live Activity** and **Include Configuration Intent**.
     The widget is static; a configuration intent adds an unused intent
     definition and an extra target.
   - When prompted to activate the new scheme, choose **Activate**.

3. Xcode generates its own `LovinityWidget.swift`, `Info.plist` and asset
   catalog inside the new group. **Delete the generated `.swift` file** (Move to
   Trash) and instead add the two files already written here:
   - Right-click the `LovinityWidget` group → *Add Files to "Runner"…*
   - Select `ios/LovinityWidget/LovinityWidget.swift` and
     `ios/LovinityWidget/LovinitySnapshot.swift`
   - Ensure **Target Membership** is the `LovinityWidget` target only — not
     Runner. Adding them to Runner too causes a duplicate `@main` symbol.

4. Point the target at the committed `Info.plist` and entitlements:
   - Select the `LovinityWidget` target → **Build Settings**
   - `INFOPLIST_FILE` → `LovinityWidget/Info.plist`
   - `CODE_SIGN_ENTITLEMENTS` → `LovinityWidget/LovinityWidget.entitlements`

5. Enable the App Group on **both** targets:
   - `Runner` target → **Signing & Capabilities** → **+ Capability** → *App
     Groups* → tick `group.com.lovinity.lovinity`
   - `LovinityWidget` target → same capability → same group

   Both sides are required. With the group on only one target everything builds
   and runs, and the widget silently reads nothing forever — there is no error
   to follow, so check this first if the widget looks dead.

6. Set the deployment target of `LovinityWidget` to match Runner (WidgetKit
   needs iOS 14+; the `containerBackground` path is guarded for iOS 17+).

7. Build and run the Runner scheme on a device or simulator, open the app once
   so a snapshot is published, then long-press the home screen → **+** →
   *Lovinity*.

## Verifying the data path

The widget only ever reads what the app wrote. If it shows *"Open Lovinity"*
after the app has been used:

- Confirm the App Group string matches in all three places:
  `Runner.entitlements`, `LovinityWidget.entitlements`, and
  `kWidgetAppGroupId` in `widget_providers.dart`.
- Confirm the extension's Product Name is exactly `LovinityWidget`;
  `HomeWidget.updateWidget(iOSName:)` targets it by that name, and a mismatch
  means the reload request goes nowhere.

## Design notes worth keeping

- **Prayer times are recomputable offline.** Coordinates and calculation method
  travel in the snapshot, so a future revision can recompute the next prayer
  natively instead of relying on the last published value. Only the check-in
  counts and the verse genuinely need the app to have run.
- **The widget never extrapolates counts.** The timeline supplies future entries
  so the countdown stays accurate, but each entry carries the *same* snapshot.
  Guessing at prayer counts would mean the widget inventing them, which is the
  one thing this surface must not do.
- **Both timezones travel with the counts.** A widget has no day toggle and no
  room to explain itself, so an unqualified "Aisha 0/5" at 1am her time reads as
  neglect. The attribution line is rendered only when the two spouses are
  actually on different calendar days.
