#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the artwork in Theme.swift (AppIconArt). The .icns is committed, so a normal
# build does not need this; run it only when the icon design changes, then commit the new file.
set -euo pipefail
cd "${0:A:h}/.."   # app/

swift build -c release > /dev/null
BIN="$(swift build -c release --show-bin-path)/MurmrStream"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"; mkdir "$SET"

"$BIN" --app-icon "$TMP/master.png" > /dev/null
# the sizes macOS asks for: name -> pixels
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x \
            256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  sips -z "${spec%%:*}" "${spec%%:*}" "$TMP/master.png" --out "$SET/${spec#*:}.png" > /dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
