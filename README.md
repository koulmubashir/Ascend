# Ascend

A personal gym tracker for iPhone and Apple Watch. Local-only, single-user, no
backend, no account.

It plans your training week, guides you through each session on your wrist,
tells you what weight to aim for next time, and moves the workouts you miss
rather than letting them pile up.

## What it does

**Plans and reschedules.** Pick how many days a week you train and it builds a
split. Miss a session and it works out what you did not finish and slots the
remainder into your next free rest day — falling back to next week if there is
no room, and giving up after a week rather than growing a backlog you will never
clear.

**Runs the session from your wrist.** The Watch shows the exercise, the muscles
it trains, and the set you are on. Swipe to log a set, feel a haptic when the
rest is over. The phone can stay in a locker: the Watch holds the plan, logs
locally, and syncs when the phone is back in range.

**Tells you what to lift.** Every set you log feeds a progression engine that
suggests your next weight and reps, detects personal bests, and shows whether an
exercise is actually trending up. There is a plate calculator and a warm-up ramp
snapped to weights your plates can actually make.

**Shows you what you have neglected.** A body map highlights the muscles each
session trains, and a four-week volume chart names the groups you have quietly
stopped training.

**Tracks the rest of it, if you want.** Heart rate during workouts, protein and
water, body measurements, deload weeks. Every one of these is off until you turn
it on, and each asks for its own permission at the moment you enable it — never
in a batch at first launch.

## Honest about the hardware

Apple Watch vitals are not equivalent to each other, and the app does not
pretend otherwise:

| | Reality |
|---|---|
| Heart rate | Genuinely live during a workout |
| Blood oxygen | A periodic spot check, usually suppressed mid-workout |
| Wrist temperature | Measured overnight only, never during training |

Each is labelled with how it was actually obtained. Rep counting counts
repetitions and notices when a set ends — it never guesses *which* exercise you
are doing, because the plan already knows and wrist-based classification is the
unreliable part.

## Building

Requires Xcode 26 or later.

```bash
# Logic tests — 120 of them, no simulator needed
swift test --package-path Packages/AscendKit

# The app, which also builds and embeds the Watch app and both extensions.
# Use the script rather than xcodebuild directly — see "Known issues".
./build.sh

# The Watch app on its own
./build.sh AscendWatch
```

## Layout

| | |
|---|---|
| `Packages/AscendKit` | Everything testable without a device: models, the session engine, scheduling, progression, rep counting, sync payloads |
| `Ascend` | iPhone app |
| `AscendWatch` | watchOS app |
| `AscendWidget` | Lock Screen Live Activity and home screen widget |
| `AscendWatchWidget` | Watch face complication |
| `design` | Body-map artwork and the app icon, generated from HTML rather than checked in as opaque binaries |

The session engine lives in AscendKit and is rendered by both the phone and the
Watch, so there is one implementation of the exercise → rest → next-exercise
flow rather than two that drift apart.

## Status

Verified in the simulator: onboarding, plan generation and editing, the session
flow, nutrition, measurements, charts, and phone → Watch sync.

Not yet verified, because they need real hardware: Live Activity presentation,
HealthKit vitals, Watch → phone sync, notification delivery, iCloud backup, the
complication, and rep-counting thresholds — which have only been validated
against synthetic signals, not a real wrist.

## Known issues

**Incremental builds fail to sign the complication.** Any incremental build
leaves `AscendWatchWidget.appex` unsigned, and validation then fails; the stale
artifact persists so every later build fails the same way. This affects the
`Ascend` scheme too, because the phone app embeds the Watch app which embeds the
complication. `build.sh` deletes it first. Giving the extension a non-empty entitlements
file, pinning `CODE_SIGN_IDENTITY`, and forcing `CODE_SIGNING_REQUIRED` were all
tried and none fixed it. Root cause not established.

**iCloud is a backup, not sync.** Last writer wins; concurrent edits on two
devices are not reconciled. Its entitlement is also deliberately absent — see
`ICLOUD-SETUP.md`.

**No supersets.** The session engine cannot express back-to-back exercises with
a shared rest.
