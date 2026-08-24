# Body map export spec

Ten images. Same figure, same position, same scale in every one — only the orange
highlighting changes. Use `_sample-upper-body.png` as the framing reference.

## Rules for every image

- **Front and back side by side**, front on the left. Both views in a single file.
- **No text.** No anatomy labels, no titles, no captions.
- **No device chrome.** No status bar, no home indicator, no toolbar.
- Identical figure position and scale across all ten, so images don't jump when swapped.
- Background transparent, or near-white `#f7f7f7`.
- Inactive muscle: `#dcdcdc`. Active muscle: radial gradient, `#ffa04a` center → `#f2571b` edge.
- 1440×870 or larger.

## The ten files

| File | Highlight |
|---|---|
| `rest.png` | nothing — all gray |
| `push.png` | chest, front delts, triceps |
| `pull.png` | lats, traps, rear delts, biceps, forearms |
| `legs.png` | quads, hamstrings, glutes, calves, adductors |
| `chest.png` | chest, front delts |
| `back.png` | lats, traps, lower back |
| `shoulders.png` | front, side and rear delts, traps |
| `arms.png` | biceps, triceps, forearms |
| `core.png` | abs, obliques |
| `full-body.png` | everything |

## Delivery

Drop the files into this folder (`design/assets/bodymap/`) using exactly these names.

If it's easier to produce one contact sheet instead, export it as a 5×2 grid in the
order above (rest, push, pull, legs, chest / back, shoulders, arms, core, full-body)
with no labels or chrome, and run:

```
design/slice-bodymaps.sh <sheet.png>
```
