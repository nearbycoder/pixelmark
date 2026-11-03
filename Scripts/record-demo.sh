#!/usr/bin/env bash
# Records the feature walkthrough for the website into docs/assets/demo.mp4 (+ poster).
# Chapter times land in build/demo/chapters.tsv; copy them into the chapter list in docs/index.html.
# Plays behind your other windows; needs a Debug build and ffmpeg.
#   ./Scripts/record-demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="build/demo"
mkdir -p "$WORK" docs/assets
APP="build/DerivedData/Build/Products/Debug/PixelMark.app/Contents/MacOS/PixelMark"

[[ -f "$WORK/backdrop.png" ]] || swift Scripts/make-demo-backdrop.swift "$WORK/backdrop.png"

echo "→ Recording (about a minute and a half)"
PIXELMARK_DEMO_IMAGE="$WORK/backdrop.png" PIXELMARK_HARNESS="video:$PWD/$WORK/raw.mov" "$APP" | tee "$WORK/record.log"
grep -q VIDEO_DONE "$WORK/record.log"
grep CHAPTER "$WORK/record.log" | cut -f1-3 > "$WORK/chapters.tsv"

echo "→ Encoding"
ffmpeg -y -loglevel error -i "$WORK/raw.mov" \
  -vf "fps=60,format=yuv420p" \
  -c:v libx264 -preset slow -crf 22 -profile:v high -movflags +faststart -an docs/assets/demo.mp4
ffmpeg -y -loglevel error -ss 9 -i docs/assets/demo.mp4 -frames:v 1 -q:v 3 docs/assets/demo-poster.jpg
ls -lh docs/assets/demo.mp4 docs/assets/demo-poster.jpg
