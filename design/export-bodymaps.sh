#!/bin/bash
# Renders the ten body-map PNGs from bodymap.html using headless Chrome.
# Usage: ./export-bodymaps.sh [path/to/bodymap.html]

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$DIR/bodymap.html}"
# tip: pass bodymap.fixed.html if the source came from a Google Docs export
OUT="$DIR/assets/bodymap"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -f "$SRC" ] || { echo "no such file: $SRC"; exit 1; }
mkdir -p "$OUT"

# preset:filename
sets=(
  "rest:rest"
  "push:push"
  "pull:pull"
  "legs:legs"
  "chest:chest"
  "back:back"
  "shoulders:shoulders"
  "arms:arms"
  "core:core"
  "fullBody:full-body"
)

for pair in "${sets[@]}"; do
  preset="${pair%%:*}"
  file="${pair##*:}"
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --window-size=920,800 --force-device-scale-factor=2 \
    --screenshot="$OUT/$file.png" \
    "file://$SRC?preset=$preset" 2>/dev/null
  echo "  $file.png  ($preset)"
done

echo "wrote ${#sets[@]} files to $OUT"
