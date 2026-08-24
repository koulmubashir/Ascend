# Fourth prompt for Gemini

Your last attempt broke the silhouette, so this one locks it down. Send the whole
thing below the divider. Save the reply as **raw code, not through Google Docs**,
to `design/bodymap.html`, then run `./export-bodymaps.sh`.

---

Your last version broke the body outline — the shoulders grew spikes, muscle
shapes spilled outside the body, and the back became one large blob. I have
reverted to the previous working version.

This time, **do not touch the silhouette at all.** Only change the muscle shapes.

## Rule 1: copy this block character for character

This is the entire `<defs>` silhouette definition. Reproduce it exactly. Do not
adjust a single coordinate, do not "improve" the proportions, do not change the
head size, the neck, the hands or the feet. It works and it is not what needs
fixing.

```
<g id="front-half">
    <ellipse cx="420" cy="106" rx="34" ry="48" />
    <path d="M404,144 C404,165 388,175 365,188 L420,188 L420,144 Z" />
    <path d="M420,188 L365,188 C345,192 338,205 342,250 C342,320 362,380 362,400 C362,430 350,450 350,470 C350,488 385,500 420,500 Z" />
    <path d="M336,190 C320,192 310,230 302,290 C295,340 290,392 302,392 C314,392 328,340 336,290 C344,240 352,210 336,190 Z" />
    <path d="M302,385 C288,385 278,430 282,520 L296,520 C306,450 314,410 314,385 Z" />
    <path d="M282,518 C278,535 280,555 284,562 C290,562 296,545 296,518 Z" />
    <path d="M350,470 C345,530 355,600 385,640 L415,640 C410,580 410,520 420,500 C380,500 355,480 350,470 Z" />
    <path d="M385,635 C370,680 375,740 392,786 L412,786 C422,740 420,680 415,635 Z" />
    <path d="M392,782 L380,815 C380,820 415,820 415,815 L412,782 Z" />
</g>
```

Also keep unchanged: the `viewBox="260 40 920 800"`, the `figure-front` and
`figure-back` groups, both silhouette `<use>` layers with `stroke-width="5"`, the
`activeGradient` definition, and the entire `<script>` block.

## Rule 2: only subdivide the muscle layer

Replace only the shapes between `<!-- MUSCLE REGIONS LAYER -->` and `</svg>`.

Each muscle is currently one blob. Split it into its real heads and bellies.
`setRegions` applies the fill to *every* element with a matching `data-region`,
so five shapes sharing a region all light up together — use as many as you need.

| region | shapes per side | draw as |
| --- | --- | --- |
| `chest` | 2 | wide lower slab, narrow clavicular band above it |
| `abs` | 8 | 4 rows of 2, narrowing toward the bottom |
| `obliques` | 2 | flank strip plus a small serratus wedge under the armpit |
| `quads` | 4 | outer sweep, inner teardrop, long centre strip, narrow inner line |
| `hamstrings` | 3 | outer, inner and centre strips |
| `calves` | 2 | two heads, inner sitting slightly lower |
| `biceps` | 2 | long belly plus a short brachialis strip on the outer edge |
| `triceps` | 3 | long, lateral and medial heads |
| `forearm` | 2 | wide upper mass tapering into a narrow lower strip |
| `frontDelt`, `sideDelt`, `rearDelt` | 1 each | three wedges meeting over the shoulder joint |
| `traps` | 2 | upper diamond neck-to-shoulders, lower triangle down the spine |
| `lats` | 1 | wide under the armpit, tapering to a point at the waist — a wing, not a circle |
| `lowerBack` | 2 | two erector columns either side of the spine |
| `glutes` | 1 | one rounded mass per side |
| `adductors` | 2 | narrow inner-thigh strips |

## Rule 3: stay inside these boxes

Every shape must sit fully within the silhouette. These are the safe bounds for
the **left half of the front figure** (centred on x=420). Mirror each shape with
`transform="translate(840,0) scale(-1,1)"` for the right half.

| part | x range | y range |
| --- | --- | --- |
| chest | 348–418 | 230–300 |
| abs | 382–418 | 315–420 |
| obliques | 355–380 | 315–450 |
| deltoids | 300–355 | 190–260 |
| biceps | 302–345 | 240–340 |
| forearm | 282–312 | 390–515 |
| quads | 352–418 | 500–635 |
| adductors | 400–418 | 500–580 |
| calves | 375–418 | 640–780 |

For the **back figure**, take the same left-half shape and use
`transform="translate(600,0)"`, mirroring the other side with
`transform="translate(2040,0) scale(-1,1)"`. Back-figure safe bounds:

| part | x range | y range |
| --- | --- | --- |
| traps | 985–1018 | 190–290 |
| lats | 950–1018 | 240–400 |
| lowerBack | 995–1018 | 400–460 |
| glutes | 950–1018 | 460–540 |
| hamstrings | 950–1018 | 505–635 |
| triceps | 900–945 | 240–340 |
| rearDelt | 900–955 | 190–260 |
| forearm | 882–912 | 390–515 |
| calves | 975–1018 | 640–780 |

## Rule 4: the rest

- Muscle shapes get `fill="#dcdcdc"` and no stroke.
- Front-of-body muscles only on the front figure, back-of-body only on the back
  figure. `forearm`, `calves` and `sideDelt` appear on both.
- Add a few small gray shapes with **no** `data-region` for the neck, knees and
  shins so there are no bare white gaps. These stay gray permanently.
- No text anywhere in the SVG.
- Aim for 90–110 shapes total across both figures.

Return the complete file in one code block.
