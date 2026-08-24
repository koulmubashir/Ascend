#!/usr/bin/env python3
"""Check that the artwork and the Swift model agree.

Two things can silently drift apart:
  - the `data-region` shapes in bodymap.html vs MuscleRegion in Swift
  - the `presets` map in bodymap.html vs BodyMapKey.regions in Swift

When they do, the app highlights muscles the labels do not mention (or worse,
the other way round). Run this after editing either side.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent
html = (root / "bodymap.html").read_text()
swift = (root.parent / "Packages/GymKit/Sources/GymKit/Models/MuscleRegion.swift").read_text()

problems = []

def enum_body(name):
    """Source of one top-level enum, so `MuscleGroup` and `BodyMapKey` -
    which declare members of the same name - are never confused."""
    m = re.search(rf"public enum {name}[^{{]*\{{(.*?)\n\}}", swift, re.S)
    if not m:
        sys.exit(f"could not find enum {name}")
    return m.group(1)

# --- regions -------------------------------------------------------------
svg_regions = set(re.findall(r'data-region="([A-Za-z]+)"', html))
swift_regions = set(re.findall(r"^    case (\w+)$", enum_body("MuscleRegion"), re.M))

if svg_regions - swift_regions:
    problems.append(f"in SVG but not in MuscleRegion: {sorted(svg_regions - swift_regions)}")
if swift_regions - svg_regions:
    problems.append(f"in MuscleRegion but not drawn: {sorted(swift_regions - svg_regions)}")

# --- presets -------------------------------------------------------------
def swift_presets():
    body = re.search(
        r"public var regions: Set<MuscleRegion> \{(.*?)\n    \}",
        enum_body("BodyMapKey"), re.S
    )
    out = {}
    for key, val in re.findall(r"case \.(\w+):\s*return \[([^\]]*)\]", body.group(1)):
        out[key] = {r.strip().lstrip(".") for r in val.split(",") if r.strip()}
    return out

def html_presets():
    body = re.search(r"const presets = \{(.*?)\n        \};", html, re.S).group(1)
    out = {}
    for key, val in re.findall(r"'(\w+)':\s*\[([^\]]*)\]", body):
        out[key] = {r.strip().strip("'") for r in val.split(",") if r.strip()}
    return out

sp, hp = swift_presets(), html_presets()
# fullBody is "everything" on both sides; compare against the full region set.
sp["fullBody"] = swift_regions
for key in sorted(set(sp) | set(hp)):
    if key not in sp:
        problems.append(f"preset '{key}' in SVG but not in BodyMapKey")
    elif key not in hp:
        problems.append(f"preset '{key}' in BodyMapKey but not in SVG")
    elif sp[key] != hp[key]:
        problems.append(
            f"preset '{key}' differs - swift only {sorted(sp[key] - hp[key])}, "
            f"svg only {sorted(hp[key] - sp[key])}"
        )

if problems:
    print("PARITY FAILED")
    for p in problems:
        print("  -", p)
    sys.exit(1)

print(f"parity ok - {len(svg_regions)} regions, {len(hp)} presets")
