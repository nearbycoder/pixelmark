#!/usr/bin/env bash
# Records the website's videos into docs/assets (+ posters):
#   tour      every feature            → demo.mp4
#   new       what's new in 1.2        → whats-new.mp4
# Chapter times land in build/demo/<name>-chapters.tsv; copy them into the chapter lists in docs/index.html.
# Plays behind your other windows; needs a Debug build and ffmpeg.
#   ./Scripts/record-demo.sh [tour|new|all]
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="build/demo"
mkdir -p "$WORK" docs/assets
APP="build/DerivedData/Build/Products/Debug/PixelMark.app/Contents/MacOS/PixelMark"

[[ -f "$WORK/backdrop.png" ]] || swift Scripts/make-demo-backdrop.swift "$WORK/backdrop.png"

record() { # <harness prefix> <output name> <poster second>
  local prefix="$1" name="$2" poster="$3"
  echo "→ Recording $name (about a minute)"
  PIXELMARK_DEMO_IMAGE="$WORK/backdrop.png" PIXELMARK_HARNESS="$prefix:$PWD/$WORK/$name.mov" "$APP" | tee "$WORK/$name.log"
  grep -q VIDEO_DONE "$WORK/$name.log"
  grep CHAPTER "$WORK/$name.log" | cut -f1-3 > "$WORK/$name-chapters.tsv"

  echo "→ Encoding $name"
  ffmpeg -y -loglevel error -i "$WORK/$name.mov" \
    -vf "fps=60,format=yuv420p" \
    -c:v libx264 -preset slow -crf 22 -profile:v high -movflags +faststart -an "docs/assets/$name.mp4"
  ffmpeg -y -loglevel error -ss "$poster" -i "docs/assets/$name.mp4" -frames:v 1 -q:v 3 "docs/assets/$name-poster.jpg"
  ls -lh "docs/assets/$name.mp4" "docs/assets/$name-poster.jpg"
}

case "${1:-all}" in
  tour) record video demo 9 ;;
  new) record video-new whats-new 14 ;;
  all) record video demo 9; record video-new whats-new 14 ;;
  *) echo "usage: $0 [tour|new|all]"; exit 1 ;;
esac
