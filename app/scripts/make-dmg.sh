#!/bin/zsh
# Packs "Murmr Stream.app" (from scripts/bundle.sh) into a .dmg: the app next to a shortcut to Applications, so the
# person opens it and drags one onto the other. Writes build/Murmr-Stream-<version>.dmg and a .sha256 beside it.
set -euo pipefail
cd "${0:A:h}/.."   # app/

VERSION="$(tr -d '[:space:]' < ../VERSION)"
APP="build/Murmr Stream.app"
OUT="build/Murmr-Stream-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "no $APP: run scripts/bundle.sh first"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Murmr Stream $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" > /dev/null
( cd build && shasum -a 256 "Murmr-Stream-$VERSION.dmg" > "Murmr-Stream-$VERSION.dmg.sha256" )
echo "built: $PWD/$OUT ($(du -h "$OUT" | cut -f1))"
cat "$OUT.sha256"
