#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swiftc -framework AppKit -framework Foundation -o /tmp/clairiere-make-icon Scripts/MakeIcon.swift
/tmp/clairiere-make-icon "$PWD/AppIcon.png"

ICONSET="$PWD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 AppIcon.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 AppIcon.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 AppIcon.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 AppIcon.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 AppIcon.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 AppIcon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 AppIcon.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 AppIcon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 AppIcon.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 AppIcon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$PWD/AppIcon.icns"

swift build -c release

BIN=""
for candidate in .build/release/Clairiere .build/out/Products/Release/Clairiere; do
  if [[ -x "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done
if [[ -z "$BIN" ]]; then
  echo "binaire introuvable après swift build" >&2
  exit 1
fi

APP="$PWD/dist/Clairiere.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clairiere"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/Clairiere"
codesign --force --sign - "$APP"
echo "built $APP"
