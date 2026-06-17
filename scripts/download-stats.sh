#!/usr/bin/env bash
# Prints TabTypist download counts from GitHub release assets.
#
# GitHub counts every asset download, including Sparkle auto-updates (they hit the
# same release asset), so this is the most complete "total downloads" figure.
#
# Usage: bash scripts/download-stats.sh
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'mmexploit/TabTypist')}"

echo "==> Download counts for ${REPO}"
echo

gh api "repos/${REPO}/releases" --jq '
  .[] | "  \(.tag_name)\(if .prerelease then " (pre)" else "" end):\n" +
        ([.assets[] | "    \(.name): \(.download_count)"] | join("\n"))' \
  | sed 's/\\n/\n/g'

echo
TOTAL=$(gh api "repos/${REPO}/releases" --jq '
  [ .[].assets[] | select(.name|endswith(".dmg")) | .download_count ] | add // 0')
echo "==> Total DMG downloads (all releases): ${TOTAL}"
