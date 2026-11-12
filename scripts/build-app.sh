#!/usr/bin/env bash
# Baut Polux.app (Universal: Apple Silicon + Intel) und ein ZIP zum Verteilen.
# Voraussetzung: macOS 13+ mit Xcode bzw. Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION)}"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:---arch arm64 --arch x86_64}"

echo "==> Kompiliere Polux $VERSION ($BUILD)"
# shellcheck disable=SC2086
swift build -c release $ARCHS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCHS --show-bin-path)"

APP="dist/Polux.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Polux" "$APP/Contents/MacOS/Polux"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> App-Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc-Signatur"
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" "dist/Polux-$VERSION.zip"
echo "==> Fertig: dist/Polux.app und dist/Polux-$VERSION.zip"
