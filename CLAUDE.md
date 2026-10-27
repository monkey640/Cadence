# Cadence

SwiftUI iOS 18+ readiness app for teen sprinters (roughly 14–18). Every morning it
reads recovery from Apple Health, scores it, and scales that day's training to match.
Everything runs on device — no account, no network, no analytics.

Bundle id `net.adnanahmad.Cadence` · v1.0 (1) · deployment target iOS 18.0.

## Locked decisions — do not relitigate

- **Design language: "timing board."** Dark, monospaced numerals (`.timingBoard`),
  lane-line dividers, flat registers — NOT card stacks. `TodayView` is the reference
  implementation; every other screen answers to it.
- **Dopamine at achievement moments ONLY.** Big motion for PRs and the once-daily
  reveal; restraint everywhere else. Every animation gated on
  `accessibilityReduceMotion`.
- **`plans.json` is static vetted data — NEVER generated or modified by AI.** This is
  prescriptive training content for minors. Templates are hand-authored and
  human-reviewed. If plans need to change, the user or a coach supplies the content;
  you wire it in and validate it against the `PlanTemplate` schema.
- **Engine weights and thresholds are coach-review-pending — do not tune them.**
  `ReadinessConfig.phoneSignalWeightsAreDraft` is `true` and the three phone-only
  signals surface a draft notice in their detail view. Flip the flag to remove the
  notice; don't change the numbers.
- **`Cadence.entitlements`: ONLY `com.apple.developer.healthkit = true` plus the app
  group.** Never the `.access` array — personal teams reject it.
- **CadenceCore stays pure.** No UI, no HealthKit, no heavy Foundation deps.
- **Swift 6 strict concurrency is ON.** Known patterns: store Activity IDs, not
  `Activity` refs; `nonisolated animatableData`; `Sendable` catalogs with `@Sendable`
  closures. `nonisolated(unsafe)` on `Theme.current` is deliberate — leave it.
- **Never mark an item done without visual proof or a passing check you have read.**
  A missing shared scheme once made `xcodebuild test` print TEST SUCCEEDED while
  running zero tests.
- The user has declined version control for this project. Don't suggest git.

## Layout

```
CadenceApp/            SwiftUI + SwiftData + HealthKit (64 files)
  Screens/             Today · Plan · Trends · History · Settings
                       + Onboarding · CheckIn · Session · Signals
  Services/            HealthKit, ReadinessCoordinator, LiveReadinessMonitor,
                       personalization, notifications, WidgetBridge, CSV export
  Models/              6 @Model types (AthleteProfile, DailyReadiness, CheckIn,
                       TrainingSession, PersonalRecord, PlanAdjustment)
  Resources/           plans.json · adjustment_ranges.json · movement_glossary.json
  AppIcon.icon         Icon Composer bundle; source of truth is ~/Downloads/cadnece.icon
Packages/CadenceCore/  pure Swift: Scoring/ Personalization/ Scaling/ (28 files)
CadenceWidgets/        home-screen widget + rest-timer Live Activity
CadenceTests/          app-level integration tests
Marketing/AppStore/    store screenshots at 1320×2868
```

## Build and test

The local toolchain is quirky: `swift build` does not work at the repo root, and
`xcodebuild` needs a device id rather than a name (`-destination 'platform=iOS
Simulator,name=...'` fails to resolve). Disk is tight — always log to a file and keep
DerivedData out of the default location.

```bash
# Build / test the app (substitute a booted simulator's id from `xcrun simctl list devices`)
xcodebuild -project Cadence.xcodeproj -scheme Cadence \
  -destination 'id=<SIM_UDID>' -derivedDataPath /private/tmp/cadence-dd \
  build > /private/tmp/cadence-build.log 2>&1

# CadenceCore unit tests (93 tests) — fast, run these first
cd Packages/CadenceCore && swift test
```

Screenshots and demo states use `#if DEBUG` env hooks, passed through simctl with the
`SIMCTL_CHILD_` prefix: `CADENCE_DEMO=1` plus `_TAB`, `_VERDICT` (push|hold|backOff),
`_PLAYER` (1|rest), `_MEET=<days>`, `_RECAP`, `_NOCHECKIN`, `_BASELINING`, `_PLANDONE`,
`_WEEKLY`, `_BULK`. The seed persists in the store, so **uninstall between shots** or a
stale verdict carries over, and allow ~13s for the first render.

## Readiness engine

```
subscore   = clamp(72 + z × 20, 0…100)      # z vs the athlete's own rolling baseline
score      = Σ(subscore × weight) / Σ(weight)
multiplier = 0.5 + 0.5 × (score / 100)      # floor 0.50 — never zero
verdict    = push ≥ 0.83 · hold ≥ 0.70 · else back off
```

Centred at 72, not 50, on purpose: a typical day should read as normal, and only
below-baseline signals pull toward caution. This is an anti-overtraining tool.

A push verdict is promoted to the full `maxMultiplier` (100%), because "push" means the
whole session. Safe by construction: the conservative cap (0.80) and low-confidence cap
(0.70) both sit below the push threshold (0.83), so a capped day can never be a push.

Weights: HRV 0.35, sleep 0.15, sleep quality 0.15, RHR 0.12, respiratory 0.08, load
0.08, wrist temp 0.07 (these seven sum to 1.00) — plus wellness 0.30, CMJ 0.12,
finger-tap 0.06, which are DRAFT and deliberately break the sum.

## Living readiness

Wearables sync late (a Garmin uploading at noon left the morning score stale all day).
HealthKit observer queries with hourly background delivery drive a headless recompute
from a background `ModelContext` via `LiveReadinessMonitor`. The metric day runs
**6 PM → 6 PM** so an overnight reading lands on the right date. Starting a session
freezes the verdict so the plan can't shift under an athlete mid-workout.
`DailyReadiness.updatedAt` must stay `Date?` — `@Model` rejects a `.now` default.

## Current state

Code and assets are complete. 98 tests pass (93 core + 5 app). Builds clean in
**Release** with zero warnings. Verified on a physical device: install, widget on the
home screen, app icon in all appearances.

`Info.plist` is a real file at the repo root (`GENERATE_INFOPLIST_FILE = NO`), so
`INFOPLIST_KEY_*` build settings are **inert** for the app target — edit the file
directly. It declares `ITSAppUsesNonExemptEncryption = false`, so App Store Connect
won't ask about export compliance on every upload.

Only three events have vetted plans (100m, 200m, 400m). The event picker derives its
options from `plans.json` at runtime via `PlanLibraryLoader.plannedEvents`, so Hurdles
and Relay are hidden until real templates land — and appear automatically when they do.
Existing profiles on those events keep their selection via `selectableEvents(including:)`.

Never observed on real data: the rest-timer Live Activity, and the late-sync recompute.
Baselines need 7+ days of real use.

Remaining work is all owner-side: paid Apple Developer account, a hosted privacy policy
URL (`PRIVACY.md` is written), a support URL, the App Store listing and privacy
questionnaire (answer "no data collected"), and a real week of use.
