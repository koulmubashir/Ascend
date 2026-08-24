# Prompt for Gemini

Copy everything below the line into Gemini. Save its reply as
`design/bodymap.html` and tell Claude — it will export the ten PNGs.

---

Build me a single self-contained HTML file that renders an anatomical muscle map
as inline SVG. No external files, no CDN links, no images — everything inline in
one file. I will screenshot it programmatically, so precision matters more than
polish.

## What it draws

A **front view and a back view side by side**, front on the left, both in one SVG.
A stylised human figure — head, neck, torso, arms hanging at the sides with a
visible gap from the body, legs, feet. Smooth organic curves, not boxes or
capsules.

Two layers:

1. **Silhouette** — one continuous smooth outline of the whole body. Thin stroke
   `#a9a5a1` at about 1.5px, fill `#fdfdfc`.
2. **Muscle regions** — separate rounded, organic shapes sitting inside the
   silhouette, no stroke. Anatomically placed and clearly readable as individual
   muscles (pecs as two rounded slabs, abs as a 3×2 grid, lats as large wings
   tapering from armpit to waist, deltoids as caps over the shoulder joints, and
   so on).

Style reference: flat, clean, modern fitness-app illustration. No shading, no
gradients on the silhouette, no textures, no outlines on the muscle shapes.

**Absolutely no text anywhere in the SVG.** No muscle names, no labels, no
titles, no captions, no view labels. The app draws its own labels.

## Colours

- Inactive muscle: `#dcdcdc`
- Active muscle: radial gradient, `#ffa04a` at the centre to `#f2571b` at the edge
- Page background: `#f7f7f7`

## Muscle regions

Every one of these must be its own shape, or its own left/right pair, each
carrying a `data-region` attribute with exactly this name:

`chest`, `frontDelt`, `sideDelt`, `rearDelt`, `traps`, `lats`, `lowerBack`,
`biceps`, `triceps`, `forearm`, `abs`, `obliques`, `quads`, `hamstrings`,
`glutes`, `calves`, `adductors`

Front-of-body muscles (chest, abs, obliques, quads, adductors, biceps, frontDelt)
appear on the front figure. Back-of-body muscles (lats, traps, lowerBack, glutes,
hamstrings, rearDelt, triceps) appear on the back figure. Forearms, calves and
sideDelt appear on both.

## Presets

Expose a global function `window.setPreset(name)` that highlights the regions for
a preset and greys out everything else. Also read `?preset=NAME` from the URL on
load and apply it, defaulting to `rest`.

| preset | highlighted regions |
|---|---|
| `rest` | none |
| `push` | chest, frontDelt, triceps |
| `pull` | lats, traps, rearDelt, biceps, forearm |
| `legs` | quads, hamstrings, glutes, calves, adductors |
| `chest` | chest, frontDelt |
| `back` | lats, traps, lowerBack |
| `shoulders` | frontDelt, sideDelt, rearDelt, traps |
| `arms` | biceps, triceps, forearm |
| `core` | abs, obliques |
| `fullBody` | all of them |

Also expose `window.setRegions(["chest","triceps"])` to highlight an arbitrary
list, so I can render one specific exercise later.

## Layout requirements

These matter because I am screenshotting the page:

- The SVG must be the only visible content — no headings, no buttons, no padding
  around it, no scrollbars.
- Wrap it in a container exactly **1440×870 CSS pixels**, positioned at the very
  top-left of the page, `margin: 0`.
- The figures must sit at exactly the same position and scale regardless of which
  preset is active, so the ten exports line up perfectly when swapped.
- Applying a preset must only change fill colours. It must never move, resize or
  re-render any shape.

Give me the complete file in one code block, ready to save and open.
