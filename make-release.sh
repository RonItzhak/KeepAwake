#!/bin/bash
# Builds KeepAwake-<version>.pkg under dist/ for a GitHub release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DIST="$ROOT/dist"
APP="$DIST/KeepAwake.app"
PAYLOAD="$DIST/payload"
PKG="$DIST/KeepAwake-${VERSION}.pkg"
SCRIPTS="$ROOT/scripts/pkg"

rm -rf "$DIST"
mkdir -p "$PAYLOAD"

KEEP_AWAKE_APP="$APP" "$ROOT/build.sh"

ditto --norsrc --noextattr --noqtn "$APP" "$PAYLOAD/KeepAwake.app"
xattr -cr "$PAYLOAD"
find "$PAYLOAD" \( -name '._*' -o -name '.DS_Store' \) -delete
codesign --force --sign - "$PAYLOAD/KeepAwake.app" >/dev/null
chmod 0755 "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

pkgbuild \
  --root "$PAYLOAD" \
  --identifier com.ron.KeepAwake \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$SCRIPTS" \
  "$PKG"

rm -rf "$PAYLOAD"
echo "Built $PKG"
