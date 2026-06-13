#!/usr/bin/env bash
# Assembles TabTypist.app from compiled Swift and Rust binaries.
# Usage: bash scripts/bundle.sh [--release]
set -euo pipefail

RELEASE_FLAG=""
SWIFT_BUILD_DIR=".build/debug"
RUST_BUILD_DIR="target/debug"

if [ "${1:-}" = "--release" ]; then
    RELEASE_FLAG="--release"
    SWIFT_BUILD_DIR=".build/release"
    RUST_BUILD_DIR="target/release"
fi

OUT_DIR="dist"
APP_DIR="${OUT_DIR}/TabTypist.app"

echo "==> Building Swift..."
if [ -n "$RELEASE_FLAG" ]; then
    swift build -c release
else
    swift build
fi

echo "==> Building Rust..."
cargo build $RELEASE_FLAG -p tabtypist-core

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"

cp "${SWIFT_BUILD_DIR}/TabTypist" "${APP_DIR}/Contents/MacOS/TabTypist"
cp "${RUST_BUILD_DIR}/tabtypist-core" "${APP_DIR}/Contents/Resources/tabtypist-core"
cp "Resources/ed25519_pubkey.bin" "${APP_DIR}/Contents/Resources/ed25519_pubkey.bin"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Embed Sparkle.framework (SPM places it alongside the binary in the build dir).
# Frameworks live in Contents/Frameworks; add an rpath so the binary finds them.
cp -R "${SWIFT_BUILD_DIR}/Sparkle.framework" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${APP_DIR}/Contents/MacOS/TabTypist" 2>/dev/null || true

# Sparkle bundles an Updater.app XPC helper; it must be inside the main bundle.
if [ -d "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" ]; then
    XPCSVC="${APP_DIR}/Contents/XPCServices"
    mkdir -p "$XPCSVC"
    cp -R "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/." \
        "$XPCSVC/" 2>/dev/null || true
fi

# Set SKIP_CODESIGN=1 to skip signing (CI will re-sign with Developer ID later).
if [ -n "${SKIP_CODESIGN:-}" ]; then
    echo "==> Skipping codesign (SKIP_CODESIGN set)."
    echo "==> Done: ${APP_DIR}"
    ls -lh "${APP_DIR}/Contents/MacOS/" "${APP_DIR}/Contents/Resources/"
    exit 0
fi

# Codesign. Prefer a STABLE self-signed identity ("TabTypist Dev", created by
# scripts/make-signing-cert.sh): with a real identity, macOS keys Input
# Monitoring / Accessibility grants on the designated requirement (identifier +
# certificate), so the grant survives every rebuild — you grant once.
#
# Ad-hoc (`--sign -`) is the fallback. It keys the grant on the cdhash, which
# changes on every rebuild, so the grant is revoked each time and CGEventTap
# silently drops events ("Tab does nothing"). The --identifier pin only keeps
# the bundle id stable; it does NOT stop the cdhash churn.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-TabTypist Dev}"
# NOTE: no -v — a self-signed identity is untrusted (CSSMERR_TP_NOT_TRUSTED) and
# `-v` would hide it, but it still signs fine and TCC matches on it correctly.
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "==> Codesigning with stable identity: $SIGN_IDENTITY"
    # Sign our own binary first, then the bundle top-level.
    # Sparkle.framework ships pre-signed by the Sparkle team — re-signing it with
    # --deep triggers a keychain prompt for every sub-component (Updater.app, XPC
    # services). Signing only our binary + the bundle top level triggers one prompt,
    # and Sparkle's existing Apple signature satisfies Gatekeeper.
    codesign --force --sign "$SIGN_IDENTITY" \
        --identifier com.tabtypist.TabTypist \
        "${APP_DIR}/Contents/MacOS/TabTypist"
    codesign --force --sign "$SIGN_IDENTITY" \
        --identifier com.tabtypist.TabTypist \
        "${APP_DIR}"
else
    echo "==> ⚠️  No '$SIGN_IDENTITY' identity found — falling back to AD-HOC signing."
    echo "    Input Monitoring will be revoked on every rebuild. To fix permanently:"
    echo "        bash scripts/make-signing-cert.sh"
    codesign --force --sign - --identifier com.tabtypist.TabTypist \
        "${APP_DIR}/Contents/MacOS/TabTypist"
    codesign --force --sign - --identifier com.tabtypist.TabTypist "${APP_DIR}"
fi

echo "==> Done: ${APP_DIR}"
ls -lh "${APP_DIR}/Contents/MacOS/" "${APP_DIR}/Contents/Resources/"
