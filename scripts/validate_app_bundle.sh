#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/CodexTray.app}"

[[ -d "$APP_DIR" ]]
[[ -f "$APP_DIR/Contents/Info.plist" ]]
[[ -f "$APP_DIR/Contents/PkgInfo" ]]
[[ -x "$APP_DIR/Contents/MacOS/CodexTray" ]]

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_DIR/Contents/Info.plist" | grep -q '^CodexTray$'
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_DIR/Contents/Info.plist" | grep -q '^true$'

echo "App bundle looks valid:"
echo "$APP_DIR"
