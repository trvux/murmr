#!/bin/zsh
# Draws every picture the README and the release page use, once per language, into docs/en/ and docs/vi/: the banner,
# the first-launch guide and screenshots of the app. It renders offscreen with the built app (run bundle.sh first), so it
# needs no screen permission and shows no personal data (the forms-of-address page uses sample-apps.txt).
#
#   app/scripts/docs-images.sh
set -euo pipefail
cd "${0:A:h}/../.."   # repo root

BIN="app/build/Murmr Stream.app/Contents/MacOS/MurmrStream"
[[ -x "$BIN" ]] || { echo "build the app first: app/scripts/bundle.sh"; exit 1; }

for lang in en vi; do
  out="docs/$lang"
  mkdir -p "$out"
  "$BIN" --brand-banner "$out/banner-light.png" lang=$lang > /dev/null
  "$BIN" --brand-banner "$out/banner-dark.png" dark lang=$lang > /dev/null
  "$BIN" --brand-guide "$out/first-launch.png" lang=$lang > /dev/null
  "$BIN" --brand-guide "$out/first-launch-dark.png" dark lang=$lang > /dev/null
  "$BIN" --snapshot pills "$out/notch.png" lang=$lang > /dev/null
  "$BIN" --snapshot welcome1picked "$out/welcome.png" lang=$lang > /dev/null
  # the forms-of-address page, drawn in a window short enough to end above the list of apps (which is the reader's own)
  MURMR_SNAPSHOT_HEIGHT=565 MURMR_SNAPSHOT_APPS="app/scripts/sample-apps.txt" "$BIN" --snapshot apps "$out/pronouns.png" lang=$lang > /dev/null
  echo "$lang: $(ls "$out" | wc -l | tr -d ' ') images in $out"
done
