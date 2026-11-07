#!/bin/zsh
# Packs "Murmr Stream.app" (from scripts/bundle.sh) into a .dmg that looks like other Mac apps' installers: the app and a
# shortcut to Applications over a picture that says where to drag. Writes build/Murmr-Stream-<version>.dmg and a .sha256.
# Uses dmgbuild (Python), installed once into vendor/dmg-venv: it writes the window layout itself, so it needs no
# Finder scripting and works the same on a build machine with nobody logged in.
set -euo pipefail
cd "${0:A:h}/.."   # app/

VERSION="$(tr -d '[:space:]' < ../VERSION)"
APP="build/Murmr Stream.app"
OUT="build/Murmr-Stream-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "no $APP: run scripts/bundle.sh first"; exit 1; }

DMGBUILD_VERSION=1.6.7
if [[ ! -x vendor/dmg-venv/bin/dmgbuild ]]; then
  echo "==> install dmgbuild $DMGBUILD_VERSION (once)"
  python3 -m venv vendor/dmg-venv
  vendor/dmg-venv/bin/pip install --quiet "dmgbuild==$DMGBUILD_VERSION"
fi

echo "==> background picture"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
"$APP/Contents/MacOS/MurmrStream" --dmg-background "$WORK/bg.png" > /dev/null
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/bg.tiff" 2> /dev/null   # one file holding 1x and 2x

echo "==> disk image"
rm -f "$OUT"
vendor/dmg-venv/bin/dmgbuild -s scripts/dmg-settings.py \
  -D "app=$APP" -D "icon=Resources/AppIcon.icns" -D "bg=$WORK/bg.tiff" \
  "Murmr Stream $VERSION" "$OUT" > /dev/null
( cd build && shasum -a 256 "Murmr-Stream-$VERSION.dmg" > "Murmr-Stream-$VERSION.dmg.sha256" )
echo "built: $PWD/$OUT ($(du -h "$OUT" | cut -f1))"
cat "$OUT.sha256"
