#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$DIR/StatsApp/Assets.xcassets/AppIcon.appiconset"
SCRIPT="$DIR/scripts/render-app-icon.swift"

declare -a SIZES=(
  "16   icon_16x16.png"
  "32   icon_16x16@2x.png"
  "32   icon_32x32.png"
  "64   icon_32x32@2x.png"
  "128  icon_128x128.png"
  "256  icon_128x128@2x.png"
  "256  icon_256x256.png"
  "512  icon_256x256@2x.png"
  "512  icon_512x512.png"
  "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  size="${entry%% *}"
  name="${entry##* }"
  swift "$SCRIPT" "$size" "$OUT/$name"
done

echo "Done. $(ls -1 "$OUT"/*.png | wc -l | tr -d ' ') PNGs generated."
