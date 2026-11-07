#!/bin/zsh
# Builds "Murmr Stream.app" into app/build/. Needs only the Command Line Tools and Go.
#
#   scripts/bundle.sh                       ad-hoc signed (macOS may ask for permissions again after every rebuild)
#   MURMR_SIGN_ID="My Cert" scripts/bundle.sh   sign with a stable identity so permissions survive rebuilds
set -euo pipefail
cd "${0:A:h}/.."   # app/

APP="build/Murmr Stream.app"

echo "==> engine (Go)"
(cd .. && go build -o app/build/murmr .)

echo "==> shell (Swift)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MurmrStream"

echo "==> bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MurmrStream"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/murmr "$APP/Contents/Resources/murmr"

echo "==> sign (${MURMR_SIGN_ID:--})"
codesign --force --deep --sign "${MURMR_SIGN_ID:--}" "$APP"
codesign --verify --deep --strict "$APP"

echo "built: $PWD/$APP"
