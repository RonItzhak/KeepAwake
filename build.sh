#!/bin/bash
# Builds Keep Awake into ~/Applications/KeepAwake.app and optionally launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${KEEP_AWAKE_APP:-$HOME/Applications/KeepAwake.app}"
MACOS="$APP/Contents/MacOS"
BINARY="$MACOS/KeepAwake"

echo "Compiling Keep Awake…"
swiftc -parse-as-library -O \
  -target arm64-apple-macos14 \
  -o /tmp/KeepAwake \
  "$ROOT/Sources/KeepAwakeApp.swift" \
  "$ROOT/Sources/KeepAwakeController.swift" \
  "$ROOT/Sources/KeepAwakeLog.swift" \
  "$ROOT/Sources/PowerManager.swift" \
  "$ROOT/Sources/TouchAuth.swift" \
  -framework AppKit \
  -framework Carbon \
  -framework LocalAuthentication \
  -framework ServiceManagement

/tmp/KeepAwake --self-check

mkdir -p "$MACOS" "$APP/Contents/Resources"
install -m 0755 /tmp/KeepAwake "$BINARY"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -f "$ROOT/Resources/install-pmset-sudoers.sh" ]; then
  cp "$ROOT/Resources/install-pmset-sudoers.sh" "$APP/Contents/Resources/install-pmset-sudoers.sh"
  chmod 0755 "$APP/Contents/Resources/install-pmset-sudoers.sh"
fi

if command -v codesign >/dev/null; then
  codesign --force --sign - "$APP" >/dev/null
fi

echo "Installed: $APP"
if [ "${1:-}" = "--launch" ]; then
  open -a "$APP"
  echo "Launched. Click the cup/moon in the menu bar to toggle."
fi
