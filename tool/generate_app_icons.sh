#!/usr/bin/env bash
# Generates the app icon and every launcher icon from one glyph.
#
#   assets/icon/app_icon.svg              full icon (dark background + bolt), source
#   assets/icon/app_icon_foreground.svg   transparent glyph for Android adaptive icons
#   assets/icon/app_icon_512x512.png      Google Play hi-res icon
#   assets/icon/app_icon_1024x1024.png    App Store master (no alpha)
#   android/.../mipmap-*                  legacy + adaptive launcher icons
#   ios/.../AppIcon.appiconset            every iOS size
#   web/favicon.png, web/icons/*          PWA icons
#
# Needs Google Chrome (macOS path below) and sips (macOS). The splash logo
# (assets/icon/splash_icon_512x512.png) is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
ICON=assets/icon
RES=android/app/src/main/res
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- the glyph: a lightning bolt ("breaking news", game energy) with two pixel
# sparks, and the word "Games" under it. It is laid out around the centre of a
# 512 box (bounding box about x 61..451, y 52..430); the wrapper centres it and
# scales it ($1). Montserrat is loaded from Google Fonts while rendering.
glyph() { cat <<SVG
  <defs>
    <style>@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@800&amp;display=swap');</style>
    <linearGradient id="bolt" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7CF3FF"/><stop offset="1" stop-color="#8B6CFF"/>
    </linearGradient>
  </defs>
  <g transform="translate(256 256) scale($1) translate(-256 -241)">
    <g transform="translate(256 183) scale(0.62) translate(-262 -256)">
      <path d="M306 52L140 292H236L200 460L376 208H272Z" fill="url(#bolt)" stroke="url(#bolt)" stroke-width="14" stroke-linejoin="round"/>
      <rect x="112" y="382" width="36" height="36" rx="8" fill="#00E5FF"/>
      <rect x="392" y="104" width="24" height="24" rx="6" fill="#B9A8FF"/>
    </g>
    <text x="256" y="430" text-anchor="middle" fill="#fff" font-family="Montserrat, 'Helvetica Neue', Arial, sans-serif" font-weight="800" font-size="124" letter-spacing="-2">Games</text>
  </g>
SVG
}

# Full icon: dark navy with a violet glow, so the bolt is the only bright thing.
{ cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs><radialGradient id="bg" cx="0.3" cy="0.25" r="1">
    <stop offset="0" stop-color="#3B2BB8"/><stop offset="0.55" stop-color="#171436"/><stop offset="1" stop-color="#0B0A18"/>
  </radialGradient></defs>
  <rect width="512" height="512" fill="url(#bg)"/>
$(glyph 0.88)
</svg>
SVG
} > "$ICON/app_icon.svg"

# Adaptive-icon foreground: Android masks to a circle/squircle, so only the
# central 66/108 of the canvas is guaranteed visible; keep the glyph inside it.
{ cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
$(glyph 0.56)
</svg>
SVG
} > "$ICON/app_icon_foreground.svg"

render() { # svg out size transparent(0|1)
  local bg="ffffffff"; [ "$4" = 1 ] && bg="00000000"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color="$bg" --window-size="$3,$3" --virtual-time-budget=8000 \
    --screenshot="$2" "file://$PWD/$1" >/dev/null 2>&1
}
noalpha() { # in out : PNG -> JPEG -> PNG drops the alpha channel
  sips -s format jpeg -s formatOptions 100 "$1" --out "$TMP/na.jpg" >/dev/null
  sips -s format png "$TMP/na.jpg" --out "$2" >/dev/null
}
resize() { sips -z "$3" "$3" "$1" --out "$2" >/dev/null; } # in out px

# Chrome sizes the SVG (512 box) to the window, so render at the target size.
render "$ICON/app_icon.svg" "$TMP/full1024.png" 1024 0
noalpha "$TMP/full1024.png" "$ICON/app_icon_1024x1024.png"
resize "$ICON/app_icon_1024x1024.png" "$TMP/full512.png" 512
noalpha "$TMP/full512.png" "$ICON/app_icon_512x512.png"
render "$ICON/app_icon_foreground.svg" "$TMP/fg1024.png" 1024 1

# --- Android: legacy launcher icons + adaptive icon
for d in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r name legacy adaptive <<<"$d"
  resize "$ICON/app_icon_1024x1024.png" "$RES/mipmap-$name/ic_launcher.png" "$legacy"
  resize "$TMP/fg1024.png" "$RES/mipmap-$name/ic_launcher_foreground.png" "$adaptive"
done
mkdir -p "$RES/mipmap-anydpi-v26" "$RES/drawable"
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML
cat > "$RES/drawable/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:type="radial"
        android:centerX="0.3"
        android:centerY="0.25"
        android:gradientRadius="110%p"
        android:startColor="#3B2BB8"
        android:centerColor="#171436"
        android:endColor="#0B0A18"/>
</shape>
XML

# --- iOS: every size listed in the icon set (no alpha, no rounding: iOS masks)
python3 - "$ICON/app_icon_1024x1024.png" <<'PY'
import json, subprocess, sys
master = sys.argv[1]
d = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for i in json.load(open(f"{d}/Contents.json"))["images"]:
    size = float(i["size"].split("x")[0]) * int(i["scale"].rstrip("x"))
    subprocess.run(["sips", "-z", str(round(size)), str(round(size)), master,
                    "--out", f"{d}/{i['filename']}"], check=True, capture_output=True)
PY

# --- Web / PWA
resize "$ICON/app_icon_1024x1024.png" web/favicon.png 32
for px in 192 512; do
  resize "$ICON/app_icon_1024x1024.png" "web/icons/Icon-$px.png" "$px"
  # The glyph already sits well inside the maskable safe zone (80%).
  resize "$ICON/app_icon_1024x1024.png" "web/icons/Icon-maskable-$px.png" "$px"
done

sips -g pixelWidth -g pixelHeight -g hasAlpha "$ICON/app_icon_512x512.png"
