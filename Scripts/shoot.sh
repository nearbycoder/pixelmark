#!/usr/bin/env bash
# Captures the measuring overlay, driven by a harness script, without covering the screen (Debug builds only).
#   ./Scripts/shoot.sh <backdrop.png> <output.png> "move 900 400; drag 10 10 200 80"
set -euo pipefail
cd "$(dirname "$0")/.."
BACKDROP="$1" OUT="$2" SCRIPT="$3"
APP="build/DerivedData/Build/Products/Debug/PixelMark.app/Contents/MacOS/PixelMark"
LOG="$(mktemp)"
PIXELMARK_DEMO_IMAGE="$BACKDROP" PIXELMARK_HARNESS="$SCRIPT" "$APP" >"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -f "$LOG"' EXIT
for _ in $(seq 1 100); do
  grep -q HARNESS_WINDOW "$LOG" && break
  sleep 0.1
done
WINDOW="$(awk '/HARNESS_WINDOW/ {print $2; exit}' "$LOG")"
[[ -n "$WINDOW" ]] || { cat "$LOG"; exit 1; }
sleep "${SETTLE:-1.2}" # let SwiftUI animations and glass settle
screencapture -x -o -l "$WINDOW" "$OUT"
echo "✓ $OUT"
