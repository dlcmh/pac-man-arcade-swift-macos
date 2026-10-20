#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="release"
APP_NAME="PAC-MAN"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "→ Building release binary for $(uname -m)…"
swift build -c "$CONFIGURATION"

BINARY="$ROOT/.build/$CONFIGURATION/PacManArcade"
if [[ ! -x "$BINARY" ]]; then
    echo "Build did not produce $BINARY" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# An ad-hoc signature is enough for a locally built app and keeps Gatekeeper
# from treating the bundle as unsigned when it is moved around locally.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "→ App bundle: $APP_DIR"
echo "  open \"$APP_DIR\""
