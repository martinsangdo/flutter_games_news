#!/usr/bin/env bash
# Renders assets/icon/feature_graphic.html to the Google Play feature graphic:
# exactly 1024x500, 24-bit PNG without an alpha channel (Play rejects alpha).
# Needs Google Chrome (macOS path below) and network access for the web font.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SRC="assets/icon/feature_graphic.html"
OUT="assets/icon/feature_graphic.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1024,500 \
  --virtual-time-budget=8000 \
  --screenshot="$TMP/shot.png" "file://$PWD/$SRC" >/dev/null 2>&1

# PNG -> JPEG -> PNG drops the alpha channel (sips keeps RGB only for JPEG).
sips -s format jpeg -s formatOptions 100 "$TMP/shot.png" --out "$TMP/shot.jpg" >/dev/null
sips -s format png "$TMP/shot.jpg" --out "$OUT" >/dev/null
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT"
