#!/usr/bin/env bash
# Creates a distributable DMG: TabTypist.app + /Applications symlink.
# Usage: bash scripts/make-dmg.sh
set -euo pipefail

APP="dist/TabTypist.app"
DMG_OUT="dist/TabTypist.dmg"
VOLUME_NAME="TabTypist"

[ -d "$APP" ] || { echo "ERROR: $APP not found — run bundle.sh first." >&2; exit 1; }

echo "==> Creating DMG..."
rm -f "$DMG_OUT"

STAGING=$(mktemp -d)
trap "rm -rf '$STAGING'" EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUT"

echo "==> DMG ready: $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))"
