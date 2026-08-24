#!/bin/bash
# Slices the 5x2 body-map contact sheet into the 10 named PNGs.
# Usage: ./slice-bodymaps.sh /path/to/contact-sheet.png
# Uses sips (built into macOS) - no extra tooling required.

set -euo pipefail

SRC="${1:?usage: slice-bodymaps.sh <contact-sheet.png>}"
OUT="$(cd "$(dirname "$0")" && pwd)/assets/bodymap"
mkdir -p "$OUT"

W=$(sips -g pixelWidth  "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
echo "source ${W}x${H}"

# Trim the chrome: top title band, and the bottom toolbar (Zoom / Reset Map).
TOP=${TOP:-40}
BOTTOM=${BOTTOM:-80}
GRID_H=$(( H - TOP - BOTTOM ))

COLS=5
ROWS=2
CELL_W=$(( W / COLS ))
CELL_H=$(( GRID_H / ROWS ))

# Per-cell inset so the neighbouring figure never bleeds in.
INSET=${INSET:-6}

names=(rest push pull legs chest back shoulders arms core full-body)

i=0
for r in $(seq 0 $((ROWS-1))); do
  for c in $(seq 0 $((COLS-1))); do
    name="${names[$i]}"
    x=$(( c * CELL_W + INSET ))
    y=$(( TOP + r * CELL_H ))
    w=$(( CELL_W - INSET * 2 ))
    h=$(( CELL_H ))
    cp "$SRC" "$OUT/$name.png"
    sips -c "$h" "$w" --cropOffset "$y" "$x" "$OUT/$name.png" >/dev/null
    echo "  $name.png  ${w}x${h}  @ ${x},${y}"
    i=$(( i + 1 ))
  done
done

echo "wrote ${#names[@]} files to $OUT"
