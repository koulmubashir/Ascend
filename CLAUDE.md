# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal gym tracker for iPhone and Apple Watch. Local-only, single-user, no
backend. Four Xcode targets over one shared Swift package.

## Commands

Run from the repo root.

```bash
# AscendKit logic — fast, no simulator needed. Run this first for any AscendKit change.
swift test --package-path Packages/AscendKit

# A single test class or method
swift test --package-path Packages/AscendKit --filter RepCounterTests
swift test --package-path Packages/AscendKit --filter RepCounterTests/testCountsCleanReps

# Build the app (also builds and embeds the Watch app and both extensions)
xcodebuild -project Ascend.xcodeproj -scheme Ascend \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build the Watch app — use the script, not xcodebuild directly.
# Incremental builds leave the complication unsigned and then fail; the script
# deletes the stale appex first. See Known gaps.
./build.sh AscendWatch

# Install and run, with debug launch hooks (DEBUG builds only)
xcrun simctl install <device-udid> \
  ~/Library/Developer/Xcode/DerivedData/Ascend-*/Build/Products/Debug-iphonesimulator/Ascend.app
xcrun simctl launch <device-udid> com.mubashirkoul.Ascend -reset -autoplan -autostart
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

**`Packages/AscendKit` holds everything testable without a device.** Models, the
session engine, scheduling, progression, notification planning, rep counting,
and the Watch sync payloads. It is pure Swift with no UIKit, SwiftUI, HealthKit
or ActivityKit, which is what lets 120 tests run in under a second from the
command line. Put logic here by default; put only rendering and system-framework
plumbing in the app targets.

**One session engine, two renderers.** `SessionEngine/SessionStateMachine.swift`
is the single source of truth for the exercise → rest → next-exercise flow. The
phone (`Ascend/Session/SessionView.swift`) and the Watch
(`AscendWatch/Session/WatchSessionView.swift`) both render its state and
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
`AscendKit/LiveActivity/SharedContainer.swift`. Lock Screen buttons and Siri
shortcuts drop a command in that mailbox; the app replays it through the normal
state machine rather than mutating session state from another process.

**Types shared with an extension must live in AscendKit.** An app extension cannot
export types back to its host app. `WorkoutActivityAttributes` is in AscendKit
behind `#if canImport(ActivityKit) && os(iOS)` so the package still builds for
watchOS.

### Targets

| Target | Deployment | Notes |
|---|---|---|
| `Ascend` | iOS 16.0 | Phone app |
| `AscendWatch` | watchOS 9.0 | Embedded in the phone app |
| `AscendWidget` | iOS 16.1 | Live Activity + home screen widget |
| `AscendWatchWidget` | watchOS 9.0 | Complication, embedded in the Watch app |

Every extension needs a **non-empty** entitlements file. An empty one does not
force code signing, and the extension then builds unsigned while its parent is
ad-hoc signed — which fails with "Embedded binary is not signed with the same
certificate as the parent app".

## Decisions that look like bugs but are not

- **Persistence is a Codable JSON snapshot, not Core Data.** Confined to
  `load()`/`save()` in `Ascend/App/AppStore.swift`.
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
- **Plan edits default to the whole series.** `PlanEditor` writes through to the
  `WorkoutPlan` template and every *upcoming* instance, but never to completed,
  missed or makeup days — history records what you did, not what the plan says
  now.
- **Live Activity updates fire only on real state changes.** The rest countdown
  uses `Text(timerInterval:)` so the system ticks it — per-second `Activity
  .update()` calls get throttled and freeze.

## Known gaps

- **Incremental Watch builds fail to sign `AscendWatchWidget.appex`**, and the
  stale unsigned artifact then makes every later build fail identically. Use `./build.sh`,
  which removes it first. Affects the Ascend scheme too, since the phone app
  embeds the Watch app. A non-empty entitlements file,
  `CODE_SIGN_IDENTITY[sdk=watchsimulator*] = "-"`, and `CODE_SIGNING_REQUIRED`
  were each tried and none fixed it; root cause not established.
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
