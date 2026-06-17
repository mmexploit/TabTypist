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
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle_pk.txt
#   cat /tmp/sparkle_pk.txt | pbcopy && rm /tmp/sparkle_pk.txt
#   gh secret set SPARKLE_PRIVATE_KEY   # paste from clipboard
#
# Output: dist/appcast.xml — uploaded as a release asset and served via
#         https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml
#         (matches SUFeedURL in Resources/Info.plist).
set -euo pipefail

FEED_URL="https://github.com/${GITHUB_REPOSITORY:-mmexploit/TabTypist}/releases/latest/download/appcast.xml"

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
# Resolve owner/repo. In GitHub Actions GITHUB_REPOSITORY is always set; locally
# fall back to gh. The previous hard-coded 'tabtypist/TabTypist' fallback produced
# 404 download URLs in CI when gh wasn't authed — do not reintroduce it.
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[ -n "$REPO" ] || { echo "ERROR: could not determine owner/repo (set GITHUB_REPOSITORY)." >&2; exit 1; }
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/TabTypist.dmg"

echo "==> Signing DMG with EdDSA key..."
# sign_update reads its key from the Keychain by default; the deprecated -s flag
# no longer works for newly generated keys. In CI we pipe the base64 private key
# (from the SPARKLE_PRIVATE_KEY secret) to stdin via --ed-key-file -. On a dev
# machine with no secret set, fall back to the Keychain. -p prints only the
# signature (no length= metadata), matching the enclosure template below.
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SIGNATURE=$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$DMG")
else
    SIGNATURE=$("$SIGN_UPDATE" -p "$DMG")
fi

mkdir -p dist
cat > dist/appcast.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>TabTypist Changelog</title>
        <link>${FEED_URL}</link>
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

echo "==> appcast feed → dist/appcast.xml"
echo "    Served at: ${FEED_URL}"
echo "    Signature: ${SIGNATURE}"
