# Follow-up prompt for Gemini

Send this back to Gemini **in the same chat**, so it edits the file it already
wrote. Attach `bodymap.fixed.html` if it has lost context.

**Then save its reply as raw code — not through Google Docs.** The last file came
back as a Docs export with the HTML escaped as text, which renders blank. Use
"Copy code", paste into a plain text editor, save as `design/bodymap.html`.

---

The structure is exactly right — keep the JavaScript, the `data-region`
attributes, the presets, `setPreset`, `setRegions` and the `?preset=` URL handling
completely unchanged. They all work.

The problem is purely the SVG geometry. Two things are wrong:

1. **The silhouette paths are broken.** Both figures use one long path made of the
   same curve segment repeated over and over, which draws a scribble instead of a
   body. There is no recognisable outline.
2. **The muscle shapes are plain ellipses in roughly random places**, and they sit
   at coordinates that do not line up with the silhouette.

Redraw all the shapes. Here is how.

## Build the silhouette from separate simple shapes

Do not attempt one continuous path for the whole body — that is what failed.
Instead draw each part as its own simple shape:

head (ellipse), neck (rounded rect), torso (one path), upper arm, forearm, hand,
thigh, shin, foot — draw the left side only, then mirror it for the right with
`transform="translate(840,0) scale(-1,1)"`.

Put all of these in a `<g id="figure-front">`, then render that group **twice**:

```html
<use href="#figure-front" fill="#a9a5a1" stroke="#a9a5a1" stroke-width="5" stroke-linejoin="round"/>
<use href="#figure-front" fill="#fdfdfc" stroke="none"/>
```

The first pass draws a fat outline around the union of all the parts; the second
fills the interior and hides the seams where parts overlap. The result reads as
one clean continuous silhouette. Do the same for `#figure-back`.

## Use these coordinates

The viewBox stays `0 0 1440 870`. Front figure centred on x=420, back figure
centred on x=1020. Both span y=60 to y=820.

Front figure landmarks (mirror x around 420):

| part | position |
| --- | --- |
| head | ellipse cx 420, cy 106, rx 34, ry 48 |
| neck | x 404–436, y 144–180 |
| shoulder line | y 190, from x 330 to x 510 |
| chest widest | y 250, x 342–498 |
| waist narrowest | y 400, x 362–478 |
| hip | y 470, x 350–490 |
| crotch | y 500 |
| knee | y 640 |
| ankle | y 786 |
| foot | y 786–820 |
| shoulder joint | (336, 200) |
| elbow | (302, 392) |
| wrist | (288, 520) |
| fingertips | (284, 562) |

Arms hang at the sides with a clear gap between the inner arm and the torso.
The back figure uses the same skeleton, centred on x=1020.

## Muscle shapes

Each muscle is a rounded organic shape placed inside the silhouette, no stroke,
sitting on top of the filled body. Make them read as actual muscles:

- **chest** — two rounded slabs side by side, y 232–300, meeting near the centre line
- **abs** — a 3 rows × 2 columns grid of rounded rects, y 320–430, about 30 wide each
- **obliques** — narrow tapered shapes flanking the abs
- **lats** — large wings, wide at the armpit and tapering down to the waist. This is
  the signature back shape; do not draw them as ovals
- **traps** — a diamond/kite between the neck and the shoulder blades
- **frontDelt / sideDelt / rearDelt** — caps sitting over the shoulder joint
- **biceps / triceps** — long rounded shapes filling the upper arm
- **forearm** — long tapered shapes below the elbow
- **quads / hamstrings** — large shapes filling the thigh
- **glutes** — two large rounded shapes at the top of the back of the legs
- **calves** — shapes on the lower leg
- **adductors** — narrow shapes on the inner thigh
- **lowerBack** — two short columns either side of the spine, below the lats

Every muscle must sit fully inside the body outline. Nothing floating outside.

Still no text anywhere in the SVG.
