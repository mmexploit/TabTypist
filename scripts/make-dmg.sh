#!/usr/bin/env bash
# Creates a distributable DMG: TabTypist.app + /Applications symlink.
# Usage: bash scripts/make-dmg.sh
set -euo pipefail

APP="dist/TabTypist.app"
DMG_OUT="dist/TabTypist.dmg"
DMG_RW="dist/TabTypist-rw.dmg"
VOLUME_NAME="TabTypist"

[ -d "$APP" ] || { echo "ERROR: $APP not found — run bundle.sh first." >&2; exit 1; }

echo "==> Creating DMG..."
rm -f "$DMG_OUT" "$DMG_RW"

# Build a writable staging DMG large enough for the app + a little headroom.
APP_SIZE_MB=$(du -sm "$APP" | awk '{print $1}')
DMG_SIZE_MB=$(( APP_SIZE_MB + 10 ))

hdiutil create \
    -size "${DMG_SIZE_MB}m" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=16,a=16,b=16" \
    -format UDRW \
    "$DMG_RW"

DEVICE=$(hdiutil attach -readwrite -noverify "$DMG_RW" | awk 'NR==1{print $1}')
MOUNT="/Volumes/$VOLUME_NAME"

cp -R "$APP" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"

# Window layout hint via bless (no AppleScript / Finder dependency in CI).
bless --folder "$MOUNT" --openfolder "$MOUNT" 2>/dev/null || true

sync
hdiutil detach "$DEVICE"

# Compress into the final read-only DMG.
hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_OUT"
rm -f "$DMG_RW"

echo "==> DMG ready: $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))"
