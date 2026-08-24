# Third prompt for Gemini

Send in the same chat. Save the reply as raw code (**not** through Google Docs)
to `design/bodymap.html`, then run `./export-bodymaps.sh`.

---

Good progress — the silhouette is a real body now and the preset wiring works.
Keep all the JavaScript, the `data-region` attributes, `setPreset`, `setRegions`
and the `?preset=` handling exactly as they are.

Two things still need work: **muscle detail** and **proportions**. Right now the
figure reads as a mannequin with a few pads stuck on it. It should read as an
anatomy chart, where gray muscle shapes cover nearly the whole body.

## 1. Many shapes per muscle, not one

This is the biggest difference. `setRegions` already applies the fill to *every*
element carrying a matching `data-region`, so a muscle can be drawn as five
separate shapes and they will all light up together. Use that.

Split each muscle into its actual heads and bellies:

| region | shapes per side | draw as |
| --- | --- | --- |
| `chest` | 2 | a large lower slab plus a narrower upper clavicular band above it |
| `abs` | 8 | a 4×2 grid, narrowing toward the bottom |
| `obliques` | 2 | a flank strip plus a small serratus wedge under the armpit |
| `quads` | 4 | outer sweep, inner teardrop, long centre strip, narrow inner line |
| `hamstrings` | 3 | outer, inner and centre strips |
| `calves` | 2 | two heads, inner sitting slightly lower than outer |
| `biceps` | 2 | long belly plus a short brachialis strip on the outer edge |
| `triceps` | 3 | long, lateral and medial heads |
| `forearm` | 2 | a wide upper mass tapering into a narrow lower strip |
| `frontDelt` / `sideDelt` / `rearDelt` | 1 each | three distinct wedges meeting over the shoulder joint |
| `traps` | 2 | upper diamond from neck to shoulders, plus a lower triangle down the spine |
| `lats` | 1 | wide under the armpit, tapering to a point at the waist — a wing, not a crescent |
| `lowerBack` | 2 | two erector columns either side of the spine |
| `glutes` | 1 | one large rounded mass per side |
| `adductors` | 2 | two narrow inner-thigh strips |

Also add small unnamed gray shapes (no `data-region`, so they stay permanently
gray) for the neck, the knees and the shins, so there are no bare white gaps.

Aim for roughly **90–110 shapes total** across both figures. Right now there are
about 40, which is why it looks sparse.

## 2. Fix the proportions

- **Head is too big.** Reduce to `rx="28" ry="38"`. A standing figure should be
  about 7.5 heads tall.
- **Neck is too wide and too long.** Narrow it to about 26 units wide and shorten
  it so the shoulders start higher.
- **Waist barely tapers.** The torso is nearly rectangular. Shoulders should be
  clearly wider than the waist, with the narrowest point around y=400, then
  flaring back out at the hips.
- **Hands are flat paddles.** Give them a visible thumb bump on the inner edge
  and a taper toward the fingertips.
- **Feet are plain wedges.** Add an arch on the inner edge and a slight toe
  taper.
- **Line weight is heavy.** Reduce the silhouette stroke from 5 to about 3.

## 3. Keep everything else

- Same `viewBox="260 40 920 800"`, same two figures centred on x=420 and x=1020.
- Same colours: inactive `#dcdcdc`, active `url(#activeGradient)`, outline
  `#a9a5a1`, background `#f7f7f7`.
- Every muscle shape must sit fully inside the silhouette.
- Muscle shapes get no stroke.
- Still no text anywhere in the SVG.
