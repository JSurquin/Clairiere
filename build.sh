#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

sign_app() {
  local app="$1"
  if [[ -n "${CI:-}" ]]; then
    codesign --force --sign - "$app"
    return
  fi
  if ensure_signing_identity && codesign --force --sign "Clairiere Local" --identifier local.jimmy.clairiere "$app"; then
    return
  fi
  codesign --force --sign - "$app"
  echo "signature temporaire : macOS peut redemander l’accès aux dossiers à la prochaine compilation" >&2
}

ensure_signing_identity() {
  local name="Clairiere Local"
  security find-certificate -c "$name" >/dev/null 2>&1 && return 0
  local work keychain
  work="$(mktemp -d)"
  keychain="$HOME/Library/Keychains/login.keychain-db"
  [[ -f "$keychain" ]] || keychain="$HOME/Library/Keychains/login.keychain"
  cat > "$work/cert.cfg" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = codesign
prompt = no
[req_dn]
CN = $name
[codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -config "$work/cert.cfg" -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1 \
    && openssl pkcs12 -export -legacy -out "$work/cert.p12" \
      -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" -passout pass:clairiere >/dev/null 2>&1 \
    && security import "$work/cert.p12" -k "$keychain" -P clairiere -A \
      -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1
  then
    rm -rf "$work"
    return 0
  fi
  rm -rf "$work"
  return 1
}

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
xattr -cr "$APP" 2>/dev/null || true
sign_app "$APP"
echo "built $APP"
