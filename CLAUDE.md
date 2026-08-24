# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal gym tracker for iPhone and Apple Watch. Local-only, single-user, no
backend. Four Xcode targets over one shared Swift package.

## Commands

Run from the repo root.

```bash
# GymKit logic — fast, no simulator needed. Run this first for any GymKit change.
swift test --package-path Packages/GymKit

# A single test class or method
swift test --package-path Packages/GymKit --filter RepCounterTests
swift test --package-path Packages/GymKit --filter RepCounterTests/testCountsCleanReps

# Build the app (also builds and embeds the Watch app and both extensions)
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build the Watch app alone
xcodebuild -project GymTracker.xcodeproj -scheme GymTrackerWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' build

# Install and run, with debug launch hooks (DEBUG builds only)
xcrun simctl install <device-udid> \
  ~/Library/Developer/Xcode/DerivedData/GymTracker-*/Build/Products/Debug-iphonesimulator/GymTracker.app
xcrun simctl launch <device-udid> com.mubashirkoul.GymTracker -reset -autoplan -autostart
```

`-reset` clears stored data, `-autoplan` creates a 4-day plan, `-autostart`
begins the next workout. They skip onboarding when testing, and are compiled
out of release builds.

Regenerate the body-map artwork and the app icon (both are generated, not
hand-placed binaries):

```bash
design/export-bodymaps.sh          # rewrites the ten PNGs from design/bodymap.html
```

## Architecture

**`Packages/GymKit` holds everything testable without a device.** Models, the
session engine, scheduling, progression, notification planning, rep counting,
and the Watch sync payloads. It is pure Swift with no UIKit, SwiftUI, HealthKit
or ActivityKit, which is what lets 113 tests run in under a second from the
command line. Put logic here by default; put only rendering and system-framework
plumbing in the app targets.

**One session engine, two renderers.** `SessionEngine/SessionStateMachine.swift`
is the single source of truth for the exercise → rest → next-exercise flow. The
phone (`GymTracker/Session/SessionView.swift`) and the Watch
(`GymTrackerWatch/Session/WatchSessionView.swift`) both render its state and
send it events. Do not fork it per platform — that is what stops the two
implementations drifting.

**Ownership split.** The phone owns plan generation and history. Once a session
is running on the Watch, the Watch is authoritative: it logs locally and flushes
to the phone opportunistically, so a workout survives the phone being out of
range. `AppStore.applyWatchSet` deduplicates by `(exerciseID, setIndex)` because
a message can arrive twice after reachability recovers.

**Cross-process state goes through the App Group container**, not
`applicationSupportDirectory`. Extensions have their own containers, so a widget
writing to its own container can never be read by its host app. See
`SharedSessionCommands` and `WidgetSnapshot` in
`GymKit/LiveActivity/SharedContainer.swift`. Lock Screen buttons and Siri
shortcuts drop a command in that mailbox; the app replays it through the normal
state machine rather than mutating session state from another process.

**Types shared with an extension must live in GymKit.** An app extension cannot
export types back to its host app. `WorkoutActivityAttributes` is in GymKit
behind `#if canImport(ActivityKit) && os(iOS)` so the package still builds for
watchOS.

### Targets

| Target | Deployment | Notes |
|---|---|---|
| `GymTracker` | iOS 16.0 | Phone app |
| `GymTrackerWatch` | watchOS 9.0 | Embedded in the phone app |
| `GymTrackerWidget` | iOS 16.1 | Live Activity + home screen widget |
| `GymTrackerWatchWidget` | watchOS 9.0 | Complication, embedded in the Watch app |

Every extension needs a **non-empty** entitlements file. An empty one does not
force code signing, and the extension then builds unsigned while its parent is
ad-hoc signed — which fails with "Embedded binary is not signed with the same
certificate as the parent app".

## Decisions that look like bugs but are not

- **Persistence is a Codable JSON snapshot, not Core Data.** Confined to
  `load()`/`save()` in `GymTracker/App/AppStore.swift`.
- **Vitals are labelled by how they are obtained.** Heart rate is live during a
  workout; blood oxygen is a periodic spot check, usually suppressed mid-workout;
  wrist temperature is overnight only. Never present them as equivalent.
- **Available vitals are inferred from data actually arriving**, not from a Watch
  model check — there is no reliable API for the latter.
- **`BodyMapKey.bestMatch` scores overlap ÷ union**, not raw overlap. Raw overlap
  makes `fullBody` win everything, so a push day lights up the whole body.
- **Bodyweight sets contribute zero volume**, and volume is attributed in full to
  every region an exercise trains rather than divided between them.
- **`RepCounter`'s baseline is a low percentile over a multi-rep window.** A mean
  or median tracks the movement itself and the threshold can never be crossed.
- **Rep counting never guesses which exercise you are doing** — the plan already
  knows, and wrist-based classification is the unreliable part.
- **iCloud is a backup, not sync.** Last writer wins; concurrent edits are not
  reconciled.
- **Live Activity updates fire only on real state changes.** The rest countdown
  uses `Text(timerInterval:)` so the system ticks it — per-second `Activity
  .update()` calls get throttled and freeze.

## Known gaps

- Plan edits apply to a single `ScheduledWorkout`, not the `TrainingDay`
  template, so next week's copy of the same day is unchanged.
- The Watch advances sets with a button; swipe is used for paging between
  screens.
- No superset support in the session engine.
- The iCloud entitlement is deliberately absent — see `ICLOUD-SETUP.md`.
- `_attic/` holds an unused parallel UI implementation, kept for reference.

## Verification

Simulator covers onboarding, planning, the session flow, nutrition, charts and
plan editing. These need a physical device and are unverified: Live Activity
presentation, HealthKit vitals, Watch → phone sync, notification delivery,
iCloud, and rep-counting thresholds (validated only against synthetic signals).

Live Activities do not reliably present in the simulator even when ActivityKit
accepts the request — check the log for `com.apple.activitykit` before assuming
the code is wrong. The simulator framebuffer can also freeze and return
identical screenshots; if the clock is not advancing between captures, reboot it.
