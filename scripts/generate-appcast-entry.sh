#!/usr/bin/env bash
# Generates a Sparkle 2 appcast entry for the just-built DMG.
#
# Usage: bash scripts/generate-appcast-entry.sh <tag>
#   e.g. bash scripts/generate-appcast-entry.sh v0.1.0
#
# Env vars:
#   SPARKLE_PRIVATE_KEY — base64-encoded EdDSA private key
#                         (export from keychain: see docs below)
#
# To export the private key from your local keychain for the first time:
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys --export \
#     | base64 > /tmp/sparkle_private_key_base64.txt
#   Then add the contents as the SPARKLE_PRIVATE_KEY GitHub secret.
#
# Output: dist/appcast-entry.xml — upload/merge into https://tabtypist.com/appcast.xml
set -euo pipefail

TAG="${1:-}"
[ -n "$TAG" ] || { echo "Usage: $0 <tag>  (e.g. v0.1.0)" >&2; exit 1; }

DMG="dist/TabTypist.dmg"
[ -f "$DMG" ] || { echo "ERROR: $DMG not found." >&2; exit 1; }

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
[ -f "$SIGN_UPDATE" ] || { echo "ERROR: sign_update not found at $SIGN_UPDATE — run swift build first." >&2; exit 1; }

VERSION="${TAG#v}"
# CFBundleVersion from Info.plist (integer build number Sparkle uses for comparisons).
BUILD_NUMBER=$(defaults read "$(pwd)/Resources/Info.plist" CFBundleVersion 2>/dev/null || echo "1")
DMG_SIZE=$(stat -f%z "$DMG")
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'tabtypist/TabTypist')/releases/download/${TAG}/TabTypist.dmg"

echo "==> Signing DMG with EdDSA key..."
SIGNATURE=$(SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}" "$SIGN_UPDATE" "$DMG")

mkdir -p dist
cat > dist/appcast-entry.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>TabTypist Changelog</title>
        <link>https://tabtypist.com/appcast.xml</link>
        <description>Most recent changes.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <pubDate>${PUBDATE}</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${SIGNATURE}"
                length="${DMG_SIZE}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

echo "==> appcast entry → dist/appcast-entry.xml"
echo "    Upload to: https://tabtypist.com/appcast.xml"
echo "    Signature: ${SIGNATURE}"
