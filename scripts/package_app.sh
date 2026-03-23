#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="CodexTray"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Unsupported configuration: $CONFIGURATION" >&2
  echo "Usage: scripts/package_app.sh [release|debug]" >&2
  exit 1
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Executable not found at $BIN_PATH" >&2
  exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/AppBundle/PkgInfo" "$CONTENTS_DIR/PkgInfo"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "Bundle ready at:"
echo "$APP_DIR"
